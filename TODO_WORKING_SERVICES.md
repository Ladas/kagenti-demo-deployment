# TODO: Working Services

**Goal**: Get all services accessible and functional via gateway (https://*.localtest.me:9443)

**Status Check**: `./scripts/platform-status.sh`

---

## Priority Order

1. **Keycloak** (Authentication) - CRITICAL
2. **Kagenti UI** (Main application)
3. **Kiali** (Service mesh observability)
4. **Other services** (Grafana, Tempo, Phoenix, etc.)

---

## Current Status (2025-11-12 10:35 CET)

### ✅ Completed
- [x] Keycloak pod running (2/2 with Istio sidecar)
- [x] Postgres connectivity fixed (DestinationRule: DISABLE)
- [x] Keycloak realm import succeeded (kubernetes & kagenti realms created)
- [x] HTTPRoute service references fixed (keycloak-service → keycloak)

### ⚠️ In Progress
- [ ] Gateway connectivity (services return HTTP 503/000 via *.localtest.me:9443)

### ❌ Blocked/Pending
- [ ] OAuth2-Proxy pods (CreateContainerConfigError - need client secrets)
- [ ] ArgoCD apps OutOfSync (need sync)

---

## Task Breakdown

### Phase 1: Keycloak Accessibility ⚡ CURRENT FOCUS

**Objective**: Access Keycloak admin console at https://keycloak.localtest.me:9443

**Status**: HTTP 000 (connection timeout)

**Diagnosis**:
- Keycloak pod: ✅ Running (2/2)
- Keycloak service: ✅ Exists (keycloak.keycloak.svc.cluster.local:8080)
- HTTPRoute: ✅ Configured and ResolvedRefs
- DestinationRule: ✅ Correct (keycloak.keycloak.svc.cluster.local, ISTIO_MUTUAL)
- Gateway: ✅ Running (external-gateway-istio-78bbc878-tb4bk)
- Realm import job: ✅ Can connect to Keycloak from within cluster

**Hypothesis**: Local DNS/routing issue with *.localtest.me:9443

**Next Steps**:
1. [ ] Check /etc/hosts entries for *.localtest.me
2. [ ] Test gateway NodePort directly (30443) instead of 9443
3. [ ] Check if gateway is listening on correct ports
4. [ ] Test with port-forward to gateway pod
5. [ ] Verify TLS certificate is valid for keycloak.localtest.me
6. [ ] Check if mTLS is blocking external traffic

**Tests**:
```bash
# Test 1: Check /etc/hosts
cat /etc/hosts | grep localtest.me

# Test 2: Test NodePort directly
curl -k https://localhost:30443 -H "Host: keycloak.localtest.me"

# Test 3: Port-forward to gateway
kubectl port-forward -n default svc/external-gateway-istio 9443:443
curl -k https://localhost:9443 -H "Host: keycloak.localtest.me"

# Test 4: Check gateway pod ports
kubectl exec -n default external-gateway-istio-78bbc878-tb4bk -- netstat -tln

# Test 5: Check certificate
kubectl get certificate -A | grep localtest

# Test 6: Check gateway logs
kubectl logs -n default external-gateway-istio-78bbc878-tb4bk --tail=100
```

**Success Criteria**:
- [ ] HTTP 200/302/401 from https://keycloak.localtest.me:9443 (not HTTP 000/503)
- [ ] Can access Keycloak admin console in browser
- [ ] Can login with admin/admin credentials

---

### Phase 2: Kagenti UI Accessibility

**Objective**: Access Kagenti UI at https://kagenti.localtest.me:9443

**Status**: HTTP 000 (connection timeout)

**Dependencies**:
- Keycloak accessible (for OIDC authentication)
- Keycloak kubernetes realm configured

**Next Steps**:
1. [ ] Verify HTTPRoute exists and is configured
2. [ ] Check kagenti-ui pod status
3. [ ] Verify OAuth2 client secret exists
4. [ ] Test connectivity from gateway to kagenti-ui service
5. [ ] Check kagenti-ui logs for errors

**Success Criteria**:
- [ ] HTTP 302 redirect to Keycloak login
- [ ] Can login with kagenti-admin/admin123
- [ ] Redirected back to Kagenti UI after login
- [ ] Kagenti UI loads successfully

---

### Phase 3: Kiali Accessibility

**Objective**: Access Kiali service mesh UI at https://kiali.localtest.me:9443

**Status**: HTTP 503 (server error)

**Dependencies**:
- Keycloak accessible
- Keycloak kubernetes realm configured
- OAuth2-Proxy pod running (needs kiali-client-secret)

**Current Issues**:
- OAuth2-Proxy pods in CreateContainerConfigError (missing client secrets)

**Next Steps**:
1. [ ] Check if kiali OAuth2 client exists in Keycloak
2. [ ] Extract client secret from Keycloak
3. [ ] Create kiali-client-secret in oauth2-proxy namespace
4. [ ] Verify kiali-oauth2-proxy pod starts successfully
5. [ ] Test kiali service connectivity

**Success Criteria**:
- [ ] OAuth2-Proxy pod running
- [ ] HTTP 302 redirect to Keycloak login
- [ ] Can login with platform-admin/admin123
- [ ] Kiali UI loads successfully

---

### Phase 4: Other Services

**Services to Fix** (in order):
1. [ ] **Grafana** (HTTP 503) - Observability dashboards
   - OAuth2-Proxy pod in CreateContainerConfigError
   - Need grafana-client-secret from Keycloak

2. [ ] **Tempo** (HTTP 503) - Distributed tracing
   - OAuth2-Proxy pod in CreateContainerConfigError
   - Need tempo-client-secret from Keycloak

3. [ ] **Phoenix** (HTTP 503) - LLM tracing
   - OAuth2-Proxy pod in CreateContainerConfigError
   - Need phoenix-client-secret from Keycloak

4. [ ] **Prometheus** (not tested) - Metrics
   - OAuth2-Proxy pod in CreateContainerConfigError
   - Need prometheus-client-secret from Keycloak

**Common Pattern**: All OAuth2-protected services need client secrets from Keycloak

**Automated Fix**:
Create a job to extract all OAuth2 client secrets from Keycloak and create Kubernetes secrets.

---

## OAuth2 Client Secrets Strategy

**Problem**: OAuth2-Proxy pods need client secrets, but secrets don't exist yet.

**Root Cause**: Realm import job creates clients in Keycloak, but doesn't extract and save secrets to Kubernetes.

**Solution Options**:

### Option A: Manual Secret Creation
```bash
# Get client secret from Keycloak API
TOKEN=$(curl -sf -X POST http://keycloak.keycloak.svc.cluster.local:8080/realms/master/protocol/openid-connect/token \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r .access_token)

# Get grafana client secret
SECRET=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  http://keycloak.keycloak.svc.cluster.local:8080/admin/realms/kubernetes/clients?clientId=grafana \
  | jq -r '.[0].secret')

# Create Kubernetes secret
kubectl create secret generic grafana-client-secret \
  -n oauth2-proxy \
  --from-literal=client-id=grafana \
  --from-literal=client-secret=$SECRET
```

### Option B: Automated Job (RECOMMENDED)
Create a Kubernetes Job similar to realm-import-job that:
1. Queries Keycloak for all OAuth2 clients
2. Extracts client secrets
3. Creates Kubernetes secrets in oauth2-proxy namespace

**Files to Create**:
- `components/00-infrastructure/keycloak/oauth2-secrets-job.yaml`

**Sync Wave**: 2 (after realm import, wave 1)

---

## ArgoCD Sync Status

**Apps OutOfSync** (need manual sync):
- istio-base
- istiod
- keycloak
- kagenti-platform-operator

**Sync Commands**:
```bash
argocd app sync istio-base --port-forward --port-forward-namespace argocd --grpc-web
argocd app sync istiod --port-forward --port-forward-namespace argocd --grpc-web
argocd app sync keycloak --port-forward --port-forward-namespace argocd --grpc-web
argocd app sync kagenti-platform-operator --port-forward --port-forward-namespace argocd --grpc-web
```

---

## Testing Checklist

### Gateway Connectivity Tests
- [ ] /etc/hosts has correct entries
- [ ] Gateway pod is running
- [ ] Gateway service exists and has endpoints
- [ ] TLS certificates are valid
- [ ] HTTPRoutes are configured correctly
- [ ] Can connect to gateway via NodePort

### Service-Specific Tests
- [ ] Keycloak admin console accessible
- [ ] Kagenti UI redirects to Keycloak
- [ ] Kiali accessible with OAuth2
- [ ] Grafana accessible with OAuth2
- [ ] All services show HTTP 200/302/401 (not 503/000)

### End-to-End Tests
- [ ] Can login to Keycloak
- [ ] Can login to Kagenti UI via Keycloak
- [ ] Can login to Kiali via OAuth2-Proxy
- [ ] Can create an agent in Kagenti UI
- [ ] Can view service mesh in Kiali

---

## Debugging Commands

### Check Service Status
```bash
./scripts/platform-status.sh
./scripts/show-access-info.sh
```

### Check Specific Service
```bash
# Keycloak
kubectl get pods -n keycloak
kubectl logs -n keycloak keycloak-0 -c keycloak --tail=50
curl -k -v https://keycloak.localtest.me:9443

# Gateway
kubectl get pods -n default -l app.kubernetes.io/component=gateway
kubectl logs -n default external-gateway-istio-78bbc878-tb4bk --tail=100

# HTTPRoutes
kubectl get httproute -A
kubectl describe httproute -n keycloak keycloak

# DestinationRules
kubectl get destinationrule -A
kubectl describe destinationrule -n keycloak keycloak-mtls
```

### Check OAuth2-Proxy
```bash
kubectl get pods -n oauth2-proxy
kubectl describe pod -n oauth2-proxy kiali-oauth2-proxy-<pod-id>
kubectl get secrets -n oauth2-proxy
```

---

## Known Issues

1. **Gateway returns HTTP 000/503** for all *.localtest.me:9443 URLs
   - Hypothesis: Local DNS/routing issue OR gateway not properly routing traffic
   - Need to verify /etc/hosts and gateway configuration

2. **OAuth2-Proxy pods failing** (CreateContainerConfigError)
   - Missing client secrets in oauth2-proxy namespace
   - Need to extract secrets from Keycloak after realm import

3. **Multiple apps OutOfSync** in ArgoCD
   - Normal after making manual fixes
   - Need to sync apps to apply latest changes

---

## Next Session TODO

1. **Fix Gateway Connectivity** (PRIORITY 1)
   - Investigate why *.localtest.me:9443 returns HTTP 000
   - Test with NodePort, port-forward, and /etc/hosts
   - Get Keycloak accessible via browser

2. **Create OAuth2 Secrets Job** (PRIORITY 2)
   - Extract client secrets from Keycloak
   - Create Kubernetes secrets for OAuth2-Proxy
   - Fix OAuth2-Proxy pod failures

3. **Sync ArgoCD Apps** (PRIORITY 3)
   - Sync all OutOfSync apps
   - Verify resource health in ArgoCD

4. **Run Full Pytest Suite** (PRIORITY 4)
   - Validate all services are accessible
   - Identify any remaining issues

---

## Success Metrics

**Definition of Done**:
- [ ] All services return HTTP 200/302/401 (not 503/000)
- [ ] Can access Keycloak admin console in browser
- [ ] Can login to Kagenti UI via Keycloak OIDC
- [ ] Can access Kiali, Grafana, Tempo, Phoenix via OAuth2-Proxy
- [ ] `./scripts/platform-status.sh` shows all services accessible
- [ ] Pytest validation tests pass
- [ ] ArgoCD shows all apps Synced and Healthy

---

**Last Updated**: 2025-11-12 22:00 CET
**Session**: Implementing Kubernetes Reflector for OAuth secret management
**Next Focus**: Create master OAuth secrets extractor Job and migrate all services to Reflector pattern

---

## 🔐 Phase 5: OAuth Secret Management with Reflector (NEW - 2025-11-12)

**Objective**: Implement automated OAuth secret management using Kubernetes Reflector for all services

**Problem**: Current per-service OAuth Jobs have cross-namespace connectivity issues:
- Jobs run in target namespace (kagenti-system, observability, etc.)
- Need to connect to Keycloak in keycloak namespace
- Istio mTLS STRICT mode causes connection failures
- Complex RBAC required for cross-namespace secret creation

**Solution**: Kubernetes Reflector Pattern
1. ✅ **Install Reflector** (completed - running in reflector namespace)
2. **Create master OAuth secrets Job** in keycloak namespace only
   - Job runs in same namespace as Keycloak (no cross-namespace issues)
   - Extracts all OAuth client secrets from Keycloak API
   - Creates source secrets in keycloak namespace with Reflector annotations
3. **Reflector automatically mirrors** secrets to target namespaces
   - kagenti-ui-oauth-secret → kagenti-system namespace
   - grafana-client-secret → observability namespace
   - kiali-client-secret → observability namespace
   - tempo-client-secret → observability namespace
   - phoenix-client-secret → observability namespace

### Services Requiring OAuth Secrets

| Service | Realm | Client ID | Source Secret | Target Namespace | Status |
|---------|-------|-----------|---------------|------------------|--------|
| Kagenti UI | kagenti | kagenti-ui | keycloak/kagenti-ui-oauth-secret | kagenti-system | ⏳ TODO |
| Grafana | kubernetes | grafana | keycloak/grafana-client-secret | observability | ⏳ TODO |
| Kiali | kubernetes | kiali | keycloak/kiali-client-secret | observability | ⏳ TODO |
| Tempo | kubernetes | tempo | keycloak/tempo-client-secret | observability | ⏳ TODO |
| Phoenix | kubernetes | phoenix | keycloak/phoenix-client-secret | observability | ⏳ TODO |
| Prometheus | kubernetes | prometheus | keycloak/prometheus-client-secret | observability | ⏳ TODO |

### Implementation Plan

#### Step 1: Install Reflector via ArgoCD ✅ DONE
- [x] Create Reflector component in components/00-infrastructure/reflector/
- [x] Create ArgoCD Application for Reflector
- [ ] Commit to Git and sync via ArgoCD
- [ ] Verify Reflector pod is running

**Files Created**:
- `components/00-infrastructure/reflector/namespace.yaml`
- `components/00-infrastructure/reflector/serviceaccount.yaml`
- `components/00-infrastructure/reflector/rbac.yaml`
- `components/00-infrastructure/reflector/deployment.yaml`
- `components/00-infrastructure/reflector/kustomization.yaml`
- `argocd/applications/base/reflector.yaml`

#### Step 2: Create Master OAuth Secrets Job
**File**: `components/00-infrastructure/keycloak/oauth-secrets-extractor-job.yaml`

**Job Responsibilities**:
1. Connect to Keycloak API (same namespace - no cross-namespace issues)
2. Authenticate with admin credentials
3. Query all OAuth clients from both realms (kubernetes, kagenti)
4. Extract client secrets for each client
5. Create Kubernetes secrets in keycloak namespace with:
   - Client ID and secret data
   - Reflector annotations for auto-mirroring
   - Correct target namespace annotations

**Example Secret with Reflector Annotations**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kagenti-ui-oauth-secret
  namespace: keycloak
  annotations:
    reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
    reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "kagenti-system"
    reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
type: Opaque
data:
  CLIENT_ID: <base64-encoded>
  CLIENT_SECRET: <base64-encoded>
  AUTH_ENDPOINT: <base64-encoded>
  TOKEN_ENDPOINT: <base64-encoded>
  REDIRECT_URI: <base64-encoded>
  SCOPE: <base64-encoded>
```

**Sync Wave**: 1 (after realm import, before platform apps)

**Tasks**:
- [ ] Create oauth-secrets-extractor-job.yaml
- [ ] Add script to query Keycloak for all clients
- [ ] Add secret creation logic with Reflector annotations
- [ ] Test locally with kustomize build
- [ ] Commit to Git
- [ ] Sync keycloak app via ArgoCD
- [ ] Verify secrets created in keycloak namespace
- [ ] Verify secrets mirrored to target namespaces

#### Step 3: Remove Per-Service OAuth Jobs
**Services to Update**:
- [ ] Kagenti UI - Remove `components/01-platform/kagenti-ui/oauth-secret-job.yaml`
- [ ] Grafana - Remove per-service secret job (if exists)
- [ ] Kiali - Remove per-service secret job (if exists)

**Cleanup**:
- [ ] Delete old Jobs manually: `kubectl delete job kagenti-ui-oauth-config -n kagenti-system`
- [ ] Remove RBAC resources for per-service jobs
- [ ] Update kustomization.yaml files

#### Step 4: Verify All Services Work
**Tests**:
- [ ] Kagenti UI login via Keycloak OAuth
- [ ] Grafana accessible via OAuth2-Proxy
- [ ] Kiali accessible via OAuth2-Proxy
- [ ] Tempo accessible via OAuth2-Proxy
- [ ] Phoenix accessible via OAuth2-Proxy

**Success Criteria**:
- [ ] All OAuth secrets exist in target namespaces
- [ ] All OAuth2-Proxy pods running (not CreateContainerConfigError)
- [ ] All services return HTTP 200/302 (not 503/000)
- [ ] Can login to all services via Keycloak
- [ ] pytest tests pass for OAuth login flows

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Keycloak Namespace                                          │
│                                                             │
│  ┌─────────────────────────┐                              │
│  │ oauth-secrets-extractor  │  (Job - Sync Wave 1)        │
│  │                         │                              │
│  │  1. Connect to Keycloak │ <───┐                       │
│  │  2. Query all clients   │     │ Same namespace        │
│  │  3. Extract secrets     │     │ (No mTLS issues)      │
│  │  4. Create K8s secrets  │     │                       │
│  └──────────┬──────────────┘     │                       │
│             │                     │                       │
│             v                     │                       │
│  ┌───────────────────────────────┴──────────────┐        │
│  │ Source Secrets (with Reflector annotations)   │        │
│  │                                                │        │
│  │  • kagenti-ui-oauth-secret                    │        │
│  │  • grafana-client-secret                      │        │
│  │  • kiali-client-secret                        │        │
│  │  • tempo-client-secret                        │        │
│  │  • phoenix-client-secret                      │        │
│  └───────────────────────────────────────────────┘        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Reflector watches source secrets
                       │ and mirrors to target namespaces
                       v
       ┌───────────────────────────────────────┐
       │ Reflector (reflector namespace)       │
       │                                       │
       │  • Watches secrets with annotations   │
       │  • Auto-creates/updates in targets    │
       │  • No manual intervention needed      │
       └───────────────┬───────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
           v                       v
  ┌─────────────────┐     ┌─────────────────┐
  │ kagenti-system  │     │  observability  │
  │                 │     │                 │
  │  • kagenti-ui   │     │  • grafana      │
  │    oauth secret │     │  • kiali        │
  │                 │     │  • tempo        │
  │                 │     │  • phoenix      │
  └─────────────────┘     └─────────────────┘
        (mirrored)              (mirrored)
```

### Benefits of Reflector Approach

✅ **Simpler RBAC**: Job only needs permissions in keycloak namespace
✅ **No cross-namespace connectivity issues**: Job runs in same namespace as Keycloak
✅ **Single source of truth**: All secrets created in keycloak namespace
✅ **Automatic synchronization**: Reflector keeps secrets in sync
✅ **Less code**: One job instead of N per-service jobs
✅ **Better GitOps compliance**: Secrets managed declaratively

### References

- **Reflector Documentation**: https://github.com/emberstack/kubernetes-reflector
- **OAuth Secret Pattern**: components/01-platform/kagenti-ui/oauth-secret-job.yaml (old approach)
- **CLAUDE.md**: GitOps workflow and TDD requirements

---

## ✅ MILESTONE: Keycloak Accessible! (2025-11-12 10:58 CET)

**Status**: HTTP 302 - Keycloak Administration Console accessible

**Fixes Applied**:
1. ✅ Port-level PeerAuthentication (PERMISSIVE on port 8080)
2. ✅ NetworkPolicy labels fixed (kubernetes.io/metadata.name, app.kubernetes.io/name)
3. ✅ Production settings (KC_PROXY=edge, KC_HOSTNAME_STRICT=true)
4. ✅ All changes synced via ArgoCD from Git

**Git Commits**:
- f709f53: Fix Keycloak NetworkPolicy labels for gateway access
- 8899f01: Production-ready Keycloak configuration with Istio Gateway mTLS fix
- ad951eb: Fix Keycloak mTLS configuration for Postgres and service name
- a67326e: Fix Keycloak HTTPRoute service name mismatch

**Test Results**:
```bash
$ curl -k -I https://keycloak.localtest.me:9443
HTTP/2 302
location: /admin/
```

---

## ⚠️ NEW ISSUES FOUND (2025-11-12 13:00 CET)

### Issue 1: Keycloak Generating HTTP URLs ❌

**Problem**: Keycloak admin console and OAuth redirects use HTTP instead of HTTPS
- Admin console JavaScript config: `"serverBaseUrl": "http://keycloak.localtest.me:9443"`
- Grafana login redirects to: `http://keycloak.localtest.me:9443/realms/...`
- Kagenti UI login redirects to: `http://keycloak.localtest.me:9443/realms/...`

**Root Cause**: Configuration conflict between `KC_HOSTNAME` and `KC_HOSTNAME_URL`
- Current config sets both `KC_HOSTNAME=keycloak.localtest.me` (no scheme/port)
- AND `KC_HOSTNAME_URL=https://keycloak.localtest.me:9443` (with scheme/port)
- This creates ambiguity - Keycloak defaults to HTTP

**Fix**: Remove `KC_HOSTNAME` and use only `KC_HOSTNAME_URL` / `KC_HOSTNAME_ADMIN_URL`
- Also set `KC_HOSTNAME_STRICT=false` for development (more permissive)

**Files to Change**:
- `components/00-infrastructure/keycloak/keycloak-statefulset.yaml`

**Status**: 🔄 IN PROGRESS

### Issue 2: Kiali Redirect to Port 8080 ❌

**Problem**: Kiali redirects to port 8080 which shows ArgoCD (port-forward conflict)

**Root Cause**: Missing HTTPRoute for Kiali
- No HTTPRoute defined for kiali.localtest.me
- Users accessing Kiali via port-forward, causing confusion

**Fix**: Create HTTPRoute for Kiali (following Grafana pattern)

**Files Created**:
- ✅ `components/02-observability/kiali/httproute.yaml`
- ✅ Updated `components/02-observability/kiali/kustomization.yaml`

**Status**: ✅ FIXED (pending commit)

---

## Current Service Status (2025-11-13 13:10 CET)

| Service | URL | Status | Auth Method | Notes |
|---------|-----|--------|-------------|-------|
| Keycloak | https://keycloak.localtest.me:9443 | HTTP 302 ✅ | Admin console | Accessible, realms configured |
| Kiali | https://kiali.localtest.me:9443 | HTTP 302 ✅ | OAuth2-Proxy (kubernetes realm) | Redirects to Keycloak login |
| Grafana | https://grafana.localtest.me:9443 | HTTP 302 ✅ | OAuth2-Proxy (kubernetes realm) | Redirects to Keycloak login |
| Prometheus | https://prometheus.localtest.me:9443 | HTTP 302 ✅ | OAuth2-Proxy (kubernetes realm) | Redirects to Keycloak login |
| Tempo | https://tempo.localtest.me:9443 | HTTP 302 ✅ | OAuth2-Proxy (kubernetes realm) | Redirects to Keycloak login |
| Phoenix | https://phoenix.localtest.me:9443 | HTTP 302 ✅ | OAuth2-Proxy (kagenti realm) | Redirects to Keycloak login |
| Kagenti UI | https://kagenti.localtest.me:9443 | HTTP 200 ✅ | Direct OIDC (kagenti realm) | Accessible, OAuth configured |

### ✅ ALL SERVICES ACCESSIBLE!

**Test Results**:
```bash
$ bash /tmp/test_services.sh
=== Service Accessibility Test ===

Kiali:
HTTP/2 302
cache-control: no-cache, no-store, must-revalidate, max-age=0

Grafana:
HTTP/2 302
cache-control: no-store

Prometheus:
HTTP/2 302
cache-control: no-cache, no-store, must-revalidate, max-age=0

Tempo:
HTTP/2 302
cache-control: no-cache, no-store, must-revalidate, max-age=0

Phoenix:
HTTP/2 302
cache-control: no-cache, no-store, must-revalidate, max-age=0

Kagenti UI:
HTTP/2 200
server: istio-envoy
```

**Credentials**:
- **Kubernetes realm** (Kiali, Grafana, Prometheus, Tempo): `platform-admin / admin123`
- **Kagenti realm** (Phoenix, Kagenti UI): `kagenti-admin / admin123`
- **Keycloak admin**: `admin / admin123`

**Completed**:
1. ✅ Fixed oauth2-proxy cookie secret (must be exactly 32 bytes)
2. ✅ All oauth2-proxy pods Running (2/2 with Istio sidecar)
3. ✅ OAuth client secrets extracted from Keycloak and mirrored via Reflector
4. ✅ Kagenti-system namespace has istio-injection=enabled
5. ✅ All GitOps changes committed to Git (commit 003227a)
6. ✅ All ArgoCD applications synced

---

## 🔐 GitOps and Testing Requirements

### ✅ GitOps Workflow (MANDATORY)

**ALL changes MUST be applied via ArgoCD and Git - NO direct kubectl apply**

**Workflow**:
1. Edit manifests in `components/` directory
2. Validate changes locally:
   ```bash
   # Kustomize validation
   kustomize build components/00-infrastructure/keycloak/ > /dev/null

   # Kubectl dry-run (client-side)
   kustomize build components/00-infrastructure/keycloak/ | kubectl apply --dry-run=client -f -

   # Kubectl dry-run (server-side)
   kustomize build components/00-infrastructure/keycloak/ | kubectl apply --dry-run=server -f -

   # ArgoCD diff (preview changes)
   argocd app diff keycloak --port-forward --port-forward-namespace argocd --grpc-web
   ```
3. Commit to Git:
   ```bash
   git add components/
   git commit -m "Descriptive commit message"
   git push origin argocd-gitops-dev
   ```
4. Sync via ArgoCD:
   ```bash
   argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web
   ```
5. Verify deployment:
   ```bash
   argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web
   kubectl get pods -n <namespace>
   ```

**Reference**: See `CLAUDE.md` for complete GitOps workflow documentation

---

### 🧪 Pytest Coverage Requirements

**ALL services MUST have pytest coverage showing:**
1. **Service is accessible** via HTTPS gateway (https://*.localtest.me:9443)
2. **Authentication works** (can login with test credentials)
3. **Basic endpoints work** (health check, API endpoints, UI loads)

**Test Files**:
- `tests/integration/test_platform.py` - Keycloak, Kagenti UI
- `tests/integration/test_observability.py` - Grafana, Kiali, Tempo, Phoenix
- `tests/integration/test_oauth_login.py` - OAuth login flows for all services

**Required Tests per Service**:

#### Keycloak
```python
def test_keycloak_admin_console_accessible():
    """Keycloak admin console returns HTTPS redirect"""
    response = requests.get("https://keycloak.localtest.me:9443", verify=False)
    assert response.status_code in [200, 302]
    assert "https://keycloak.localtest.me:9443" in response.text  # HTTPS URLs only

def test_keycloak_admin_login():
    """Can login to Keycloak admin console"""
    # Login via Keycloak API
    response = requests.post(
        "https://keycloak.localtest.me:9443/realms/master/protocol/openid-connect/token",
        data={"username": "admin", "password": "admin123", "grant_type": "password", "client_id": "admin-cli"},
        verify=False
    )
    assert response.status_code == 200
    assert "access_token" in response.json()
```

#### Grafana
```python
def test_grafana_oauth_login():
    """Can login to Grafana via Keycloak OAuth"""
    session = requests.Session()
    # Follow OAuth redirect chain
    response = session.get("https://grafana.localtest.me:9443", verify=False, allow_redirects=True)
    assert "keycloak" in response.url  # Redirected to Keycloak
    # Login and verify redirect back to Grafana
    # ...
```

#### Kagenti UI
```python
def test_kagenti_ui_accessible():
    """Kagenti UI is accessible and returns HTTP 200"""
    response = requests.get("https://kagenti.localtest.me:9443", verify=False)
    assert response.status_code in [200, 302]
```

**Run Tests**:
```bash
# Quick validation (critical apps, ~30s)
pytest tests/validation/test_app_state.py -v --only-critical

# Integration tests (all services, ~2m)
pytest tests/integration/ -v

# Specific service
pytest tests/integration/test_platform.py::test_keycloak_admin_login -v

# Full suite with HTML report
pytest tests/ -v --html=report.html
```

**Test Coverage Goals**:
- ✅ All services return HTTP 200/302 (not 503/000)
- ✅ OAuth login works for all services
- ✅ Basic API endpoints return expected responses
- ✅ No HTTP URLs in redirect chains (all HTTPS)

---

