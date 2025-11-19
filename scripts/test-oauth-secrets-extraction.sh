#!/bin/bash
set -e

echo "=== Quick Redeploy: OAuth Secrets Extraction Test ==="
echo ""

# Delete existing secrets
echo "1. Deleting existing OAuth secrets..."
kubectl delete secret grafana-client-secret -n keycloak --ignore-not-found
kubectl delete secret phoenix-client-secret -n keycloak --ignore-not-found
kubectl delete secret kagenti-ui-oauth-secret -n keycloak --ignore-not-found
kubectl delete secret grafana-client-secret -n observability --ignore-not-found
kubectl delete secret phoenix-client-secret -n oauth2-proxy --ignore-not-found
kubectl delete secret kagenti-ui-oauth-secret -n kagenti-system --ignore-not-found

# Delete job
echo "2. Deleting oauth2-secrets-extractor Job..."
kubectl delete job oauth2-secrets-extractor -n keycloak --ignore-not-found

# Wait for deletion
sleep 5

# Re-trigger job (ArgoCD will recreate it)
echo "3. Syncing Keycloak application to recreate Job..."
argocd app sync keycloak --port-forward --port-forward-namespace argocd --grpc-web --timeout 120

# Watch job
echo "4. Waiting for Job to complete..."
kubectl wait --for=condition=complete job/oauth2-secrets-extractor -n keycloak --timeout=120s

# Check job logs
echo ""
echo "5. Job logs:"
kubectl logs -n keycloak job/oauth2-secrets-extractor --tail=50

# Verify secrets in keycloak namespace
echo ""
echo "6. Secrets in keycloak namespace:"
kubectl get secrets -n keycloak | grep -E "grafana|phoenix|kagenti-ui"

# Wait for Reflector to mirror
echo ""
echo "7. Waiting 10s for Reflector to mirror secrets..."
sleep 10

# Verify secrets mirrored to target namespaces
echo ""
echo "8. Secrets mirrored to target namespaces:"
echo "   Observability namespace (grafana-client-secret):"
kubectl get secret grafana-client-secret -n observability -o jsonpath='{.metadata.annotations}' | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))"

echo ""
echo "   OAuth2-Proxy namespace (phoenix-client-secret):"
kubectl get secret phoenix-client-secret -n oauth2-proxy -o jsonpath='{.metadata.annotations}' | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))"

echo ""
echo "   Kagenti-System namespace (kagenti-ui-oauth-secret):"
kubectl get secret kagenti-ui-oauth-secret -n kagenti-system -o jsonpath='{.metadata.annotations}' | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))"

echo ""
echo "✅ OAuth secrets extraction test complete!"
echo ""
echo "Secrets created:"
echo "  ✓ grafana-client-secret (keycloak → observability)"
echo "  ✓ phoenix-client-secret (keycloak → oauth2-proxy)"
echo "  ✓ kagenti-ui-oauth-secret (keycloak → kagenti-system)"
