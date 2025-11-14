#!/bin/bash
set -euo pipefail

# Kagenti Demo Deployment - Kind Cluster
# Production-grade GitOps deployment following FINAL_TODO_LIST.md
#
# This script:
# 1. Creates Kind cluster with proper configuration
# 2. Installs prerequisites (Istio, Gateway API CRDs)
# 3. Deploys all components via Kustomize
# 4. Validates deployment
#
# Usage: ./scripts/deploy/deploy-kind.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_step() {
    echo -e "${BLUE}▶${NC} $1"
}

# Configuration
CLUSTER_NAME="kagenti-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🚀 Kagenti Demo Deployment - Kind Cluster"
echo "=========================================="
echo
echo "Repository: $REPO_ROOT"
echo "Cluster Name: $CLUSTER_NAME"
echo
echo "⚠️  NOTE: This deployment is currently INCOMPLETE per FINAL_TODO_LIST.md"
echo "   Missing: Keycloak, Kagenti UI, Internal Registry, OTEL, Ollama"
echo "   Security: No authentication, hardcoded credentials (NOT production-ready)"
echo
read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Deployment cancelled"
    exit 0
fi
echo

# ============================================================================
# Step 1: Check Prerequisites
# ============================================================================
log_step "Step 1/7: Checking prerequisites..."
echo

# Check required tools
REQUIRED_TOOLS="kind kubectl helm docker jq"
for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool &>/dev/null; then
        log_error "$tool not found. Please install it first."
        echo "  macOS: brew install $tool"
        exit 1
    fi
    log_info "$tool: $(command -v $tool)"
done

# Check kubectl version
KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' || echo "unknown")
log_info "kubectl version: $KUBECTL_VERSION"

# Check kustomize version (via kubectl)
KUSTOMIZE_VERSION=$(kubectl version --client -o json 2>/dev/null | jq -r '.kustomizeVersion' || echo "unknown")
log_info "kustomize version: $KUSTOMIZE_VERSION"

# Check helm version
HELM_VERSION=$(helm version --short 2>/dev/null || echo "unknown")
log_info "helm version: $HELM_VERSION"

# Verify Helm is v3+ (required for Kustomize helmCharts)
if ! helm version --short | grep -q "^v3"; then
    log_error "Helm v3+ required for Kustomize helmCharts feature"
    exit 1
fi

echo

# ============================================================================
# Step 2: Create Kind Cluster
# ============================================================================
log_step "Step 2/7: Creating Kind cluster..."
echo

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log_warn "Cluster '$CLUSTER_NAME' already exists"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_step "Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
        log_info "Cluster deleted"
    else
        log_info "Using existing cluster"
    fi
fi

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log_step "Creating new Kind cluster..."

    # Create Kind config with extra port mappings
    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      # HTTP/HTTPS for Istio Gateway
      - containerPort: 8080
        hostPort: 8080
        protocol: TCP
      - containerPort: 8443
        hostPort: 8443
        protocol: TCP
      # HTTPS for secure services
      - containerPort: 9443
        hostPort: 9443
        protocol: TCP
EOF

    log_info "Kind cluster created"
fi

# Wait for cluster to be ready
log_step "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s
log_info "Cluster ready"
echo

# ============================================================================
# Step 3: Install Gateway API CRDs
# ============================================================================
log_step "Step 3/7: Installing Gateway API CRDs..."
echo

GATEWAY_API_VERSION="v1.2.1"
log_step "Installing Gateway API CRDs ${GATEWAY_API_VERSION}..."

kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

log_info "Gateway API CRDs installed"
echo

# ============================================================================
# Step 4: Install Istio Service Mesh
# ============================================================================
log_step "Step 4/7: Installing Istio..."
echo

ISTIO_VERSION="1.24.2"
ISTIO_DIR="/tmp/istio-${ISTIO_VERSION}"

if [ ! -d "$ISTIO_DIR" ]; then
    log_step "Downloading Istio ${ISTIO_VERSION}..."
    cd /tmp
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
    cd "$REPO_ROOT"
    log_info "Istio downloaded"
fi

log_step "Installing Istio with ambient profile..."
"${ISTIO_DIR}/bin/istioctl" install --set profile=ambient -y

log_step "Waiting for Istio to be ready..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=ztunnel -n istio-system --timeout=300s

log_info "Istio installed and ready"
echo

# Verify Prometheus is available (required by Grafana)
log_step "Verifying Prometheus deployment..."
if kubectl get svc -n istio-system prometheus &>/dev/null; then
    log_info "Prometheus found in istio-system"
else
    log_warn "Prometheus not found - Grafana datasource will fail"
    log_warn "You may need to install Prometheus manually"
fi
echo

# ============================================================================
# Step 5: Create Istio Gateway
# ============================================================================
log_step "Step 5/7: Creating Istio Gateway..."
echo

log_step "Creating external-gateway for HTTPRoutes..."

kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external-gateway
  namespace: default
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 8080
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
EOF

log_step "Waiting for gateway to be ready..."
sleep 5
# Gateway may not get external address in Kind, but listener will be ready
if kubectl wait --for=condition=Programmed gateway/external-gateway -n default --timeout=30s 2>/dev/null; then
    log_info "Gateway fully ready"
else
    log_warn "Gateway address pending (expected in Kind), checking listener status..."
    # Verify at least the listener is programmed
    if kubectl get gateway external-gateway -n default -o jsonpath='{.status.listeners[0].conditions[?(@.type=="Programmed")].status}' | grep -q "True"; then
        log_info "Gateway listener ready (address assignment pending - this is OK in Kind)"
    else
        log_error "Gateway listener not ready"
        kubectl get gateway external-gateway -n default -o yaml
        exit 1
    fi
fi
echo

# ============================================================================
# Step 6: Deploy Kagenti Stack via Kustomize
# ============================================================================
log_step "Step 6/7: Deploying Kagenti stack..."
echo

cd "$REPO_ROOT"

log_warn "Deploying with Kustomize (this may take 5-10 minutes)..."
log_warn "Helm charts will be downloaded and templated by Kustomize"
echo

log_step "Building and applying kind-local environment..."
kubectl kustomize environments/kind-local/ --enable-helm | kubectl apply -f -

log_info "Kustomize deployment complete"
echo

# ============================================================================
# Step 7: Wait for All Components
# ============================================================================
log_step "Step 7/7: Waiting for components to be ready..."
echo

# Wait for Tekton
log_step "Waiting for Tekton Pipelines..."
kubectl wait --for=condition=ready pod -l app=tekton-pipelines-controller -n tekton-pipelines --timeout=300s 2>/dev/null || log_warn "Tekton controller not ready yet"

# Wait for Platform Operator (if Helm chart deployed successfully)
log_step "Waiting for Platform Operator..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kagenti-operator -n kagenti-system --timeout=300s 2>/dev/null || log_warn "Platform Operator not ready yet (check Helm deployment)"

# Wait for Kiali (if Helm chart deployed successfully)
log_step "Waiting for Kiali..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kiali -n kiali --timeout=300s 2>/dev/null || log_warn "Kiali not ready yet (check Helm deployment)"

# Wait for Grafana
log_step "Waiting for Grafana..."
kubectl wait --for=condition=ready pod -l app=grafana -n observability --timeout=300s 2>/dev/null || log_warn "Grafana not ready yet"

# Wait for Phoenix
log_step "Waiting for Phoenix..."
kubectl wait --for=condition=ready pod -l app=phoenix -n observability --timeout=300s 2>/dev/null || log_warn "Phoenix not ready yet"

# Wait for Kubernetes Dashboard
log_step "Waiting for Kubernetes Dashboard..."
kubectl wait --for=condition=ready pod -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=300s 2>/dev/null || log_warn "Kubernetes Dashboard not ready yet"

echo

# ============================================================================
# Display Status and Access Information
# ============================================================================
echo "================================"
echo "🎉 Deployment Complete!"
echo "================================"
echo

echo "📊 Cluster Status:"
echo
kubectl get nodes
echo

echo "📦 Deployed Components:"
echo

echo "Infrastructure:"
kubectl get pods -n tekton-pipelines 2>/dev/null | head -5 || echo "  No Tekton pods"
echo

echo "Platform:"
kubectl get pods -n kagenti-system 2>/dev/null | head -5 || echo "  No Platform Operator pods"
echo

echo "Observability:"
kubectl get pods -n observability 2>/dev/null || echo "  No observability pods"
echo

echo "Kiali:"
kubectl get pods -n kiali 2>/dev/null || echo "  No Kiali pods"
echo

echo "Kubernetes Dashboard:"
kubectl get pods -n kubernetes-dashboard 2>/dev/null || echo "  No dashboard pods"
echo

echo "Agents:"
kubectl get pods -n team1 2>/dev/null || echo "  No agent pods (expected - agents deploy via Component CRDs)"
echo

echo "📖 Access URLs (via localtest.me):"
echo "  Grafana:              http://grafana.localtest.me:8080"
echo "  Kiali:                http://kiali.localtest.me:8080"
echo "  Phoenix:              http://phoenix.localtest.me:8080"
echo "  Kubernetes Dashboard: http://kubernetes-dashboard.localtest.me:8080"
echo

log_warn "⚠️  SECURITY WARNING:"
echo "  - No authentication configured (all services open)"
echo "  - Default credentials in use (admin/admin)"
echo "  - NOT production-ready"
echo
echo "See FINAL_TODO_LIST.md Phase 1 for security hardening steps"
echo

echo "📚 Useful Commands:"
echo "  View all resources:       kubectl get all -A"
echo "  View HTTPRoutes:          kubectl get httproute -A"
echo "  View Gateway status:      kubectl get gateway -A"
echo "  Delete cluster:           kind delete cluster --name $CLUSTER_NAME"
echo "  Check Helm releases:      helm list -A"
echo

echo "✅ Done!"
echo
log_info "Deployment logs available in this terminal"
