#!/usr/bin/env bash
# Cleanup Script - Destroys Kind Cluster
# Part of ArgoCD GitOps migration
# Usage: ./scripts/kind/00-cleanup.sh

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kagenti-demo}"

echo "🧹 Cleaning up Kind cluster: ${CLUSTER_NAME}"
echo ""

# Check if cluster exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "📦 Deleting Kind cluster..."
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "✅ Cluster deleted"
else
    echo "ℹ️  Cluster '${CLUSTER_NAME}' does not exist, nothing to clean up"
fi

echo ""
echo "✨ Cleanup complete!"
echo ""
echo "Next steps:"
echo "  1. Create new cluster: ./scripts/kind/01-create-cluster.sh"
echo "  2. Install ArgoCD:    ./scripts/kind/02-install-argocd.sh"
echo "  3. Bootstrap apps:    ./scripts/kind/03-bootstrap-apps.sh"
