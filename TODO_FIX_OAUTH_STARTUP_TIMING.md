# TODO: Fix OAuth Secret Startup Timing Issues

**Date**: 2025-11-19
**Status**: WORKAROUND APPLIED, PERMANENT FIX NEEDED
**Priority**: HIGH (prevents clean deployments)

---

## Problem Statement

OAuth-protected services (Grafana, Kagenti-UI, OAuth2-Proxy) fail to start with proper authentication when deployed from scratch because:

1. **Pods start immediately** when ArgoCD syncs
2. **Keycloak takes 2-5 minutes** to become ready (StatefulSet + database init)
3. **oauth2-secrets-extractor Job runs 5-15 minutes** after Keycloak is ready (PostSync hook)
4. **Secrets created too late** - pods already running with empty env vars

**Result**: Services show "Expected CLIENT_SECRET env var but none exists" errors until pods are manually restarted.

---

## Current Workarounds Applied (2025-11-19)

### 1. Grafana OAuth Fix
**File**: `components/02-observability/grafana/deployment.yaml:115`
**Fix**: Enabled Istio sidecar injection
**Status**: ✅ Fixed and committed (4d05a26)

**Issue**: Grafana had `sidecar.istio.io/inject: "false"` which prevented mTLS communication with Keycloak.

### 2. Kagenti-UI OAuth Fix
**Action**: Manually restarted pod to pick up secret
**Status**: ✅ Fixed (temporary)

**Issue**: Pod started before `kagenti-ui-oauth-secret` existed. Environment variables marked as `optional: true` allowed pod to start without values.

---

## Permanent Fix Strategy

### Option 1: InitContainer Wait Pattern ✅ PARTIALLY IMPLEMENTED

**Already implemented in**:
- `components/01-platform/kagenti-ui/deployment.yaml:77-111` - waits 120 seconds for secret

**Need to add to**:
- Grafana deployment
- OAuth2-Proxy deployments (phoenix, tempo, kiali, prometheus, grafana)

**Implementation**:
```yaml
initContainers:
- name: wait-for-oauth-secret
  image: bitnami/kubectl:latest
  command: ["/bin/sh", "-c"]
  args:
  - |
    echo "Waiting for OAuth secret..."
    MAX_ATTEMPTS=60  # 2 minutes
    ATTEMPT=0
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
      if kubectl get secret <secret-name> -n <namespace> >/dev/null 2>&1; then
        # Verify required keys exist
        REQUIRED_KEYS="CLIENT_ID CLIENT_SECRET AUTH_ENDPOINT TOKEN_ENDPOINT REDIRECT_URI"
        ALL_PRESENT=true
        for KEY in $REQUIRED_KEYS; do
          if ! kubectl get secret <secret-name> -n <namespace> \
               -o jsonpath="{.data.$KEY}" >/dev/null 2>&1; then
            ALL_PRESENT=false
          fi
        done
        if [ "$ALL_PRESENT" = "true" ]; then
          echo "✓ Secret ready with all required keys"
          exit 0
        fi
      fi
      ATTEMPT=$((ATTEMPT + 1))
      sleep 2
    done
    echo "WARNING: Secret not ready after $MAX_ATTEMPTS attempts. Proceeding anyway."
    exit 0  # Don't block deployment, just warn
```

**Pros**:
- ✅ Simple to implement
- ✅ Works with existing architecture
- ✅ No ArgoCD changes needed

**Cons**:
- ⚠️ Adds 2 minutes to pod startup (if secret doesn't exist)
- ⚠️ Still requires manual intervention if wait timeout exceeded

---

### Option 2: ArgoCD Sync Waves (RECOMMENDED FOR PRODUCTION)

**Current waves**:
```yaml
# components/00-infrastructure/keycloak/
argocd.argoproj.io/sync-wave: "1"  # Keycloak StatefulSet

# components/00-infrastructure/keycloak/oauth-secrets-extractor-job.yaml
argocd.argoproj.io/sync-wave: "2"  # PostSync hook
argocd.argoproj.io/hook: PostSync

# components/02-observability/grafana/
# NO SYNC WAVE - defaults to wave 0 (runs BEFORE Keycloak!)
```

**Fix: Add sync waves**:
```yaml
# Keycloak deployment
argocd.argoproj.io/sync-wave: "5"  # Infrastructure layer

# oauth2-secrets-extractor Job
argocd.argoproj.io/sync-wave: "10"  # After Keycloak ready

# Grafana, Kagenti-UI, OAuth2-Proxy
argocd.argoproj.io/sync-wave: "15"  # After secrets exist
```

**Pros**:
- ✅ **Guaranteed ordering** - pods never start before secrets exist
- ✅ Clean deployments every time
- ✅ No manual intervention needed
- ✅ Follows GitOps best practices

**Cons**:
- ⚠️ Slower total deployment time (sequential waves)
- ⚠️ Requires understanding of ArgoCD sync waves
- ⚠️ Breaks if wave numbers conflict

---

### Option 3: Reloader + ConfigMap/Secret Watcher

**Implementation**: Deploy Stakater Reloader
```yaml
# components/00-infrastructure/reloader/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reloader
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: reloader
        image: stakater/reloader:v1.0.0
```

**Add annotations to Deployments**:
```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
    # OR specifically:
    secret.reloader.stakater.com/reload: "grafana-client-secret"
```

**How it works**:
- Reloader watches Secrets/ConfigMaps
- When secret changes, Reloader restarts associated pods
- Pods automatically pick up new values

**Pros**:
- ✅ **Automatic pod restart** when secrets change
- ✅ Handles secret rotation
- ✅ Works for runtime secret updates (not just startup)

**Cons**:
- ⚠️ Adds external dependency (Reloader)
- ⚠️ Doesn't fix initial deployment (pods still start before secrets)
- ⚠️ Requires additional RBAC permissions

---

## Recommended Implementation Plan

### Phase 1: Quick Fix (1 day) ✅ DONE
- [x] Enable Grafana Istio sidecar (4d05a26)
- [x] Restart kagenti-ui pod manually
- [x] Document issue in TODO_FIX_OAUTH_STARTUP_TIMING.md

### Phase 2: InitContainer Pattern (3 days)
- [ ] Add initContainer wait logic to Grafana deployment
- [ ] Add initContainer wait logic to all OAuth2-Proxy deployments
- [ ] Test with fresh cluster deployment (`./scripts/quick-redeploy.sh`)
- [ ] Verify pods wait for secrets before starting

### Phase 3: Sync Waves (1 week)
- [ ] Audit ALL sync waves in `components/`
- [ ] Assign waves: infrastructure (0-10), platform (15-20), observability (25-30), apps (35+)
- [ ] Update Keycloak to wave 5
- [ ] Update oauth2-secrets-extractor to wave 10
- [ ] Update OAuth-protected services to wave 15+
- [ ] Test full deployment from scratch
- [ ] Document wave strategy in `argocd_architecture.md`

### Phase 4: Reloader (Optional, 2 days)
- [ ] Deploy Stakater Reloader to kube-system
- [ ] Add annotations to OAuth-protected Deployments
- [ ] Test secret rotation scenario
- [ ] Document in `docs/08-security/secrets-management.md`

---

## Testing Checklist

**After implementing fixes, test**:

- [ ] Fresh cluster deployment (`./scripts/quick-redeploy.sh`)
- [ ] Keycloak starts and becomes ready
- [ ] oauth2-secrets-extractor Job completes
- [ ] Secrets created in all namespaces
- [ ] **Grafana pods wait for secret** (check initContainer logs)
- [ ] **Kagenti-UI pods wait for secret** (check initContainer logs)
- [ ] **OAuth2-Proxy pods wait for secret** (check initContainer logs)
- [ ] All pods start with 2/2 containers (app + istio-proxy)
- [ ] **No manual pod restarts needed**
- [ ] OAuth login works immediately at:
  - https://grafana.localtest.me:9443
  - https://kagenti.localtest.me:9443
  - https://phoenix.localtest.me:9443
  - https://tempo.localtest.me:9443
  - https://kiali.localtest.me:9443
  - https://prometheus.localtest.me:9443

**Secret rotation test**:
- [ ] Delete `grafana-client-secret` in keycloak namespace
- [ ] Re-run oauth2-secrets-extractor Job
- [ ] **Pods restart automatically** (if Reloader deployed)
- [ ] OAuth login still works after rotation

---

## Related Issues

- `TODO_SECURITY.md` - Secret rotation strategy
- `docs/08-security/secrets-management.md` - Secrets architecture
- `argocd_architecture.md` - Sync wave documentation
- Grafana mTLS fix: `components/02-observability/grafana/deployment.yaml:115` (commit 4d05a26)

---

## Root Cause Analysis

**Why do these issues keep recurring?**

1. **No ordering guarantees** - ArgoCD syncs all apps in wave 0 by default
2. **Async PostSync hooks** - oauth2-secrets-extractor runs after sync completes, but other pods don't wait
3. **Optional env vars** - `optional: true` allows pods to start without secrets
4. **No pod lifecycle management** - Pods don't restart when secrets appear

**This is a classic GitOps bootstrapping problem:**
- Service A depends on Service B
- Both sync at wave 0
- Race condition: which starts first?

**Solution**: Explicit ordering via sync waves + initContainer guards.

---

---

## OAuth Authentication Architecture

### Service Communication Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EXTERNAL ACCESS (Browser)                        │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │
                          │ HTTPS (TLS 1.3)
                          │ Port 9443
                          │
                          ▼
              ┌───────────────────────┐
              │   Istio Gateway       │
              │  (TLS Termination)    │
              └───────────┬───────────┘
                          │
                          │ HTTP (in mesh)
                          │ + mTLS via Istio sidecars
                          │
        ┌─────────────────┼─────────────────┬─────────────────┐
        │                 │                 │                 │
        ▼                 ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ OAuth2-Proxy │  │ OAuth2-Proxy │  │ OAuth2-Proxy │  │   Grafana    │
│  (Phoenix)   │  │ (Prometheus) │  │   (Kiali)    │  │ (Native OAuth)│
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                 │                 │
       │ HTTP (local)    │                 │                 │
       │ + mTLS sidecar  │                 │                 │
       │                 │                 │                 │
       ├─────────────────┴─────────────────┴─────────────────┘
       │
       │ OAuth Token Exchange
       │ http://keycloak.keycloak.svc:8080/.../token
       │ + mTLS via Istio sidecars (REQUIRED)
       │
       ▼
┌──────────────────────┐
│     Keycloak         │
│  Port 8080 (HTTP)    │◄─────── STRICT mTLS enforced by PeerAuthentication
│  Port 9000 (Health)  │         (Plain HTTP rejected → connection reset)
│  Port 9443 (HTTPS)   │
└──────────────────────┘
```

### Security Protocol Matrix

| Connection | Protocol | Security | Notes |
|------------|----------|----------|-------|
| **Browser → Istio Gateway** | HTTPS (TLS 1.3) | TLS certificate from cert-manager | External gateway, port 9443 |
| **Istio Gateway → OAuth2-Proxy** | HTTP | mTLS via Istio sidecars | Automatic sidecar encryption |
| **Istio Gateway → Grafana** | HTTP | mTLS via Istio sidecars | Grafana deployment.yaml:115 |
| **OAuth2-Proxy → Backend Service** | HTTP | mTLS via Istio sidecars | Phoenix, Prometheus, Kiali |
| **OAuth2-Proxy → Keycloak:8080** | HTTP | **STRICT mTLS (required)** | PeerAuthentication enforced |
| **Grafana → Keycloak:8080** | HTTP | **STRICT mTLS (required)** | Token endpoint for OAuth |
| **Kubelet → Keycloak:9000** | HTTP | **No mTLS (DISABLED)** | Health check endpoint |
| **Browser → Keycloak:9443** | HTTPS | TLS certificate from cert-manager | Login UI, admin console |

**Key Points:**
- ✅ **All in-mesh traffic uses mTLS** (automatic via Istio sidecars)
- ✅ **Keycloak port 8080 enforces STRICT mTLS** - clients without sidecar are rejected
- ✅ **No plaintext HTTP crosses the network** (except to localhost sidecar proxy)
- ✅ **Applications speak HTTP to local sidecar** (same pod, not over network)
- ✅ **Sidecars handle all encryption** (transparent to applications)

---

### Deployment Sequence & Timing

**Current State (PROBLEM):**

```
Time   | Wave | Component                        | Status
-------|------|----------------------------------|---------------------------
T+0s   | 0    | Grafana deployment               | Starts, waits for secret
T+0s   | 0    | Kagenti-UI deployment            | Starts, waits for secret
T+0s   | 0    | OAuth2-Proxy deployments         | Starts, waits for secret
T+0s   | 1    | Keycloak StatefulSet             | Starts (database init)
T+120s | 1    | Keycloak becomes Ready           | Port 8080 accepting mTLS
T+180s | 2    | oauth2-secrets-extractor (PostSync) | Job triggered
T+300s | 2    | Secrets created + Reflector      | Mirrored to namespaces
       |      |                                  |
       |      | ⚠️ PROBLEM: Pods started at T+0s before secrets existed!
       |      | ⚠️ ISSUE: optional:true masked the failure (silent start)
       |      | ⚠️ RESULT: Manual pod restart required
```

**After Fix (SOLUTION):**

```
Time   | Wave | Component                        | Status
-------|------|----------------------------------|---------------------------
T+0s   | 5    | Keycloak StatefulSet             | Starts (database init)
T+120s | 5    | Keycloak becomes Ready           | Port 8080 accepting mTLS
T+120s | 10   | oauth2-secrets-extractor         | Job runs immediately
T+180s | 10   | Secrets created + Reflector      | Mirrored to namespaces
T+180s | 15   | Grafana initContainer            | Waits for grafana-client-secret
T+180s | 15   | Kagenti-UI initContainer         | Waits for kagenti-ui-oauth-secret
T+180s | 15   | OAuth2-Proxy initContainers      | Wait for client secrets
T+185s | 15   | All secrets found                | initContainers exit
T+185s | 15   | Main containers start            | ✅ Secrets already available
T+200s | 15   | Pods become Ready                | OAuth working immediately
       |      |                                  |
       |      | ✅ NO manual intervention needed
       |      | ✅ Clean deployment every time
```

**Sync Wave Assignments (Proposed):**

| Wave | Layer | Components |
|------|-------|------------|
| **0-4** | Infrastructure | Gateway API, cert-manager, Istio, Tekton |
| **5** | Platform - Auth | **Keycloak StatefulSet** |
| **10** | Platform - Secrets | **oauth2-secrets-extractor Job** |
| **15** | Platform - UI | **Grafana, Kagenti-UI, OAuth2-Proxy** |
| **20** | Observability | Prometheus, Tempo, Loki, Phoenix, Kiali |
| **30** | Applications | Agents, user workloads |

---

### Health Check & Init Container Verification

**Services with InitContainer Wait Pattern:**

| Service | InitContainer | Secret Name | Namespace | Status |
|---------|--------------|-------------|-----------|--------|
| **Kagenti-UI** | ✅ Yes | `kagenti-ui-oauth-secret` | `kagenti-system` | ✅ VERIFIED |
| **OAuth2-Proxy (Phoenix)** | ✅ Yes | `phoenix-client-secret` | `oauth2-proxy` | ✅ VERIFIED |
| **OAuth2-Proxy (Prometheus)** | ✅ Yes | `prometheus-client-secret` | `oauth2-proxy` | ✅ VERIFIED |
| **OAuth2-Proxy (Kiali)** | ✅ Yes | `kiali-client-secret` | `oauth2-proxy` | ✅ VERIFIED |
| **Grafana** | ❌ **MISSING** | `grafana-client-secret` | `observability` | ⚠️ **NEEDS FIX** |

**InitContainer Pattern Comparison:**

**Kagenti-UI (Advanced - with timeout & key verification):**
```yaml
initContainers:
- name: wait-for-oauth-secret
  image: quay.io/kubestellar/kubectl:1.30.14
  command: ["/bin/sh", "-c"]
  args:
  - |
    echo "Waiting for OAuth secret..."
    MAX_ATTEMPTS=60  # 2 minutes
    ATTEMPT=0
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
      if kubectl get secret kagenti-ui-oauth-secret -n kagenti-system >/dev/null 2>&1; then
        # Verify ALL required keys exist
        REQUIRED_KEYS="CLIENT_ID CLIENT_SECRET AUTH_ENDPOINT TOKEN_ENDPOINT REDIRECT_URI"
        ALL_PRESENT=true
        for KEY in $REQUIRED_KEYS; do
          if ! kubectl get secret kagenti-ui-oauth-secret -n kagenti-system \
               -o jsonpath="{.data.$KEY}" >/dev/null 2>&1; then
            ALL_PRESENT=false
          fi
        done
        if [ "$ALL_PRESENT" = "true" ]; then
          echo "✓ All OAuth keys present"
          exit 0
        fi
      fi
      ATTEMPT=$((ATTEMPT + 1))
      sleep 2
    done
    echo "WARNING: Secret not ready, proceeding anyway"
    exit 0  # Don't block deployment
```

**OAuth2-Proxy (Simple - infinite wait):**
```yaml
initContainers:
- name: wait-for-secret
  image: bitnami/kubectl:latest
  command: ["sh", "-c"]
  args:
  - |
    echo "Waiting for Keycloak client secret phoenix-client-secret..."
    until kubectl get secret phoenix-client-secret -n oauth2-proxy > /dev/null 2>&1; do
      echo "Secret not found, waiting 5s..."
      sleep 5
    done
    echo "Secret found, proceeding"
```

**Grafana (MISSING - needs to be added):**
```yaml
# File: components/02-observability/grafana/deployment.yaml
spec:
  template:
    spec:
      initContainers:
      - name: wait-for-oauth-secret
        image: bitnami/kubectl:latest
        command: ["sh", "-c"]
        args:
        - |
          echo "Waiting for Grafana OAuth secret..."
          until kubectl get secret grafana-client-secret -n observability > /dev/null 2>&1; do
            echo "Secret not found, waiting 5s..."
            sleep 5
          done
          echo "Secret found, proceeding"
      containers:
      - name: grafana
        # ... existing container config
```

---

### OAuth Environment Variable Configuration

**Correct Pattern (Required Credentials):**

```yaml
env:
- name: CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: grafana-client-secret
      key: CLIENT_SECRET
      # optional: false (default)
      # Pod will CreateContainerConfigError if secret missing
      # Kubernetes auto-retries when secret appears
      # ✅ Clear error state, no manual restart needed
```

**WRONG Pattern (Silent Failure):**

```yaml
env:
- name: CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: grafana-client-secret
      key: CLIENT_SECRET
      optional: true  # ❌ BAD
      # Pod starts with empty CLIENT_SECRET=""
      # OAuth fails silently
      # Requires manual pod restart after secret appears
      # ⚠️ NEVER use for required credentials
```

**Exception (Truly Optional Values):**

```yaml
env:
- name: SSL_CERT_FILE  # Not all deployments need custom CA
  valueFrom:
    secretKeyRef:
      name: custom-ca-bundle
      key: ca.crt
      optional: true  # ✅ OK - genuinely optional
```

---

### Secret Creation & Mirroring Flow

```
┌─────────────────────────────────────────────────────────────┐
│  1. Keycloak StatefulSet Starts (Wave 1)                    │
│     - PostgreSQL initializes                                 │
│     - Keycloak realm configuration imported                  │
│     - OAuth clients created: grafana, phoenix, kiali, etc.   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ Ready (port 8080 accepting mTLS)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  2. oauth2-secrets-extractor Job (Wave 2, PostSync Hook)    │
│     - Calls Keycloak Admin API                              │
│     - Extracts client secrets                               │
│     - Creates secrets in 'keycloak' namespace               │
│     - Adds Reflector annotations                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ Secrets created
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Reflector Operator (Watches for annotations)            │
│     - Detects new secrets with reflection-allowed=true      │
│     - Mirrors to target namespaces:                         │
│       • grafana-client-secret → observability               │
│       • phoenix-client-secret → oauth2-proxy                │
│       • kagenti-ui-oauth-secret → kagenti-system            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ Mirroring complete
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Service Pods Start (Wave 15)                            │
│     - initContainers wait for secrets                       │
│     - Kubernetes auto-retries on secret mount failure       │
│     - Main containers start when secrets available          │
│     - OAuth authentication works immediately                │
└─────────────────────────────────────────────────────────────┘
```

**Secrets Created by oauth2-secrets-extractor:**

| Secret Name | Source Realm | Target Namespace | Used By |
|-------------|--------------|------------------|---------|
| `grafana-client-secret` | `kubernetes` | `observability` | Grafana native OAuth |
| `phoenix-client-secret` | `kagenti` | `oauth2-proxy` | Phoenix OAuth2-Proxy |
| `prometheus-client-secret` | `kubernetes` | `oauth2-proxy` | Prometheus OAuth2-Proxy |
| `kiali-client-secret` | `kubernetes` | `oauth2-proxy` | Kiali OAuth2-Proxy |
| `tempo-client-secret` | `kubernetes` | `oauth2-proxy` | Tempo OAuth2-Proxy |
| `kagenti-ui-oauth-secret` | `kagenti` | `kagenti-system` | Kagenti-UI native OAuth |

**Secret Contents (Standard Format):**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-client-secret
  namespace: observability
  annotations:
    reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
    reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
type: Opaque
data:
  CLIENT_ID: Z3JhZmFuYQ==  # base64("grafana")
  CLIENT_SECRET: <base64-encoded-random-secret>
  AUTH_ENDPOINT: <base64(https://keycloak.localtest.me:9443/realms/kubernetes/protocol/openid-connect/auth)>
  TOKEN_ENDPOINT: <base64(http://keycloak.keycloak.svc:8080/realms/kubernetes/protocol/openid-connect/token)>
  REDIRECT_URI: <base64(https://grafana.localtest.me:9443/oauth2/callback)>
  SCOPE: <base64("openid profile email")>
```

---

**Last Updated**: 2025-11-19
**Next Review**: After Phase 2 implementation
