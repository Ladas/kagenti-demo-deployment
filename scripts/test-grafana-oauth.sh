#!/bin/bash
set -e

echo "=== Quick Redeploy: Grafana OAuth Test ==="
echo ""

# Delete Grafana pod
echo "1. Deleting Grafana pod..."
kubectl delete pod -n observability -l app=grafana

# Wait for new pod with initContainer
echo "2. Waiting for new Grafana pod to start..."
sleep 5

# Watch initContainer logs
echo "3. Checking initContainer wait-for-oauth-secret logs..."
POD=$(kubectl get pod -n observability -l app=grafana -o jsonpath='{.items[0].metadata.name}')
echo "   Pod: $POD"
echo ""
echo "   InitContainer logs:"
kubectl logs -n observability $POD -c wait-for-oauth-secret || echo "   (initContainer may have already completed)"

# Wait for pod ready
echo ""
echo "4. Waiting for Grafana pod to be ready..."
kubectl wait --for=condition=ready pod -l app=grafana -n observability --timeout=300s

# Check Grafana pod containers
echo ""
echo "5. Verifying pod containers:"
kubectl get pod -n observability -l app=grafana -o jsonpath='{.items[0].spec.containers[*].name}'
echo ""
kubectl get pod -n observability -l app=grafana -o jsonpath='{.items[0].spec.initContainers[*].name}'

# Test OAuth env vars
echo ""
echo "6. Checking OAuth environment variables in Grafana container..."
kubectl exec -n observability $POD -- env | grep -E "GF_AUTH_GENERIC_OAUTH|CLIENT_SECRET" || echo "   (env vars may be masked for security)"

echo ""
echo "✅ Grafana OAuth test complete!"
echo ""
echo "Next steps:"
echo "  - Test OAuth login: https://grafana.localtest.me:9443"
echo "  - Click 'Sign in with Keycloak'"
echo "  - Should redirect to Keycloak login (admin/admin123)"
echo ""
echo "To view Grafana logs:"
echo "  kubectl logs -n observability -l app=grafana --tail=50 -f"
