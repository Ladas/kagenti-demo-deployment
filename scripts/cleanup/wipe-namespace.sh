#!/bin/bash
# Wipe OpenShift/Kubernetes namespace with safety checks
# Creates backup before deletion

set -e

NAMESPACE=${1:-observability}
ENVIRONMENT=${2:-stage}
TIMEOUT=300  # 5 minutes

echo "=== Kagenti Namespace Cleanup ==="
echo "Namespace: $NAMESPACE"
echo "Environment: $ENVIRONMENT"
echo ""

# Detect if we're using oc or kubectl
if command -v oc &>/dev/null && oc whoami &>/dev/null; then
  CLI="oc"
  CLI_NAME="OpenShift"
else
  CLI="kubectl"
  CLI_NAME="Kubernetes"
fi

echo "Using $CLI_NAME CLI: $CLI"
echo ""

# Safety check for production
if [ "$ENVIRONMENT" = "prod" ]; then
  echo "⚠️  PRODUCTION ENVIRONMENT DETECTED"
  echo "This script requires additional confirmation for production."
  read -p "Type 'DELETE PRODUCTION' to continue: " CONFIRM
  if [ "$CONFIRM" != "DELETE PRODUCTION" ]; then
    echo "❌ Cleanup cancelled"
    exit 1
  fi
fi

# Verify namespace exists
if ! $CLI get namespace $NAMESPACE &>/dev/null; then
  echo "ℹ️  Namespace $NAMESPACE does not exist"
  exit 0
fi

# Create backup
BACKUP_DIR="backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

echo "📦 Creating backup..."
$CLI get all -n $NAMESPACE -o yaml > $BACKUP_DIR/$NAMESPACE-all.yaml 2>/dev/null || echo "No resources in 'all' category"
$CLI get configmap -n $NAMESPACE -o yaml > $BACKUP_DIR/$NAMESPACE-configmaps.yaml 2>/dev/null || echo "No ConfigMaps"
$CLI get secret -n $NAMESPACE -o yaml > $BACKUP_DIR/$NAMESPACE-secrets.yaml 2>/dev/null || echo "No Secrets"
$CLI get pvc -n $NAMESPACE -o yaml > $BACKUP_DIR/$NAMESPACE-pvcs.yaml 2>/dev/null || echo "No PVCs"

# OpenShift-specific resources
if [ "$CLI" = "oc" ]; then
  oc get route -n $NAMESPACE -o yaml > $BACKUP_DIR/$NAMESPACE-routes.yaml 2>/dev/null || echo "No Routes"
fi

echo "✅ Backup created: $BACKUP_DIR"
echo ""

# Confirmation
echo "⚠️  This will delete all resources in namespace: $NAMESPACE"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "❌ Cleanup cancelled"
  exit 0
fi

# Delete namespace
echo ""
echo "🗑️  Deleting namespace $NAMESPACE..."
$CLI delete namespace $NAMESPACE --wait=false

# Wait for deletion
echo "⏳ Waiting for namespace deletion (timeout: ${TIMEOUT}s)..."
START_TIME=$(date +%s)
while $CLI get namespace $NAMESPACE &>/dev/null; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))

  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    echo "⚠️  Timeout reached. Namespace may be stuck in Terminating state."
    echo ""
    echo "To force delete, run:"
    echo "  ./scripts/cleanup/force-delete-namespace.sh $NAMESPACE"
    exit 1
  fi

  echo -n "."
  sleep 2
done

echo ""
echo "✅ Namespace $NAMESPACE deleted successfully"
echo "📁 Backup location: $BACKUP_DIR"
echo ""
