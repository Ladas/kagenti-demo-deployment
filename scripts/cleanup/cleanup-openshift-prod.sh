#!/bin/bash
# Cleanup OpenShift Production Environment for Redeployment
# This script removes the kagenti deployment from OpenShift production cluster
# IMPORTANT: Production cleanup requires approval and maintenance window

set -e

NAMESPACE="observability"
ENVIRONMENT="production"

echo "=== OpenShift Production Environment Cleanup ==="
echo "Namespace: $NAMESPACE"
echo "Environment: $ENVIRONMENT"
echo ""

# Detect if we're using oc
if command -v oc &>/dev/null && oc whoami &>/dev/null; then
  CLI="oc"
else
  echo "❌ Not logged into OpenShift cluster"
  echo ""
  echo "Login first:"
  echo "  oc login https://api.prod-cluster.example.com:6443"
  exit 1
fi

echo "Logged in as: $(oc whoami)"
echo "Cluster: $(oc whoami --show-server)"
echo ""

# Verify it's production
CLUSTER_URL=$(oc whoami --show-server)
if ! echo "$CLUSTER_URL" | grep -qi "prod"; then
  echo "⚠️  WARNING: Cluster URL doesn't contain 'prod'"
  echo "Are you sure this is the production cluster?"
  read -p "Continue anyway? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Cancelled"
    exit 0
  fi
fi

# Production safety checks
echo "🔒 PRODUCTION ENVIRONMENT DETECTED"
echo ""
echo "Pre-deployment checklist:"
echo "  [ ] Approval from team lead obtained"
echo "  [ ] Maintenance window scheduled"
echo "  [ ] Stakeholders notified"
echo "  [ ] Rollback plan documented"
echo "  [ ] Current state documented"
echo ""
read -p "All checklist items completed? (yes/no): " CHECKLIST

if [ "$CHECKLIST" != "yes" ]; then
  echo "❌ Checklist not complete. Aborting for safety."
  exit 1
fi

echo ""
echo "Options:"
echo "  1) Delete observability namespace only"
echo "  2) Delete observability + kagenti-system namespaces"
echo "  3) Delete observability + kagenti-system + team1 namespaces"
echo "  4) Delete observability + ArgoCD namespaces (removes GitOps!)"
echo "  5) Cancel"
echo ""
read -p "Choose option (1-5): " OPTION

# Create backup directory
BACKUP_DIR="backups/openshift-prod-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# Additional production-specific backup
echo ""
echo "📦 Creating comprehensive production backup..."

case $OPTION in
  1)
    echo ""
    echo "🗑️  Deleting observability namespace..."

    # Comprehensive backup
    echo "📦 Backing up all resources..."
    oc get all -n $NAMESPACE -o yaml > $BACKUP_DIR/all.yaml 2>/dev/null || echo "No resources in 'all' category"
    oc get configmap -n $NAMESPACE -o yaml > $BACKUP_DIR/configmaps.yaml 2>/dev/null || echo "No ConfigMaps"
    oc get secret -n $NAMESPACE -o yaml > $BACKUP_DIR/secrets.yaml 2>/dev/null || echo "No Secrets"
    oc get route -n $NAMESPACE -o yaml > $BACKUP_DIR/routes.yaml 2>/dev/null || echo "No Routes"
    oc get pvc -n $NAMESPACE -o yaml > $BACKUP_DIR/pvcs.yaml 2>/dev/null || echo "No PVCs"
    oc get pdb -n $NAMESPACE -o yaml > $BACKUP_DIR/pdbs.yaml 2>/dev/null || echo "No PDBs"
    oc get serviceaccount -n $NAMESPACE -o yaml > $BACKUP_DIR/serviceaccounts.yaml 2>/dev/null || echo "No ServiceAccounts"
    oc get rolebinding -n $NAMESPACE -o yaml > $BACKUP_DIR/rolebindings.yaml 2>/dev/null || echo "No RoleBindings"

    # Create backup manifest
    cat > $BACKUP_DIR/BACKUP_INFO.txt <<EOF
Production Backup
=================
Date: $(date)
User: $(oc whoami)
Cluster: $(oc whoami --show-server)
Namespace: $NAMESPACE
Reason: Cleanup for redeployment

Files:
$(ls -lh $BACKUP_DIR/)
EOF

    echo "✅ Comprehensive backup created: $BACKUP_DIR"
    echo ""

    # Final confirmation
    echo "⚠️  FINAL CONFIRMATION REQUIRED"
    echo "This will delete the PRODUCTION observability namespace"
    echo "Namespace: $NAMESPACE"
    echo "Cluster: $(oc whoami --show-server)"
    echo ""
    read -p "Type 'DELETE PRODUCTION' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE PRODUCTION" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespace
    echo ""
    echo "🗑️  Deleting namespace '$NAMESPACE'..."
    oc delete namespace $NAMESPACE --wait=false

    # Wait for deletion
    echo "⏳ Waiting for namespace deletion (timeout: 10min)..."
    START_TIME=$(date +%s)
    TIMEOUT=600

    while oc get namespace $NAMESPACE &>/dev/null; do
      CURRENT_TIME=$(date +%s)
      ELAPSED=$((CURRENT_TIME - START_TIME))

      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo ""
        echo "⚠️  Timeout reached. Namespace may be stuck."
        echo "Manual intervention may be required."
        echo "Contact cluster admin or try: ./scripts/cleanup/force-delete-namespace.sh $NAMESPACE"
        exit 1
      fi

      echo -n "."
      sleep 5
    done

    echo ""
    echo "✅ Namespace '$NAMESPACE' deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  1. Update Route hostname if needed"
    echo "  2. oc apply -k environments/openshift-prod/"
    echo "  3. Monitor rollout: oc rollout status deployment/grafana -n observability"
    ;;

  2)
    echo ""
    echo "🗑️  Deleting observability + kagenti-system namespaces..."

    # Backup
    echo "📦 Creating comprehensive backup..."
    for ns in observability kagenti-system; do
      mkdir -p $BACKUP_DIR/$ns
      oc get all -n $ns -o yaml > $BACKUP_DIR/$ns/all.yaml 2>/dev/null || echo "No resources in $ns"
      oc get configmap -n $ns -o yaml > $BACKUP_DIR/$ns/configmaps.yaml 2>/dev/null || true
      oc get secret -n $ns -o yaml > $BACKUP_DIR/$ns/secrets.yaml 2>/dev/null || true
      oc get route -n $ns -o yaml > $BACKUP_DIR/$ns/routes.yaml 2>/dev/null || true
      oc get pvc -n $ns -o yaml > $BACKUP_DIR/$ns/pvcs.yaml 2>/dev/null || true
      oc get pdb -n $ns -o yaml > $BACKUP_DIR/$ns/pdbs.yaml 2>/dev/null || true
    done

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Final confirmation
    echo "⚠️  FINAL CONFIRMATION REQUIRED"
    echo "This will delete PRODUCTION namespaces: observability, kagenti-system"
    echo "Cluster: $(oc whoami --show-server)"
    echo ""
    read -p "Type 'DELETE PRODUCTION' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE PRODUCTION" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespaces
    echo ""
    echo "🗑️  Deleting namespaces..."
    oc delete namespace observability kagenti-system --wait=true --timeout=10m || {
      echo "⚠️  Some namespaces may be stuck."
      echo "Contact cluster admin for assistance."
      exit 1
    }

    echo ""
    echo "✅ Namespaces deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  oc apply -k environments/openshift-prod/"
    ;;

  3)
    echo ""
    echo "🗑️  Deleting observability + kagenti-system + team1 namespaces..."

    # Backup
    echo "📦 Creating comprehensive backup..."
    for ns in observability kagenti-system team1; do
      mkdir -p $BACKUP_DIR/$ns
      oc get all -n $ns -o yaml > $BACKUP_DIR/$ns/all.yaml 2>/dev/null || echo "No resources in $ns"
      oc get configmap -n $ns -o yaml > $BACKUP_DIR/$ns/configmaps.yaml 2>/dev/null || true
      oc get secret -n $ns -o yaml > $BACKUP_DIR/$ns/secrets.yaml 2>/dev/null || true
      oc get route -n $ns -o yaml > $BACKUP_DIR/$ns/routes.yaml 2>/dev/null || true
      oc get pvc -n $ns -o yaml > $BACKUP_DIR/$ns/pvcs.yaml 2>/dev/null || true
    done

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Final confirmation
    echo "⚠️  FINAL CONFIRMATION REQUIRED"
    echo "This will delete ALL PRODUCTION KAGENTI namespaces"
    echo "Namespaces: observability, kagenti-system, team1"
    echo "Cluster: $(oc whoami --show-server)"
    echo ""
    read -p "Type 'DELETE ALL PRODUCTION' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE ALL PRODUCTION" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespaces
    echo ""
    echo "🗑️  Deleting all Kagenti namespaces..."
    oc delete namespace observability kagenti-system team1 --wait=true --timeout=10m || {
      echo "⚠️  Some namespaces may be stuck."
      echo "Contact cluster admin for assistance."
      exit 1
    }

    echo ""
    echo "✅ All namespaces deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  oc apply -k environments/openshift-prod/"
    ;;

  4)
    echo ""
    echo "⚠️  WARNING: This will remove GitOps automation!"
    echo "🗑️  Deleting observability + ArgoCD namespaces..."

    # Backup
    echo "📦 Creating comprehensive backup..."
    for ns in observability argocd; do
      mkdir -p $BACKUP_DIR/$ns
      oc get all -n $ns -o yaml > $BACKUP_DIR/$ns/all.yaml 2>/dev/null || echo "No resources in $ns"
      oc get configmap -n $ns -o yaml > $BACKUP_DIR/$ns/configmaps.yaml 2>/dev/null || true
      oc get secret -n $ns -o yaml > $BACKUP_DIR/$ns/secrets.yaml 2>/dev/null || true
      oc get route -n $ns -o yaml > $BACKUP_DIR/$ns/routes.yaml 2>/dev/null || true
      oc get application -n $ns -o yaml > $BACKUP_DIR/$ns/applications.yaml 2>/dev/null || true
    done

    echo "✅ Backup created: $BACKUP_DIR"
    echo ""

    # Final confirmation
    echo "⚠️  CRITICAL: This removes GitOps automation!"
    echo "Namespaces: observability, argocd"
    echo "Cluster: $(oc whoami --show-server)"
    echo ""
    read -p "Type 'DELETE GITOPS PRODUCTION' to confirm: " CONFIRM

    if [ "$CONFIRM" != "DELETE GITOPS PRODUCTION" ]; then
      echo "❌ Cancelled"
      exit 0
    fi

    # Delete namespaces
    echo ""
    echo "🗑️  Deleting namespaces..."
    oc delete namespace observability argocd --wait=true --timeout=10m || {
      echo "⚠️  Some namespaces may be stuck."
      echo "Contact cluster admin for assistance."
      exit 1
    }

    echo ""
    echo "✅ Namespaces deleted successfully"
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "To redeploy:"
    echo "  ./scripts/deploy/bootstrap-argocd.sh"
    echo "  kubectl apply -f argocd-apps/openshift-prod.yaml"
    echo "  # Then manually sync in ArgoCD UI"
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
echo "Production cleanup complete! 🎉"
echo ""
echo "IMPORTANT: Document this cleanup in your change log"
