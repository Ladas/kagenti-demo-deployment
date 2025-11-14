#!/usr/bin/env bash
# Install ArgoCD on Kind Cluster
# Part of ArgoCD GitOps migration
# Based on: https://redis.io/learn/operate/ci-cd/argo-cd
# Usage: ./scripts/kind/02-install-argocd.sh

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kagenti-demo}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.9.3}"

echo "🚀 Installing ArgoCD ${ARGOCD_VERSION}"
echo ""

# Verify we're connected to the right cluster
CURRENT_CONTEXT=$(kubectl config current-context)
if [[ ! "${CURRENT_CONTEXT}" == "kind-${CLUSTER_NAME}" ]]; then
    echo "❌ Wrong cluster context: ${CURRENT_CONTEXT}"
    echo "   Expected: kind-${CLUSTER_NAME}"
    exit 1
fi

# Create ArgoCD namespace
echo "📦 Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "⬇️  Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Available --timeout=300s \
  deployment/argocd-server \
  deployment/argocd-repo-server \
  deployment/argocd-applicationset-controller \
  -n argocd

echo "✅ ArgoCD pods are ready"
echo ""

# Patch ArgoCD server to use LoadBalancer (for access via Istio Gateway)
echo "🔧 Patching ArgoCD server service to LoadBalancer..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Wait for LoadBalancer IP
echo "⏳ Waiting for LoadBalancer IP..."
sleep 5
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "✅ ArgoCD LoadBalancer IP: ${ARGOCD_IP}"
echo ""

# Get initial admin password
echo "🔑 Retrieving ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "   Username: admin"
echo "   Password: ${ARGOCD_PASSWORD}"
echo ""

# Check if ArgoCD CLI is installed
if ! command -v argocd &> /dev/null; then
    echo "⚠️  ArgoCD CLI not found"
    echo "   Installing ArgoCD CLI..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install argocd
    else
        echo "   Please install manually: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
        exit 1
    fi
fi

# Login to ArgoCD CLI using port-forward (LoadBalancer IP doesn't work from host)
echo "🔐 Logging in to ArgoCD CLI via port-forward..."
export ARGOCD_PASSWORD="${ARGOCD_PASSWORD}"
argocd login --port-forward --port-forward-namespace argocd \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --insecure \
  --grpc-web

echo "✅ ArgoCD CLI logged in"
echo ""

# Increase gRPC message size limit for large manifests (local sync)
echo "🔧 Configuring ArgoCD for large manifests..."
kubectl patch cm argocd-cmd-params-cm -n argocd --type=merge -p='{"data":{"server.grpc.max.message.size":"10485760"}}'
kubectl patch cm argocd-cmd-params-cm -n argocd --type=merge -p='{"data":{"reposerver.grpc.max.message.size":"10485760"}}'
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/argocd-repo-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=60s
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=60s
echo "✅ ArgoCD configured (10MB gRPC limit)"
echo ""

# Start port-forward for ArgoCD UI
echo "🌐 Starting port-forward for ArgoCD UI..."
kubectl port-forward -n argocd svc/argocd-server 8080:443 > /tmp/argocd-ui-pf.log 2>&1 &
ARGOCD_PF_PID=$!
sleep 2
echo "✅ ArgoCD UI available at: https://localhost:8080"
echo "   Username: admin"
echo "   Password: ${ARGOCD_PASSWORD}"
echo "   (port-forward PID: $ARGOCD_PF_PID)"
echo ""

# Create HTTPRoute for ArgoCD UI (if Gateway exists)
if kubectl get gateway external-gateway -n default &>/dev/null; then
    echo "🌐 Creating HTTPRoute for ArgoCD UI..."
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  parentRefs:
  - name: external-gateway
    namespace: default
    sectionName: https
  hostnames:
  - "argocd.localtest.me"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: argocd-server
      port: 443
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-server-http-redirect
  namespace: argocd
spec:
  parentRefs:
  - name: external-gateway
    namespace: default
    sectionName: http
  hostnames:
  - "argocd.localtest.me"
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        port: 9443
EOF
    echo "✅ ArgoCD UI available at: https://argocd.localtest.me:9443"
else
    echo "ℹ️  No Gateway found, ArgoCD UI accessible via LoadBalancer only"
fi
echo ""

echo "✨ ArgoCD installation complete!"
echo ""
echo "📊 Access ArgoCD:"
echo "   Web UI:  https://argocd.localtest.me:9443 (if Gateway exists)"
echo "   CLI:     argocd app list"
echo ""
echo "Next steps:"
echo "  1. Bootstrap applications: ./scripts/kind/03-bootstrap-apps.sh"
echo "  2. Sync applications:      argocd app sync <app-name> --local /path/to/component"
