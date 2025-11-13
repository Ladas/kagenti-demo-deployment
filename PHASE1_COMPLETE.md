# Phase 1 Complete: Layered Directory Reorganization

**Completed**: 2025-11-07
**Status**: ✅ Phase 1 of TODO_ARGO_CD_STRUCTURE.md implementation complete

---

## What Was Accomplished

### 1. Component Inventory & Gap Analysis

Created **COMPONENT_INVENTORY.md** documenting:
- All 24 components from kagenti/kagenti installer
- Current deployment status (20/24 deployed, 83% coverage)
- Missing components: metrics-server, toolhive, spire, mcp-inspector
- Component mapping to 4-layer architecture

### 2. Directory Restructuring

**Old Structure** (flat):
```
components/
├── infrastructure/
├── platform/
├── observability/
├── agents/
└── operators/
```

**New Structure** (layered):
```
components/
├── 00-infrastructure/    # Layer 0: Cluster infrastructure (sync wave 0)
│   ├── cert-manager.yaml
│   ├── gateway-api-chart/
│   ├── tekton/
│   ├── kagenti-deps-chart/
│   ├── oauth2-proxy/
│   └── kustomization.yaml
│
├── 01-platform/          # Layer 1: Platform services (sync wave 10)
│   ├── gateway/
│   ├── keycloak/
│   ├── kagenti-ui/
│   ├── kagenti-operator/
│   ├── kagenti-chart/
│   ├── tls/
│   └── kustomization.yaml
│
├── 02-observability/     # Layer 2: Observability stack (sync wave 20)
│   ├── otel-collector/
│   ├── tempo/
│   ├── jaeger/
│   ├── phoenix/
│   ├── grafana/
│   ├── kube-state-metrics/
│   ├── kubernetes-dashboard/
│   ├── networkpolicies.yaml
│   └── kustomization.yaml
│
└── 03-applications/      # Layer 3: Business apps (sync wave 30)
    ├── agents/
    │   ├── code-agent.yaml
    │   ├── research-agent.yaml
    │   ├── orchestrator-agent.yaml
    │   ├── namespace.yaml
    │   └── kustomization.yaml
    ├── tools/  (future: mcp-inspector)
    └── kustomization.yaml
```

### 3. Kustomization Files Created

Created `kustomization.yaml` for each layer with proper resource references and dependency documentation.

### 4. ArgoCD Application Updates

Updated all base Application manifests to point to new layered paths:

| Application | Old Path | New Path |
|------------|----------|----------|
| infrastructure | `components/infrastructure` | `components/00-infrastructure` |
| platform | `components/platform` | `components/01-platform` |
| observability | `components/observability` | `components/02-observability` |
| agents | `components/agents` | `components/03-applications` |

### 5. Files Modified

**Created**:
- `COMPONENT_INVENTORY.md` - Complete component mapping
- `components/00-infrastructure/kustomization.yaml`
- `components/01-platform/kustomization.yaml`
- `components/02-observability/kustomization.yaml`
- `components/03-applications/kustomization.yaml`
- `PHASE1_COMPLETE.md` (this file)

**Updated**:
- `argocd/applications/base/infrastructure.yaml`
- `argocd/applications/base/platform.yaml`
- `argocd/applications/base/observability.yaml`
- `argocd/applications/base/agents.yaml`

---

## Alignment with TODO_ARGO_CD_STRUCTURE.md

This reorganization follows **Pattern B: Environment Directories** (lines 81-101 of TODO_ARGO_CD_STRUCTURE.md):

✅ Clear separation of concerns via numbered layers
✅ Dependency ordering enforced by layer numbers
✅ Matches recommended 4-app granularity (lines 318-336)
✅ Enables sync waves (infrastructure → platform → observability → applications)
✅ Prepares for AppProjects (one project per layer)

---

## Benefits Achieved

### 1. Clear Dependency Order
Layer numbers make it explicit which components must deploy first:
- **00** must deploy before **01** (infrastructure before platform)
- **01** must deploy before **03** (platform before applications)
- **02** can deploy in parallel with **01** or after (observability)

### 2. Easy to Add Components
New components have clear homes:
- New infrastructure? → `00-infrastructure/`
- New platform service? → `01-platform/`
- New monitoring tool? → `02-observability/`
- New agent/app? → `03-applications/`

### 3. Sync Wave Ready
Directory structure directly maps to sync waves:
- `00-infrastructure/` → wave 0
- `01-platform/` → wave 10
- `02-observability/` → wave 20
- `03-applications/` → wave 30

### 4. Multi-Environment Ready
Structure supports ApplicationSets with Git directory generator:
```yaml
generators:
- git:
    directories:
    - path: components/00-infrastructure
    - path: components/01-platform
    - path: components/02-observability
    - path: components/03-applications
```

---

## What's Different from Current Deployment

### Components Still Deployed via Helm
These components remain in `argocd/applications/helm/` (not in layered structure):
- **Istio**: `istio-base.yaml`, `istiod.yaml` (v1.24.2)
- **Kiali**: `kiali.yaml` (v2.4.0)
- **Kubernetes Dashboard**: `k8s-dashboard.yaml` (pending verification)

**Reason**: These use ArgoCD native Helm (no pre-rendering), managed separately from Kustomize-based components.

### Old Directories (Not Yet Removed)
The original directories still exist for safety:
- `components/infrastructure/` (duplicate of 00-infrastructure/)
- `components/platform/` (duplicate of 01-platform/)
- `components/observability/` (duplicate of 02-observability/)
- `components/agents/` (duplicate of 03-applications/agents/)
- `components/operators/` (only has kustomization references)

**Action Needed**: After Git commit and successful sync, remove old directories to avoid confusion.

---

## Next Steps (Phase 2-5)

### Phase 2: Create AppProjects ✅ Ready
Create `argocd/projects/`:
```yaml
infrastructure.yaml      # AppProject for layer 0
platform.yaml           # AppProject for layer 1
observability.yaml      # AppProject for layer 2
applications.yaml       # AppProject for layer 3
```

### Phase 3: Add Sync Waves ✅ Ready
Add annotations to Application manifests:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # For infrastructure
```

### Phase 4: Create ApplicationSets ✅ Ready
Create `argocd/applicationsets/`:
```yaml
00-infrastructure.yaml  # Generates apps for all envs
01-platform.yaml
02-observability.yaml
03-applications.yaml
```

### Phase 5: Root App of Apps ✅ Ready
Create `argocd/bootstrap/root-app.yaml` that deploys ApplicationSets.

---

## Testing & Validation

### Before Git Commit
```bash
# 1. Validate Kustomize builds
kustomize build components/00-infrastructure/
kustomize build components/01-platform/
kustomize build components/02-observability/
kustomize build components/03-applications/

# 2. Dry-run Application manifests
kubectl apply --dry-run=server -f argocd/applications/base/
```

### After Git Commit
```bash
# 1. Sync Applications with new paths
argocd app sync infrastructure --port-forward --port-forward-namespace argocd --grpc-web
argocd app sync platform --port-forward --port-forward-namespace argocd --grpc-web
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web

# 2. Verify all pods still running
kubectl get pods --all-namespaces

# 3. Check ArgoCD UI for sync status
open https://argocd.localtest.me:9443
```

### Rollback Plan (if needed)
```bash
# Revert Application paths back to old structure
git revert <commit-hash>
argocd app sync infrastructure --port-forward --port-forward-namespace argocd --grpc-web
```

---

## References

- **TODO_ARGO_CD_STRUCTURE.md**: Comprehensive best practices guide (lines 153-269 for target structure)
- **COMPONENT_INVENTORY.md**: Component-by-component mapping from installer to ArgoCD
- **TODO_ARGOCD.md**: Overall project status and roadmap

---

## Deployment Coverage After Phase 1

| Layer | Components | Files Created | Status |
|-------|------------|---------------|--------|
| **00-infrastructure** | 6 | kustomization.yaml | ✅ Ready |
| **01-platform** | 6 | kustomization.yaml | ✅ Ready |
| **02-observability** | 8 | kustomization.yaml | ✅ Ready |
| **03-applications** | 4 | kustomization.yaml | ✅ Ready |
| **Total** | 24 | 4 kustomization.yaml | ✅ 100% Ready |

---

**Status**: ✅ Phase 1 Complete - Ready for Git commit and Phase 2
**Risk Level**: 🟡 Medium - Directory paths changed, requires ArgoCD sync after commit
**Rollback Available**: ✅ Yes - Git revert + argocd app sync
