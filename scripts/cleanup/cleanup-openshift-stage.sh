#!/bin/bash
# Cleanup OpenShift Stage Environment for Redeployment
# This script removes the kagenti deployment from OpenShift staging cluster
# Use this to clean up before redeploying

set -e

NAMESPACE="observability"
ENVIRONMENT="stage"

echo "=== OpenShift Stage Environment Cleanup ==="
echo "Namespace: $NAMESPACE"
echo "Environment: $ENVIRONMENT"
echo ""

# Detect if we're using oc or kubectl
if command -v oc &>/dev/null && oc whoami &>/dev/null; then
  CLI="oc"
  CLI_NAME="OpenShift"
else
  echo "❌ Not logged into OpenShift cluster"
  echo ""
  echo "Login first:"
  echo "  oc login https://api.your-cluster.example.com:6443"
  exit 1
fi

echo "Logged in as: $(oc whoami)"
echo "Cluster: $(oc whoami --show-server)"
echo ""

# Verify it's not production
CLUSTER_URL=$(oc whoami --show-server)
if echo "$CLUSTER_URL" | grep -qi "prod"; then
  echo "⚠️  WARNING: Detected 'prod' in cluster URL!"
  echo "This script is for STAGE environment only"
  echo "For production, use: cleanup-openshift-prod.sh"
  exit 1
fi

echo "Options:"
echo "  1) Delete observability namespace only"
echo "  2) Delete observability + kagenti-system namespaces"
echo "  3) Delete observability + kagenti-system + team1 namespaces"
echo "  4) Delete observability + ArgoCD namespaces"
echo "  5) Cancel"
echo ""
read -p "Choose option (1-5): " OPTION

# Create backup directory
BACKUP_DIR="backups/openshift-stage-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

case $OPTION in
  1)
    echo ""
    echo "🗑️  Deleting observability namespace..."

    # Backup
    echo "📦 Creating backup..."
    oc get all -n $NAMESPACE -o yaml > $BACKUP_DIR/all.yaml 2>/dev/null || echo "No resources in 'all' category"
    oc get configmap -n $NAMESPACE -o yaml > $BACKUP_DIR/configmaps.yaml 2>/dev/null || echo "No ConfigMaps"
    oc get secret -n $NAMESPACE -o yaml > $BACKUP_DIR/secrets.yaml 2>/dev/null || echo "No Secrets"
    oc get route -n $NAMESPACE -o yaml > $BACKUP_DIR/routes.yaml 2>/dev/null || echo "No Routes"
    oc get pvc -n $NAMESPACE -o yaml > $BACKUP_DIR/pvcs.yaml 2>/dev/null || echo "No PVCs"

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Confirmation
    echo "⚠️  This will delete namespace: $NAMESPACE"
    read -p "Type 'DELETE' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespace
    echo ""
    echo "🗑️  Deleting namespace '$NAMESPACE'..."
    oc delete namespace $NAMESPACE --wait=false

    # Wait for deletion
    echo "⏳ Waiting for namespace deletion (timeout: 5min)..."
    START_TIME=$(date +%s)
    TIMEOUT=300

    while oc get namespace $NAMESPACE &>/dev/null; do
      CURRENT_TIME=$(date +%s)
      ELAPSED=$((CURRENT_TIME - START_TIME))

      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo ""
        echo "⚠️  Timeout reached. Namespace may be stuck."
        echo "Try force delete: ./scripts/cleanup/force-delete-namespace.sh $NAMESPACE"
        exit 1
      fi

      echo -n "."
      sleep 2
    done

    echo ""
    echo "✅ Namespace '$NAMESPACE' deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  oc apply -k environments/openshift-stage/"
    ;;

  2)
    echo ""
    echo "🗑️  Deleting observability + kagenti-system namespaces..."

    # Backup
    echo "📦 Creating backup..."
    for ns in observability kagenti-system; do
      oc get all -n $ns -o yaml > $BACKUP_DIR/$ns-all.yaml 2>/dev/null || echo "No resources in $ns"
      oc get configmap -n $ns -o yaml > $BACKUP_DIR/$ns-configmaps.yaml 2>/dev/null || true
      oc get route -n $ns -o yaml > $BACKUP_DIR/$ns-routes.yaml 2>/dev/null || true
    done

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Confirmation
    echo "⚠️  This will delete namespaces: observability, kagenti-system"
    read -p "Type 'DELETE' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespaces
    echo ""
    echo "🗑️  Deleting namespaces..."
    oc delete namespace observability kagenti-system --wait=true --timeout=5m || {
      echo "⚠️  Some namespaces may be stuck. Check with:"
      echo "  oc get namespaces | grep Terminating"
      exit 1
    }

    echo ""
    echo "✅ Namespaces deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  oc apply -k environments/openshift-stage/"
    ;;

  3)
    echo ""
    echo "🗑️  Deleting observability + kagenti-system + team1 namespaces..."

    # Backup
    echo "📦 Creating backup..."
    for ns in observability kagenti-system team1; do
      oc get all -n $ns -o yaml > $BACKUP_DIR/$ns-all.yaml 2>/dev/null || echo "No resources in $ns"
      oc get configmap -n $ns -o yaml > $BACKUP_DIR/$ns-configmaps.yaml 2>/dev/null || true
      oc get route -n $ns -o yaml > $BACKUP_DIR/$ns-routes.yaml 2>/dev/null || true
    done

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Confirmation
    echo "⚠️  This will delete namespaces: observability, kagenti-system, team1"
    read -p "Type 'DELETE ALL' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE ALL" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespaces
    echo ""
    echo "🗑️  Deleting namespaces..."
    oc delete namespace observability kagenti-system team1 --wait=true --timeout=5m || {
      echo "⚠️  Some namespaces may be stuck. Check with:"
      echo "  oc get namespaces | grep Terminating"
      exit 1
    }

    echo ""
    echo "✅ Namespaces deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  oc apply -k environments/openshift-stage/"
    ;;

  4)
    echo ""
    echo "🗑️  Deleting observability + ArgoCD namespaces..."

    # Backup
    echo "📦 Creating backup..."
    for ns in observability argocd; do
      oc get all -n $ns -o yaml > $BACKUP_DIR/$ns-all.yaml 2>/dev/null || echo "No resources in $ns"
      oc get configmap -n $ns -o yaml > $BACKUP_DIR/$ns-configmaps.yaml 2>/dev/null || true
      oc get secret -n $ns -o yaml > $BACKUP_DIR/$ns-secrets.yaml 2>/dev/null || true
      oc get route -n $ns -o yaml > $BACKUP_DIR/$ns-routes.yaml 2>/dev/null || true
    done

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Confirmation
    echo "⚠️  This will delete namespaces: observability, argocd"
    echo "This will remove GitOps automation!"
    read -p "Type 'DELETE GITOPS' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE GITOPS" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespaces
    echo ""
    echo "🗑️  Deleting namespaces..."
    oc delete namespace observability argocd --wait=true --timeout=5m || {
      echo "⚠️  Some namespaces may be stuck. Check with:"
      echo "  oc get namespaces | grep Terminating"
      exit 1
    }

    echo ""
    echo "✅ Namespaces deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  ./scripts/deploy/bootstrap-argocd.sh"
    echo "  kubectl apply -f argocd-apps/openshift-stage.yaml"
    ;;

  5)
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
