# ArgoCD GitOps Workflow for Local Development

**Last Updated**: 2025-11-14

This document describes the GitOps workflow for developing Kagenti platform components using ArgoCD.

**See also**: [argocd_architecture.md](./argocd_architecture.md) for detailed architecture documentation.

---

## 🎯 Philosophy

**ALL changes to the Kind cluster happen via ArgoCD syncing from Git**. This ensures:
- ✅ Every change is tracked in Git
- ✅ No configuration drift
- ✅ Reproducible deployments
- ✅ Easy rollback
- ✅ Branch-based development

**No `kubectl apply` allowed** (except for ArgoCD installation and debugging only).

---

## 🚀 Quick Start

### Prerequisites
- Docker running
- kubectl >= 1.27
- kind >= 0.20
- argocd CLI >= 2.9
- Python 3.11+ with pytest installed

### One-Command Deployment

```bash
# Complete cluster redeploy (15-20 minutes)
./scripts/quick-redeploy.sh
```

**What it does:**
1. Auto-detects repository and branch (uses PR branch in GitHub Actions)
2. Destroys existing cluster
3. Creates new Kind cluster
4. Installs ArgoCD
5. Bootstraps applications (automatically uses detected repo/branch)
6. Optionally builds/loads agent images (prompted locally, skipped in CI)
7. Syncs root application
8. Shows final status

**Branch Detection:**
- **Local**: Uses current Git branch
- **GitHub Actions PR**: Automatically uses PR branch and fork repository
- **Default**: Falls back to `main` branch from upstream repo

**When prompted for agent images (local only):**
- `y` - Build from source (2-5 minutes)
- `n` - Load pre-built images (30 seconds)
- `skip` - Skip agents (agents will show ImagePullBackOff)
- **CI mode**: Automatically skips prompts

### Manual Deployment (if needed)

```bash
# Step-by-step deployment
./scripts/kind/00-cleanup.sh
./scripts/kind/01-create-cluster.sh
./scripts/kind/02-install-argocd.sh
./scripts/kind/03-bootstrap-apps.sh

# Optional: Load agent images
./scripts/kind/04-load-agent-images.sh build  # or 'load'

# Sync root application (creates all child apps)
argocd app sync kagenti-platform-kind \
  --port-forward --port-forward-namespace argocd --grpc-web \
  --timeout 600

# Monitor deployment
./scripts/monitor-argocd-apps.sh 900  # 15-minute timeout
```

### Check Platform Health

```bash
# Comprehensive platform status check
./scripts/platform-status.sh
```

**Checks:**
- ArgoCD applications (health & sync status)
- Platform pods (all namespaces)
- Gateway & certificates
- Istio mTLS configuration
- Service accessibility (via Gateway)
- OAuth authentication
- Integration tests (pytest)

**Runs pytest tests automatically** - shows real-time test results as they execute.

---

## 🧪 Test-Driven Development (TDD)

### GitOps + Testing Workflow

**ALWAYS follow this workflow for changes:**

```bash
# 1. Make changes in Git
vim components/02-observability/grafana/deployment.yaml

# 2. Validate syntax BEFORE committing
kustomize build components/02-observability/grafana/ > /dev/null

# 3. Commit and push
git add components/02-observability/
git commit -m "Update Grafana dashboard"
git push origin feature/grafana-dashboard

# 4. Sync from Git
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# 5. Validate deployment
./scripts/platform-status.sh

# 6. Run targeted tests
pytest tests/integration/test_observability.py::test_grafana_dashboard -v
```

### Quick Test Commands

```bash
# Fast validation (critical apps only, ~30s)
pytest tests/validation/test_app_state.py -v --only-critical

# Platform health check with tests
./scripts/platform-status.sh

# Specific component tests
pytest tests/integration/test_observability.py -v

# Full test suite
pytest tests/ -v --html=report.html
```

---

## 🔄 Development Iteration

### Standard Git-Based Workflow

```bash
# 1. Create feature branch
git checkout -b feature/update-grafana

# 2. Make changes
vim components/02-observability/grafana/deployment.yaml

# 3. Validate with kustomize
kustomize build components/02-observability/grafana/ > /dev/null

# 4. Preview changes in ArgoCD (before committing)
argocd app diff observability --port-forward --port-forward-namespace argocd --grpc-web

# 5. Commit and push
git add components/02-observability/
git commit -m "Update Grafana image to v10.2.0"
git push origin feature/update-grafana

# 6. Sync from Git
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# 7. Verify
./scripts/platform-status.sh
kubectl logs -n observability deployment/grafana --tail=50

# 8. Merge when ready
git checkout main
git merge feature/update-grafana
git push origin main
```

### Force Sync Options

```bash
# Normal sync
argocd app sync platform --port-forward --port-forward-namespace argocd --grpc-web

# Force sync (bypass cache)
argocd app sync platform --force --port-forward --port-forward-namespace argocd --grpc-web

# Hard sync (force + prune orphaned resources)
argocd app sync platform --force --prune --port-forward --port-forward-namespace argocd --grpc-web
```

**When to use `--force --prune`:**
- StatefulSet pods not recreating after config change
- ArgoCD shows "OutOfSync" but changes don't apply
- Need to ensure latest Git commit is deployed

---

## 🐛 Troubleshooting

### Debug Pods for Testing Connectivity

**Deploy debug pod to test service connectivity:**

```bash
# Deploy curl pod in namespace with Istio injection
kubectl run debug-curl \
  -n observability \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm -it \
  -- sh

# Inside pod:
curl http://grafana.observability.svc.cluster.local:3000
curl http://tempo-query-frontend.observability.svc.cluster.local:3100/ready
```

**Deploy debug pod WITHOUT Istio sidecar:**

```bash
# Use label to skip sidecar injection
kubectl run debug-curl \
  -n observability \
  --image=curlimages/curl:latest \
  --labels="sidecar.istio.io/inject=false" \
  --restart=Never \
  --rm -it \
  -- sh
```

**Test OAuth endpoints:**

```bash
# Test Keycloak token acquisition
kubectl run debug-oauth \
  -n default \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm -it \
  -- sh

# Inside pod:
curl -k -X POST "https://keycloak.localtest.me:9443/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin123" \
  -d "grant_type=password" \
  -d "client_id=admin-cli"
```

### Common Issues

**Issue: Pods stuck in ImagePullBackOff**

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check image availability in Kind
docker exec kagenti-demo-control-plane crictl images | grep <image-name>

# Load missing images
./scripts/kind/04-load-agent-images.sh load
```

**Issue: ArgoCD app stuck OutOfSync**

```bash
# Get detailed app status
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Force sync
argocd app sync <app-name> --force --port-forward --port-forward-namespace argocd --grpc-web
```

**Issue: Pod CrashLoopBackOff**

```bash
# Check logs
kubectl logs -n <namespace> <pod-name> --previous

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod <pod-name> -n <namespace>
```

**Issue: Certificate not ready**

```bash
# Check all certificates
kubectl get certificate -A

# Describe specific certificate
kubectl describe certificate <cert-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=100
```

**Issue: mTLS connection failures / TLS WRONG_VERSION_NUMBER**

This error occurs when OAuth2-Proxy's Istio sidecar tries to use mTLS to connect to backend services that expect plain HTTP.

**Symptom**: `upstream connect error or disconnect/reset before headers. TLS error: WRONG_VERSION_NUMBER`

**Root cause**: STRICT mTLS policy + OAuth2-Proxy using HTTP to backend

**Fix**: Add PERMISSIVE mTLS for backend services accessed via OAuth2-Proxy:

```bash
# Check mTLS policies
kubectl get peerauthentication -A

# For services like Phoenix, Tempo, Kiali - they need PERMISSIVE mode
# Already configured in:
# - components/02-observability/mtls-policy.yaml (Phoenix, Tempo)
# - components/02-observability/kiali/mtls-policy.yaml (Kiali)

# Verify policy applied
kubectl get peerauthentication -n observability
kubectl get peerauthentication -n kiali-system

# Check OAuth2-Proxy logs for TLS errors
kubectl logs -n oauth2-proxy deployment/phoenix-oauth2-proxy --tail=50
```

**General mTLS debugging**:

```bash
# Verify Istio sidecar injection (should show 2/2 containers)
kubectl get pods -n <namespace>

# Check namespace has istio-injection label
kubectl get namespace <namespace> -o jsonpath='{.metadata.labels.istio-injection}'

# Check all mTLS policies
kubectl get peerauthentication -A
kubectl get destinationrule -A

# Debug specific pod
istioctl x describe pod <pod-name> -n <namespace>
```

**Issue: Service not accessible via Gateway**

```bash
# Check Gateway status
kubectl get gateway -A
kubectl describe gateway external-gateway -n default

# Check HTTPRoutes
kubectl get httproute -A
kubectl describe httproute <route-name> -n <namespace>

# Test from debug pod
kubectl run test-curl -n default --image=curlimages/curl:latest --restart=Never --rm -it \
  -- curl -k https://grafana.localtest.me:9443
```

**Issue: Deployment not applying changes**

```bash
# Restart deployment (force pod recreation)
kubectl rollout restart deployment/<name> -n <namespace>

# Watch rollout status
kubectl rollout status deployment/<name> -n <namespace>

# Force delete pod (will be recreated)
kubectl delete pod <pod-name> -n <namespace>
```

### Useful Debug Scripts

```bash
# Check platform health (includes pytest tests)
./scripts/platform-status.sh

# Monitor ArgoCD application sync (standalone)
./scripts/monitor-argocd-apps.sh 900

# Show service access URLs and credentials
./scripts/show-access-info.sh

# Full cluster redeploy
./scripts/quick-redeploy.sh
```

---

## 🔒 Encryption and mTLS

**ALL service-to-service communication MUST be encrypted using Istio mTLS (STRICT mode)**.

### Sidecar Proxy Pattern

```
Application (HTTP) → Istio Sidecar (mTLS) → Network (encrypted) → Istio Sidecar → Application (HTTP)
```

**Key points:**
- ✅ Applications speak HTTP to local Istio sidecar (same pod, not over network)
- ✅ Istio sidecars automatically encrypt ALL network traffic with mTLS
- ✅ NO plaintext HTTP travels over the network between services
- ✅ Automatic certificate rotation handled by Istio

### Verification

```bash
# Check sidecar injection (should show 2/2 for app + sidecar)
kubectl get pods -n <namespace>

# Verify namespace has istio-injection label
kubectl get namespace <namespace> -o jsonpath='{.metadata.labels.istio-injection}'

# Check mTLS status
istioctl x describe pod <pod-name> -n <namespace>

# View mTLS policies
kubectl get peerauthentication -A
kubectl get destinationrule -A
```

**See also:**
- [docs/ENCRYPTION_ARCHITECTURE.md](./docs/ENCRYPTION_ARCHITECTURE.md) - Full encryption architecture
- [docs/PRODUCTION_SECURITY_ROADMAP.md](./docs/PRODUCTION_SECURITY_ROADMAP.md) - SPIRE integration roadmap

---

## 🎛️ Essential ArgoCD Commands

```bash
# List all applications
argocd app list --port-forward --port-forward-namespace argocd --grpc-web

# Get application status
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Sync application
argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Diff Git vs cluster
argocd app diff <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# View sync history
argocd app history <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Rollback to previous version
argocd app rollback <app-name> <revision-id> --port-forward --port-forward-namespace argocd --grpc-web
```

---

## 📊 Monitoring & Access

### Access Services

```bash
# Get ArgoCD admin password
cat /tmp/argocd-pass.txt

# Access services via browser
open https://argocd.localtest.me:9443      # ArgoCD UI
open https://keycloak.localtest.me:9443    # Keycloak Admin
open https://grafana.localtest.me:9443     # Grafana
open https://kagenti.localtest.me:9443     # Kagenti UI
open https://kiali.localtest.me:9443       # Kiali Service Mesh
```

**Default credentials:**
- ArgoCD: `admin` / `<from /tmp/argocd-pass.txt>`
- Keycloak: `admin` / `admin123` (dev only)
- Grafana: `admin` / `admin123` (dev only)

### Monitoring Commands

```bash
# Platform health check (comprehensive)
./scripts/platform-status.sh

# Monitor ArgoCD sync progress
./scripts/monitor-argocd-apps.sh 900  # 15-minute timeout

# Show access URLs and credentials
./scripts/show-access-info.sh

# Watch pods in all namespaces
kubectl get pods -A -w

# Check specific namespace
kubectl get pods -n observability -w
```

### Alert Monitoring

**Check Currently Firing Alerts**:

```bash
# List all firing alerts via Grafana API
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://localhost:3000/api/alertmanager/grafana/api/v2/alerts' \
  -u admin:admin123 | python3 -c "
import sys, json
alerts = json.load(sys.stdin)
firing = [a for a in alerts if a.get('status', {}).get('state') == 'active']
print(f'Firing alerts: {len(firing)}')
for alert in firing:
    labels = alert.get('labels', {})
    print(f\"  • {labels.get('alertname')} ({labels.get('severity')})\")
"

# List all alert rules
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://localhost:3000/api/v1/provisioning/alert-rules' \
  -u admin:admin123 | python3 -c "
import sys, json
rules = json.load(sys.stdin)
print(f'Total alert rules: {len(rules)}')
for rule in rules:
    print(f\"  • {rule.get('title')} ({rule.get('labels', {}).get('severity')})\")
"
```

**Test Alert Queries**:

```bash
# Test a PromQL query directly in Prometheus
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=up{job="kubernetes-pods"}' | python3 -m json.tool

# Test specific alert query
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=kube_deployment_status_replicas_available{namespace="observability"} == 0' \
  | python3 -m json.tool
```

**Modify Alert Rules** (GitOps workflow):

```bash
# 1. Edit alert configuration
vim components/02-observability/grafana/alerting-provisioning.yaml

# 2. Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('components/02-observability/grafana/alerting-provisioning.yaml'))"

# 3. Commit changes
git add components/02-observability/
git commit -m "Update alert thresholds for CPU usage"
git push

# 4. Apply and reload (if ArgoCD sync is slow)
kubectl apply -f components/02-observability/grafana/alerting-provisioning.yaml
kubectl rollout restart deployment/grafana -n observability

# 5. Verify alert updated
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://localhost:3000/api/v1/provisioning/alert-rules' \
  -u admin:admin123 | grep -A 10 "your-alert-uid"
```

**Silence/Mute Alerts**:

```bash
# Create a silence via Grafana API (temporary - not GitOps)
# For GitOps approach, use mute-timings.yaml in alerting-provisioning.yaml

# Example: Silence an alert for 2 hours
kubectl exec -n observability deployment/grafana -- \
  curl -s -X POST 'http://localhost:3000/api/alertmanager/grafana/api/v2/silences' \
  -H 'Content-Type: application/json' \
  -u admin:admin123 \
  -d '{
    "matchers": [{"name": "alertname", "value": "YourAlertName", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -v+2H +%Y-%m-%dT%H:%M:%SZ)'",
    "comment": "Silenced during maintenance",
    "createdBy": "admin"
  }'
```

**View Alert History in Grafana**:

1. Open Grafana: `https://grafana.localtest.me:9443`
2. Navigate to: **Alerting** → **Alert rules**
3. Click on an alert to see:
   - Current state
   - Query results
   - Evaluation history
   - Annotations

**Debug Alert Issues**:

```bash
# Check alert rule configuration
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://localhost:3000/api/v1/provisioning/alert-rules' \
  -u admin:admin123 | python3 -c "
import sys, json
rules = json.load(sys.stdin)
rule = next((r for r in rules if r.get('uid') == 'your-alert-uid'), None)
if rule:
    print('Alert Query:', rule['data'][0]['model']['expr'])
    print('noDataState:', rule['noDataState'])
    print('execErrState:', rule['execErrState'])
    print('Evaluation interval:', rule.get('for', 'instant'))
"

# Check Grafana logs for alert evaluation errors
kubectl logs -n observability deployment/grafana --tail=100 | grep -i alert

# Check Prometheus metrics for the alert query
kubectl port-forward -n observability svc/prometheus 9090:9090 &
# Then open http://localhost:9090 and test your query

# Verify AlertManager is receiving alerts
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://alertmanager.observability.svc:9093/api/v2/alerts' | python3 -m json.tool
```

**Common Alert Issues & Solutions**:

| Issue | Cause | Solution |
|-------|-------|----------|
| Alert fires constantly | `noDataState: Alerting` + query returns empty | Change to `noDataState: OK` |
| Alert never fires | Query syntax error or wrong labels | Test query in Prometheus UI |
| False positive | Incorrect threshold or metric | Verify actual metric values |
| Alert delayed | `for` duration too long | Reduce evaluation window |

**See also**:
- [docs/04-observability/ADDING_NEW_ALERTS.md](./docs/04-observability/ADDING_NEW_ALERTS.md) - How to add new alerts
- [docs/04-observability/ALERT_FIX_SUMMARY.md](./docs/04-observability/ALERT_FIX_SUMMARY.md) - Alert troubleshooting examples
- [TODO_ALERTS.md](./TODO_ALERTS.md) - Alert development roadmap

---

## 📁 Repository Structure

```
kagenti-demo-deployment/
├── argocd/
│   ├── bootstrap/kind/
│   │   └── root-app.yaml           # Root Application (App-of-Apps)
│   └── applications/
│       ├── base/                   # Reusable templates
│       ├── kind-local/             # Kind-specific patches
│       └── helm/                   # Helm-based apps
│
├── components/                     # LAYERED manifests
│   ├── 00-infrastructure/          # Wave 0: Gateway, cert-manager, Tekton, Istio
│   ├── 01-platform/                # Wave 10: Keycloak, operators, UI
│   ├── 02-observability/           # Wave 20: Grafana, Tempo, Phoenix
│   └── 03-applications/            # Wave 30: Agents
│
├── scripts/
│   ├── quick-redeploy.sh           # Complete cluster redeploy
│   ├── platform-status.sh          # Health check + pytest
│   ├── monitor-argocd-apps.sh      # Monitor sync progress
│   └── kind/
│       ├── 00-cleanup.sh
│       ├── 01-create-cluster.sh
│       ├── 02-install-argocd.sh
│       ├── 03-bootstrap-apps.sh
│       └── 04-load-agent-images.sh
│
└── tests/
    ├── integration/                # Integration tests
    └── validation/                 # Platform validation tests
```

---

## 📚 Further Reading

- [argocd_architecture.md](./argocd_architecture.md) - ArgoCD architecture and sync waves
- [docs/ENCRYPTION_ARCHITECTURE.md](./docs/ENCRYPTION_ARCHITECTURE.md) - Encryption and mTLS
- [docs/INTEGRATION_TESTS.md](./docs/INTEGRATION_TESTS.md) - Testing strategy
- [TODO_TESTS.md](./TODO_TESTS.md) - Testing roadmap
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Istio mTLS](https://istio.io/latest/docs/concepts/security/#mutual-tls-authentication)

---

**Remember**: 🚫 No `kubectl apply` → ✅ Always Git + `argocd app sync`
