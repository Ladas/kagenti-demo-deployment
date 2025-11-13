#!/bin/bash
# Master Cleanup Script - Choose Environment
# This script helps select and run the appropriate cleanup script

set -e

echo "=== Kagenti Environment Cleanup ==="
echo ""
echo "This script will help you clean up a Kagenti deployment"
echo "for redeployment purposes."
echo ""

# Detect current kubectl context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
echo "Current kubectl context: $CURRENT_CONTEXT"
echo ""

echo "Select environment to clean up:"
echo ""
echo "  1) Kind Local          (Local Kind cluster)"
echo "  2) K3s Local           (Rancher Desktop)"
echo "  3) OpenShift Stage     (External OpenShift staging)"
echo "  4) OpenShift Prod      (External OpenShift production)"
echo "  5) Cancel"
echo ""
read -p "Choose environment (1-5): " ENV_CHOICE

case $ENV_CHOICE in
  1)
    echo ""
    echo "Running Kind Local cleanup..."
    exec ./scripts/cleanup/cleanup-kind-local.sh
    ;;

  2)
    echo ""
    echo "Running K3s Local cleanup..."
    exec ./scripts/cleanup/cleanup-k3s-local.sh
    ;;

  3)
    echo ""
    echo "Running OpenShift Stage cleanup..."
    exec ./scripts/cleanup/cleanup-openshift-stage.sh
    ;;

  4)
    echo ""
    echo "⚠️  WARNING: You selected PRODUCTION environment"
    echo ""
    read -p "Are you absolutely sure? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
      echo "❌ Cancelled"
      exit 0
    fi
    echo ""
    echo "Running OpenShift Production cleanup..."
    exec ./scripts/cleanup/cleanup-openshift-prod.sh
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
