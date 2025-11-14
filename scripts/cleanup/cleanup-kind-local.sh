#!/bin/bash
# Cleanup Kind Local Environment for Redeployment
# This script removes the kagenti deployment from Kind cluster
# Use this to clean up before redeploying

set -e

CLUSTER_NAME="agent-platform"
NAMESPACE="observability"

echo "=== Kind Local Environment Cleanup ==="
echo "Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Check if Kind cluster exists
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "ℹ️  Kind cluster '$CLUSTER_NAME' does not exist"
  echo "Nothing to clean up."
  exit 0
fi

echo "Options:"
echo "  1) Delete only observability namespace (keep cluster)"
echo "  2) Delete entire Kind cluster (complete cleanup)"
echo "  3) Cancel"
echo ""
read -p "Choose option (1-3): " OPTION

case $OPTION in
  1)
    echo ""
    echo "🗑️  Deleting observability namespace..."

    # Switch to Kind context
    kubectl config use-context kind-$CLUSTER_NAME

    # Create backup
    BACKUP_DIR="backups/kind-local-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $BACKUP_DIR

    echo "📦 Creating backup..."
    kubectl get all -n $NAMESPACE -o yaml > $BACKUP_DIR/all.yaml 2>/dev/null || echo "No resources in 'all' category"
    kubectl get configmap -n $NAMESPACE -o yaml > $BACKUP_DIR/configmaps.yaml 2>/dev/null || echo "No ConfigMaps"
    kubectl get httproute -n $NAMESPACE -o yaml > $BACKUP_DIR/httproutes.yaml 2>/dev/null || echo "No HTTPRoutes"

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Delete namespace
    echo "🗑️  Deleting namespace '$NAMESPACE'..."
    kubectl delete namespace $NAMESPACE --wait=true --timeout=2m || {
      echo "⚠️  Namespace deletion timed out or failed"
      echo "Try force delete: ./scripts/cleanup/force-delete-namespace.sh $NAMESPACE"
      exit 1
    }

    echo ""
    echo "✅ Namespace '$NAMESPACE' deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  ./scripts/deploy/deploy-kind.sh"
    ;;

  2)
    echo ""
    echo "⚠️  WARNING: This will delete the entire Kind cluster!"
    echo "Cluster name: $CLUSTER_NAME"
    read -p "Type 'DELETE CLUSTER' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE CLUSTER" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    echo ""
    echo "🗑️  Deleting Kind cluster '$CLUSTER_NAME'..."
    kind delete cluster --name $CLUSTER_NAME

    echo ""
    echo "✅ Kind cluster '$CLUSTER_NAME' deleted successfully"
    echo ""
    echo "To recreate and redeploy:"
    echo "  ./scripts/deploy/deploy-kind.sh"
    ;;

  3)
    echo "❌ Cancelled"
    exit 0
    ;;

  *)
    echo "❌ Invalid option"
    exit 1
    ;;
esac

echo ""
echo "Cleanup complete! 🎉"
