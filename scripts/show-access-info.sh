#!/usr/bin/env bash
# Display Access Information for Kagenti Platform Services
# Shows URLs, credentials, and authentication status
# All services use HTTPS with Keycloak SSO
# Use --port-forward flag to start port-forwards automatically

set -euo pipefail

# Parse arguments
PORT_FORWARD=false
if [[ "${1:-}" == "--port-forward" ]]; then
    PORT_FORWARD=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Kagenti Platform - Service Access Information       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if kubectl context is correct
CONTEXT=$(kubectl config current-context)
echo -e "${BLUE}Kubernetes Context:${NC} ${CONTEXT}"
echo ""

# Function to check if a pod is ready
check_pod_ready() {
    local namespace=$1
    local label=$2
    local ready=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    echo "$ready"
}

# Function to check if HTTPRoute exists
check_httproute() {
    local namespace=$1
    local name=$2
    kubectl get httproute -n "$namespace" "$name" &>/dev/null && echo "true" || echo "false"
}

# Function to display service info
display_service() {
    local service_name=$1
    local url=$2
    local namespace=$3
    local label=$4
    local realm=$5
    local username=$6
    local password=$7
    local auth_type=$8

    local ready=$(check_pod_ready "$namespace" "$label")
    local status_icon
    local status_color

    if [ "$ready" = "true" ]; then
        status_icon="✓"
        status_color="$GREEN"
    else
        status_icon="✗"
        status_color="$RED"
    fi

    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}${service_name}${NC}"
    echo -e "${status_color}  Status:${NC} ${status_icon} Pod Ready: ${ready}"
    echo -e "${BLUE}  URL:${NC}     ${url}"
    echo -e "${BLUE}  Auth:${NC}    ${auth_type} (${realm} realm)"
    echo -e "${GREEN}  User:${NC}    ${username}"
    echo -e "${GREEN}  Pass:${NC}    ${password}"
    echo ""
}

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  PLATFORM MANAGEMENT${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Get ArgoCD password from secret
ARGOCD_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "secret-not-found")

# Get Kubernetes Dashboard token (24h validity)
K8S_DASHBOARD_TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=24h 2>/dev/null || echo "token-generation-failed")

display_service \
    "ArgoCD (GitOps)" \
    "https://localhost:8080 (port-forward required)" \
    "argocd" \
    "app.kubernetes.io/name=argocd-server" \
    "n/a" \
    "admin" \
    "$ARGOCD_PASSWORD" \
    "Native Auth"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  AUTHENTICATION SERVICES${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

display_service \
    "Keycloak SSO" \
    "https://keycloak.localtest.me:9443" \
    "keycloak" \
    "app.kubernetes.io/name=keycloak" \
    "master" \
    "admin" \
    "admin" \
    "Admin Console"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  APPLICATION SERVICES (kagenti realm)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

display_service \
    "Kagenti UI" \
    "https://kagenti.localtest.me:9443" \
    "kagenti-system" \
    "app=kagenti-ui" \
    "kagenti" \
    "kagenti-admin" \
    "admin123" \
    "Native OIDC"

display_service \
    "Phoenix (LLM Tracing)" \
    "https://phoenix.localtest.me:9443" \
    "observability" \
    "app=phoenix" \
    "kagenti" \
    "kagenti-admin" \
    "admin123" \
    "OAuth2-Proxy"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  INFRASTRUCTURE SERVICES (kubernetes realm)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

display_service \
    "Grafana (Dashboards)" \
    "https://grafana.localtest.me:9443" \
    "observability" \
    "app=grafana" \
    "kubernetes" \
    "platform-admin" \
    "admin123" \
    "Native OIDC"

display_service \
    "Tempo (Tracing)" \
    "https://tempo.localtest.me:9443" \
    "observability" \
    "app=tempo" \
    "kubernetes" \
    "platform-admin" \
    "admin123" \
    "OAuth2-Proxy"

display_service \
    "Kiali (Service Mesh)" \
    "https://kiali.localtest.me:9443" \
    "kiali-system" \
    "app.kubernetes.io/name=kiali" \
    "kubernetes" \
    "platform-admin" \
    "admin123" \
    "OAuth2-Proxy"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  REALM USERS & PASSWORDS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Kagenti Realm (Applications):${NC}"
echo -e "  ${GREEN}kagenti-admin${NC}      / ${GREEN}admin123${NC}     (Admin role)"
echo -e "  ${GREEN}kagenti-developer${NC}  / ${GREEN}dev123${NC}       (Developer role)"
echo -e "  ${GREEN}kagenti-user${NC}       / ${GREEN}user123${NC}      (User role)"
echo ""

echo -e "${YELLOW}Kubernetes Realm (Infrastructure):${NC}"
echo -e "  ${GREEN}platform-admin${NC}     / ${GREEN}admin123${NC}     (Admin role)"
echo -e "  ${GREEN}platform-developer${NC} / ${GREEN}dev123${NC}       (Developer role)"
echo -e "  ${GREEN}platform-viewer${NC}    / ${GREEN}viewer123${NC}    (Viewer role)"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SECURITY STATUS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check strict mTLS
echo -e "${YELLOW}Istio Strict mTLS:${NC}"
MTLS_GLOBAL=$(kubectl get peerauthentication -n istio-system default-strict-mtls -o jsonpath='{.spec.mtls.mode}' 2>/dev/null || echo "NOT_SET")
if [ "$MTLS_GLOBAL" = "STRICT" ]; then
    echo -e "  ${GREEN}✓${NC} Global: ${GREEN}STRICT${NC}"
else
    echo -e "  ${RED}✗${NC} Global: ${RED}${MTLS_GLOBAL}${NC}"
fi

for ns in kagenti-system observability team1 keycloak; do
    MTLS_NS=$(kubectl get peerauthentication -n "$ns" default-strict-mtls -o jsonpath='{.spec.mtls.mode}' 2>/dev/null || echo "NOT_SET")
    if [ "$MTLS_NS" = "STRICT" ]; then
        echo -e "  ${GREEN}✓${NC} ${ns}: ${GREEN}STRICT${NC}"
    else
        echo -e "  ${RED}✗${NC} ${ns}: ${RED}${MTLS_NS}${NC}"
    fi
done
echo ""

# Check HTTPRoutes (HTTPS enforcement)
echo -e "${YELLOW}HTTPS Enforcement:${NC}"
GATEWAY_COUNT=$(kubectl get gateway -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w)
HTTPROUTE_COUNT=$(kubectl get httproute -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w)
echo -e "  ${GREEN}✓${NC} Gateways configured: ${GATEWAY_COUNT}"
echo -e "  ${GREEN}✓${NC} HTTPRoutes configured: ${HTTPROUTE_COUNT}"
echo -e "  ${GREEN}✓${NC} All routes use HTTPS (port 9443)"
echo ""

# Check TLS certificates
echo -e "${YELLOW}TLS Certificates:${NC}"
CERT_COUNT=$(kubectl get certificate -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w)
CERT_READY=$(kubectl get certificate -A -o jsonpath='{.items[?(@.status.conditions[0].status=="True")].metadata.name}' 2>/dev/null | wc -w)
echo -e "  ${GREEN}✓${NC} Certificates: ${CERT_READY}/${CERT_COUNT} ready"
echo ""

# Check Keycloak realm status
echo -e "${YELLOW}Keycloak Realms:${NC}"
REALM_IMPORT_STATUS=$(kubectl get job -n keycloak keycloak-realm-import -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
if [ "$REALM_IMPORT_STATUS" = "True" ]; then
    echo -e "  ${GREEN}✓${NC} Realm import: ${GREEN}Complete${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Realm import: ${YELLOW}${REALM_IMPORT_STATUS}${NC}"
fi

KC_CONFIG_STATUS=$(kubectl get job -n keycloak keycloak-config -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
if [ "$KC_CONFIG_STATUS" = "True" ]; then
    echo -e "  ${GREEN}✓${NC} Client config: ${GREEN}Complete${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Client config: ${YELLOW}${KC_CONFIG_STATUS}${NC}"
fi
echo ""

# Check OAuth2-Proxy secrets
echo -e "${YELLOW}OAuth2-Proxy Secrets:${NC}"
for client in tempo phoenix prometheus kiali; do
    if kubectl get secret -n oauth2-proxy "keycloak-${client}-client-secret" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${client}-client-secret exists"
    else
        echo -e "  ${RED}✗${NC} ${client}-client-secret missing"
    fi
done

if kubectl get secret -n oauth2-proxy oauth2-proxy-secrets &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} cookie-secret exists"
else
    echo -e "  ${RED}✗${NC} cookie-secret missing"
fi
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  QUICK ACCESS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}To access services:${NC}"
echo -e "  1. Navigate to the HTTPS URL above"
echo -e "  2. You'll be redirected to Keycloak login"
echo -e "  3. Login with the credentials for the appropriate realm"
echo -e "  4. After successful auth, you'll be redirected to the service"
echo ""

echo -e "${YELLOW}To access ArgoCD:${NC}"
echo -e "  ${CYAN}# Get ArgoCD admin password:${NC}"
echo -e "  ${BLUE}kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d${NC}"
echo -e "  ${CYAN}# Or read from cached file:${NC}"
echo -e "  ${BLUE}cat /tmp/argocd-pass.txt${NC}"
echo -e ""
echo -e "  ${CYAN}# Start port-forward in background:${NC}"
echo -e "  ${BLUE}kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &${NC}"
echo -e "  ${CYAN}# Check if port-forward is running:${NC}"
echo -e "  ${BLUE}lsof -i :8080${NC}"
echo -e ""
echo -e "  ${CYAN}# Then navigate to:${NC}"
echo -e "  ${BLUE}https://localhost:8080${NC}"
echo -e "  Username: ${GREEN}admin${NC}"
echo -e "  Password: ${GREEN}${ARGOCD_PASSWORD}${NC}"
echo ""

echo -e "${YELLOW}To access Keycloak Admin Console:${NC}"
echo -e "  ${BLUE}https://keycloak.localtest.me:9443${NC}"
echo -e "  Username: ${GREEN}admin${NC}"
echo -e "  Password: ${GREEN}admin${NC}"
echo ""

echo -e "${YELLOW}To access Kubernetes Dashboard:${NC}"
echo -e "  ${CYAN}# Option 1: Token Authentication (Direct)${NC}"
echo -e "  ${BLUE}https://kubernetes-dashboard.localtest.me:9443${NC}"
echo -e "  Token (24h validity): ${GREEN}${K8S_DASHBOARD_TOKEN}${NC}"
echo ""
echo -e "  ${CYAN}# Option 2: OAuth2 with Keycloak (kubernetes realm)${NC}"
echo -e "  Username: ${GREEN}platform-admin${NC} / Password: ${GREEN}admin123${NC}"
echo ""
echo -e "  ${CYAN}# To regenerate token:${NC}"
echo -e "  ${BLUE}kubectl create token admin-user -n kubernetes-dashboard --duration=24h${NC}"
echo ""

echo -e "${YELLOW}To test with curl (requires OAuth2 token):${NC}"
echo -e "  ${CYAN}# Get token from Keycloak${NC}"
echo -e "  ${BLUE}curl -X POST https://keycloak.localtest.me:9443/realms/kubernetes/protocol/openid-connect/token \\${NC}"
echo -e "    ${BLUE}-d \"client_id=grafana\" \\${NC}"
echo -e "    ${BLUE}-d \"username=platform-admin\" \\${NC}"
echo -e "    ${BLUE}-d \"password=admin123\" \\${NC}"
echo -e "    ${BLUE}-d \"grant_type=password\"${NC}"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TROUBLESHOOTING${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}If authentication fails:${NC}"
echo -e "  1. Check Keycloak pod: ${CYAN}kubectl logs -n keycloak -l app.kubernetes.io/name=keycloak${NC}"
echo -e "  2. Check realm import: ${CYAN}kubectl logs -n keycloak job/keycloak-realm-import${NC}"
echo -e "  3. Check client config: ${CYAN}kubectl logs -n keycloak job/keycloak-config${NC}"
echo -e "  4. Check OAuth2-Proxy: ${CYAN}kubectl logs -n oauth2-proxy deployment/<service>-oauth2-proxy${NC}"
echo ""

echo -e "${YELLOW}To re-run configuration jobs:${NC}"
echo -e "  ${CYAN}kubectl delete job -n keycloak keycloak-realm-import${NC}"
echo -e "  ${CYAN}kubectl delete job -n keycloak keycloak-config${NC}"
echo -e "  ${CYAN}argocd app sync platform${NC}"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  All services use HTTPS with Keycloak SSO authentication${NC}"
echo -e "${GREEN}  Istio provides strict mTLS for service-to-service traffic${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Start port-forwards if requested
if [ "$PORT_FORWARD" = true ]; then
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  STARTING PORT-FORWARDS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Check if port 8080 is already in use
    if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        EXISTING_PID=$(lsof -Pi :8080 -sTCP:LISTEN -t)
        echo -e "${YELLOW}ArgoCD port-forward already running${NC}"
        echo -e "  ${GREEN}✓${NC} ArgoCD accessible at: ${BLUE}https://localhost:8080${NC}"
        echo -e "    PID: ${EXISTING_PID}"
    else
        # Start ArgoCD port-forward
        echo -e "${YELLOW}Starting ArgoCD port-forward...${NC}"
        kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
        ARGOCD_PF_PID=$!
        sleep 2

        if kill -0 $ARGOCD_PF_PID 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} ArgoCD accessible at: ${BLUE}https://localhost:8080${NC}"
            echo -e "    PID: ${ARGOCD_PF_PID}"
        else
            echo -e "  ${RED}✗${NC} Failed to start ArgoCD port-forward"
            echo -e "    Check: kubectl get svc -n argocd argocd-server"
        fi
    fi

    echo ""
    echo -e "${YELLOW}Port-forwards running in background${NC}"
    echo -e "${YELLOW}To stop:${NC} pkill -f \"kubectl port-forward\""
    echo ""
fi
