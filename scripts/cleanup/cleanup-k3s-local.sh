#!/bin/bash
# Cleanup K3s Local Environment for Redeployment
# This script removes the kagenti deployment from K3s (Rancher Desktop)
# Use this to clean up before redeploying

set -e

NAMESPACE="observability"

echo "=== K3s Local Environment Cleanup ==="
echo "Namespace: $NAMESPACE"
echo ""

# Check if we can access the cluster
if ! kubectl get nodes &>/dev/null; then
  echo "❌ Cannot access Kubernetes cluster"
  echo "Ensure Rancher Desktop is running"
  exit 1
fi

# Check if it's a K3s cluster
if ! kubectl get nodes -o json | grep -q "k3s"; then
  echo "⚠️  Warning: This doesn't appear to be a K3s cluster"
  echo "Current context: $(kubectl config current-context)"
  read -p "Continue anyway? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Cancelled"
    exit 0
  fi
fi

echo "Options:"
echo "  1) Delete observability namespace only"
echo "  2) Delete observability + ArgoCD namespaces"
echo "  3) Complete K3s reset (via Rancher Desktop UI required)"
echo "  4) Cancel"
echo ""
read -p "Choose option (1-4): " OPTION

case $OPTION in
  1)
    echo ""
    echo "🗑️  Deleting observability namespace..."

    # Create backup
    BACKUP_DIR="backups/k3s-local-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $BACKUP_DIR

    echo "📦 Creating backup..."
    kubectl get all -n $NAMESPACE -o yaml > $BACKUP_DIR/all.yaml 2>/dev/null || echo "No resources in 'all' category"
    kubectl get configmap -n $NAMESPACE -o yaml > $BACKUP_DIR/configmaps.yaml 2>/dev/null || echo "No ConfigMaps"
    kubectl get ingress -n $NAMESPACE -o yaml > $BACKUP_DIR/ingresses.yaml 2>/dev/null || echo "No Ingresses"

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
    echo "  kubectl apply -k environments/k3s-local/"
    ;;

  2)
    echo ""
    echo "🗑️  Deleting observability and ArgoCD namespaces..."

    # Create backup
    BACKUP_DIR="backups/k3s-local-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $BACKUP_DIR

    echo "📦 Creating backup..."
    kubectl get all -n $NAMESPACE -o yaml > $BACKUP_DIR/observability-all.yaml 2>/dev/null || echo "No resources in observability"
    kubectl get all -n argocd -o yaml > $BACKUP_DIR/argocd-all.yaml 2>/dev/null || echo "No resources in argocd"

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Delete namespaces
    echo "🗑️  Deleting namespaces..."
    kubectl delete namespace $NAMESPACE argocd --wait=true --timeout=2m || {
      echo "⚠️  Namespace deletion timed out or failed"
      echo "Try force delete for stuck namespaces"
      exit 1
    }

    echo ""
    echo "✅ Namespaces deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  ./scripts/deploy/bootstrap-argocd.sh"
    echo "  kubectl apply -f argocd-apps/k3s-local.yaml"
    ;;

  3)
    echo ""
    echo "ℹ️  Complete K3s Reset Instructions:"
    echo ""
    echo "K3s reset must be done via Rancher Desktop UI:"
    echo ""
    echo "1. Open Rancher Desktop application"
    echo "2. Go to: Troubleshooting menu"
    echo "3. Click: 'Reset Kubernetes'"
    echo "4. Confirm the reset"
    echo "5. Wait for Kubernetes to restart"
    echo ""
    echo "Alternative CLI method (macOS):"
    echo "  killall 'Rancher Desktop'"
    echo "  rm -rf ~/Library/Application\\ Support/rancher-desktop/k3s"
    echo "  open -a 'Rancher Desktop'"
    echo ""
    echo "After reset, redeploy:"
    echo "  kubectl apply -k environments/k3s-local/"
    ;;

  4)
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
