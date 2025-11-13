#!/bin/bash

echo "============================================================"
echo "   Starting All Kagenti Platform UIs"
echo "============================================================"
echo ""

# Kill any existing port-forwards
pkill -f "port-forward" 2>/dev/null
sleep 2

# Start all port-forwards in background
echo "Starting port-forwards..."

kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
sleep 1
kubectl port-forward svc/kagenti-ui -n kagenti-system 8081:8501 > /dev/null 2>&1 &
sleep 1
kubectl port-forward svc/grafana -n observability 3000:3000 > /dev/null 2>&1 &
sleep 1
kubectl port-forward svc/kiali -n kiali-system 20001:20001 > /dev/null 2>&1 &
sleep 1
kubectl port-forward svc/tempo -n observability 3100:3200 > /dev/null 2>&1 &
sleep 1
kubectl port-forward svc/phoenix -n observability 6006:6006 > /dev/null 2>&1 &
sleep 1
kubectl port-forward svc/keycloak -n keycloak 8082:8080 > /dev/null 2>&1 &
sleep 1
kubectl port-forward svc/container-registry -n cr-system 5000:5000 > /dev/null 2>&1 &

sleep 3

echo ""
echo "✅ All services are now accessible:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. ArgoCD (GitOps)"
echo "   URL:      https://localhost:8080"
echo "   Username: admin"
echo "   Password: fqtcaEMTcZWqaqhL"
echo "   Browser:  open https://localhost:8080"
echo ""
echo "2. Kagenti UI (Platform)"
echo "   URL:      http://localhost:8081"
echo "   Auth:     Keycloak SSO (kagenti realm)"
echo "   Browser:  open http://localhost:8081"
echo ""
echo "3. Grafana (Metrics)"
echo "   URL:      http://localhost:3000"
echo "   Username: admin"
echo "   Password: dummy-secret-for-testing"
echo "   Browser:  open http://localhost:3000"
echo "   Note:     Dashboards pre-loaded!"
echo ""
echo "4. Kiali (Service Mesh)"
echo "   URL:      http://localhost:20001"
echo "   Browser:  open http://localhost:20001"
echo ""
echo "5. Tempo (Distributed Tracing - Grafana)"
echo "   URL:      http://localhost:3100"
echo "   Browser:  View traces in Grafana → Explore → Tempo"
echo "   Note:     Infrastructure traces (Istio, HTTP, DB)"
echo ""
echo "6. Phoenix (LLM Observability)"
echo "   URL:      http://localhost:6006"
echo "   Browser:  open http://localhost:6006"
echo "   Note:     Agent & LLM traces only"
echo ""
echo "7. Keycloak (IAM)"
echo "   URL:      http://localhost:8082"
echo "   Username: admin"
echo "   Password: admin"
echo "   Browser:  open http://localhost:8082"
echo ""
echo "8. Container Registry"
echo "   URL:      http://localhost:5000/v2/_catalog"
echo "   Browser:  open http://localhost:5000/v2/_catalog"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press Ctrl+C to stop all port-forwards"
echo ""

# Keep script running
trap "echo ''; echo 'Stopping all port-forwards...'; pkill -f 'port-forward'; exit 0" INT TERM
wait
