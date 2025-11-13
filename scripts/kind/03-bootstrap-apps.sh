#!/usr/bin/env bash
# Bootstrap ArgoCD Applications
# Part of ArgoCD GitOps migration
# Usage: ./scripts/kind/03-bootstrap-apps.sh

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kagenti-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "🚀 Bootstrapping ArgoCD Applications"
echo ""

# Verify we're connected to the right cluster
CURRENT_CONTEXT=$(kubectl config current-context)
if [[ ! "${CURRENT_CONTEXT}" == "kind-${CLUSTER_NAME}" ]]; then
    echo "❌ Wrong cluster context: ${CURRENT_CONTEXT}"
    echo "   Expected: kind-${CLUSTER_NAME}"
    exit 1
fi

# Create root Application (App-of-Apps)
echo "📦 Creating root Application (App-of-Apps)..."
kubectl apply -f "${REPO_ROOT}/argocd/bootstrap/kind/root-app.yaml"

echo "✅ Root Application created"
echo ""

# List Applications
echo "📋 ArgoCD Applications:"
argocd app list --port-forward --port-forward-namespace argocd --grpc-web
echo ""

echo "✨ Bootstrap complete!"
echo ""
echo "ℹ️  Applications are created but NOT synced (manual sync mode)"
echo ""
echo "Next steps - Sync applications using LOCAL directories:"
echo "  1. argocd app sync kagenti-platform-kind --local ${REPO_ROOT}/argocd/applications/kind-local"
echo "  2. argocd app sync infrastructure --local ${REPO_ROOT}/components/infrastructure"
echo "  3. argocd app sync platform --local ${REPO_ROOT}/components/platform"
echo "  4. argocd app sync observability --local ${REPO_ROOT}/components/observability"
echo "  5. argocd app sync agents --local ${REPO_ROOT}/components/agents"
echo ""
echo "Or use the helper script:"
echo "  ./scripts/argocd/local-sync.sh infrastructure"
echo "  ./scripts/argocd/local-sync.sh platform"
echo "  ./scripts/argocd/local-sync.sh observability"
echo "  ./scripts/argocd/local-sync.sh agents"
