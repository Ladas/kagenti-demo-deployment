#!/bin/bash
set -e

echo "=== Quick Redeploy: Keycloak Only ==="
echo ""

# Delete Keycloak namespace
echo "1. Deleting keycloak namespace..."
kubectl delete namespace keycloak --wait=true

# Wait for namespace deletion
echo "2. Waiting for namespace deletion..."
while kubectl get namespace keycloak >/dev/null 2>&1; do
  echo "   Waiting for namespace to be fully deleted..."
  sleep 2
done

# Sync Keycloak application
echo "3. Syncing Keycloak application via ArgoCD..."
argocd app sync keycloak --port-forward --port-forward-namespace argocd --grpc-web

# Wait for Keycloak pod
echo "4. Waiting for Keycloak pod to be ready..."
kubectl wait --for=condition=ready pod -l app=keycloak -n keycloak --timeout=300s

# Check secret extraction
echo "5. Checking oauth2-secrets-extractor Job..."
kubectl get job oauth2-secrets-extractor -n keycloak -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'

# Verify secrets created
echo ""
echo "6. Verifying secrets created:"
echo "   - grafana-client-secret: $(kubectl get secret grafana-client-secret -n keycloak -o name 2>/dev/null || echo 'NOT FOUND')"
echo "   - phoenix-client-secret: $(kubectl get secret phoenix-client-secret -n keycloak -o name 2>/dev/null || echo 'NOT FOUND')"
echo "   - kagenti-ui-oauth-secret: $(kubectl get secret kagenti-ui-oauth-secret -n keycloak -o name 2>/dev/null || echo 'NOT FOUND')"

echo ""
echo "✅ Keycloak redeployment complete!"
echo ""
echo "Next steps:"
echo "  - Test OAuth login: https://keycloak.localtest.me:9443"
echo "  - Check secrets mirrored: kubectl get secrets -A | grep client-secret"
