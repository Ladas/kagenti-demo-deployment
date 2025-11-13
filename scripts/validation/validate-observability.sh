#!/bin/bash
# Validate Kagenti observability stack deployment
# Works with Kind, K3s, and OpenShift

set -e

ENVIRONMENT=${1:-kind-local}
NAMESPACE="observability"

echo "=== Kagenti Observability Validation ==="
echo "Environment: $ENVIRONMENT"
echo "Namespace: $NAMESPACE"
echo ""

# Detect CLI
if command -v oc &>/dev/null && oc whoami &>/dev/null; then
  CLI="oc"
else
  CLI="kubectl"
fi

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation functions
validate_namespace() {
  echo -n "Checking namespace '$NAMESPACE'... "
  if $CLI get namespace $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    return 0
  else
    echo -e "${RED}✗${NC}"
    echo "  Namespace does not exist"
    return 1
  fi
}

validate_deployment() {
  local deployment=$1
  echo -n "Checking deployment '$deployment'... "

  if ! $CLI get deployment $deployment -n $NAMESPACE &>/dev/null; then
    echo -e "${RED}✗${NC}"
    echo "  Deployment not found"
    return 1
  fi

  local ready=$($CLI get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
  local desired=$($CLI get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.replicas}')

  if [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} ($ready/$desired pods ready)"
    return 0
  else
    echo -e "${RED}✗${NC} ($ready/$desired pods ready)"
    return 1
  fi
}

validate_service() {
  local service=$1
  echo -n "Checking service '$service'... "

  if $CLI get service $service -n $NAMESPACE &>/dev/null; then
    local cluster_ip=$($CLI get service $service -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
    echo -e "${GREEN}✓${NC} (ClusterIP: $cluster_ip)"
    return 0
  else
    echo -e "${RED}✗${NC}"
    echo "  Service not found"
    return 1
  fi
}

validate_configmap() {
  local configmap=$1
  echo -n "Checking ConfigMap '$configmap'... "

  # ConfigMaps with hash suffix
  if $CLI get configmap -n $NAMESPACE | grep -q "^${configmap}"; then
    local full_name=$($CLI get configmap -n $NAMESPACE -o name | grep "^configmap/${configmap}" | head -1)
    echo -e "${GREEN}✓${NC} ($full_name)"
    return 0
  else
    echo -e "${RED}✗${NC}"
    echo "  ConfigMap not found"
    return 1
  fi
}

validate_http_endpoint() {
  local url=$1
  local description=$2
  echo -n "Testing HTTP endpoint ($description)... "

  if curl -sf --max-time 10 "$url" > /dev/null; then
    echo -e "${GREEN}✓${NC}"
    return 0
  else
    echo -e "${RED}✗${NC}"
    echo "  URL: $url"
    return 1
  fi
}

validate_prometheus_connectivity() {
  echo -n "Testing Prometheus connectivity... "

  # Port-forward to Grafana
  $CLI port-forward -n $NAMESPACE svc/grafana 3000:3000 &>/dev/null &
  PF_PID=$!
  sleep 2

  # Test datasource
  local result=$(curl -sf http://localhost:3000/api/datasources 2>/dev/null || echo "")

  kill $PF_PID 2>/dev/null || true

  if echo "$result" | grep -q "prometheus"; then
    echo -e "${GREEN}✓${NC}"
    return 0
  else
    echo -e "${YELLOW}⚠${NC}"
    echo "  Could not verify Prometheus datasource"
    return 1
  fi
}

# Run validations
FAILED=0

echo "1. Namespace"
validate_namespace || ((FAILED++))
echo ""

echo "2. Deployments"
validate_deployment "grafana" || ((FAILED++))
echo ""

echo "3. Services"
validate_service "grafana" || ((FAILED++))
echo ""

echo "4. ConfigMaps"
validate_configmap "grafana-datasources" || ((FAILED++))
validate_configmap "grafana-dashboards-config" || ((FAILED++))
validate_configmap "grafana-dashboards" || ((FAILED++))
echo ""

# Environment-specific validation
case $ENVIRONMENT in
  kind-local)
    echo "5. Kind-specific checks"
    validate_http_endpoint "http://grafana.localtest.me:8080/api/health" "Grafana HTTPRoute" || ((FAILED++))
    ;;

  k3s-local)
    echo "5. K3s-specific checks"
    if $CLI get ingress grafana -n $NAMESPACE &>/dev/null; then
      echo -e "Ingress: ${GREEN}✓${NC}"
    else
      echo -e "Ingress: ${RED}✗${NC}"
      ((FAILED++))
    fi
    ;;

  openshift-*)
    echo "5. OpenShift-specific checks"
    if oc get route grafana -n $NAMESPACE &>/dev/null; then
      local route_host=$(oc get route grafana -n $NAMESPACE -o jsonpath='{.spec.host}')
      echo -e "Route: ${GREEN}✓${NC} (https://$route_host)"
      validate_http_endpoint "https://$route_host/api/health" "Grafana Route" || ((FAILED++))
    else
      echo -e "Route: ${RED}✗${NC}"
      ((FAILED++))
    fi
    ;;
esac

echo ""
echo "6. Prometheus Integration"
validate_prometheus_connectivity || echo "  (Warning only, not counted as failure)"
echo ""

# Summary
echo "=== Validation Summary ==="
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ All validations passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAILED validation(s) failed${NC}"
  echo ""
  echo "Troubleshooting:"
  echo "  View pods: $CLI get pods -n $NAMESPACE"
  echo "  View logs: $CLI logs -n $NAMESPACE deployment/grafana"
  echo "  View events: $CLI get events -n $NAMESPACE --sort-by='.lastTimestamp'"
  exit 1
fi
