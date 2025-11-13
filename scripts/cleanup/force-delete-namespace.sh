#!/bin/bash
# Force delete stuck namespace by removing finalizers
# Use this when namespace is stuck in Terminating state

set -e

NAMESPACE=${1:-observability}

echo "=== Force Delete Namespace ==="
echo "Namespace: $NAMESPACE"
echo ""

# Detect if we're using oc or kubectl
if command -v oc &>/dev/null && oc whoami &>/dev/null; then
  CLI="oc"
else
  CLI="kubectl"
fi

# Verify namespace exists
if ! $CLI get namespace $NAMESPACE &>/dev/null; then
  echo "ℹ️  Namespace $NAMESPACE does not exist"
  exit 0
fi

# Check if namespace is stuck
STATUS=$($CLI get namespace $NAMESPACE -o jsonpath='{.status.phase}')
if [ "$STATUS" != "Terminating" ]; then
  echo "⚠️  Namespace is not in Terminating state (status: $STATUS)"
  echo ""
  echo "Use regular delete:"
  echo "  $CLI delete namespace $NAMESPACE"
  exit 1
fi

echo "⚠️  Namespace is stuck in Terminating state"
echo ""
echo "This will forcefully remove finalizers and delete the namespace."
echo "This is a destructive operation and should only be used as a last resort."
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "❌ Cancelled"
  exit 1
fi

# Get namespace JSON
echo ""
echo "📥 Getting namespace JSON..."
$CLI get namespace $NAMESPACE -o json > /tmp/$NAMESPACE.json

# Remove finalizers
echo "🔧 Removing finalizers..."
if command -v jq &>/dev/null; then
  jq '.spec.finalizers = []' /tmp/$NAMESPACE.json > /tmp/$NAMESPACE-clean.json
else
  # Fallback if jq not available
  cat /tmp/$NAMESPACE.json | \
    sed 's/"finalizers": \[.*\]/"finalizers": []/' > /tmp/$NAMESPACE-clean.json
fi

# Replace namespace
echo "💥 Forcing namespace deletion..."
$CLI replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" \
  -f /tmp/$NAMESPACE-clean.json

# Verify deletion
echo "⏳ Verifying deletion..."
sleep 2

if $CLI get namespace $NAMESPACE &>/dev/null; then
  echo ""
  echo "❌ Namespace still exists. Manual intervention required."
  echo ""
  echo "Check for:"
  echo "1. Admission webhooks blocking deletion"
  echo "   $CLI get validatingwebhookconfigurations"
  echo "   $CLI get mutatingwebhookconfigurations"
  echo ""
  echo "2. API services unavailable"
  echo "   $CLI get apiservices"
  echo ""
  echo "3. Resources with finalizers"
  echo "   $CLI api-resources --verbs=list --namespaced -o name | xargs -n 1 $CLI get -n $NAMESPACE"
  exit 1
else
  echo ""
  echo "✅ Namespace $NAMESPACE forcefully deleted"
fi

# Cleanup temp files
rm -f /tmp/$NAMESPACE.json /tmp/$NAMESPACE-clean.json
echo ""
