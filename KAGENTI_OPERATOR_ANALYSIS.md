# Kagenti Operator Analysis & Deployment Strategy

**Date**: 2025-11-20
**Purpose**: Document findings about kagenti-operator Helm chart vs Kustomize deployment

---

## Key Findings

### 1. Helm Chart vs Kustomize

**Helm Chart Location**: `/Users/ladas/Projects/OCTO/research/ladas-kagenti-operator/charts/kagenti-operator/`

**What the Helm Chart Provides:**

✅ **Tekton ConfigMaps** (14 files in `templates/tekton/`):
- `github-clone-step.yaml` - Git clone task
- `folder-check-step.yaml` - Folder verification
- `kaniko-build-step-local.yaml` - Local registry Kaniko build
- `kaniko-build-step-external.yaml` - External registry Kaniko build
- `kaniko-build-step.yaml` - Standard Kaniko build
- `buildah-build-step.yaml` - Buildah build (alternative)
- `buildpack-step.yaml` - Buildpack build (alternative)
- `dockerfile-detector-step.yaml` - Dockerfile detection
- `pipeline-template-dev.yaml` - Dev mode pipeline template
- `pipeline-template-dev-local.yaml` - Dev mode local pipeline
- `pipeline-template-dev-external.yaml` - Dev mode external pipeline
- `pipeline-template-buildpack-dev.yaml` - Buildpack dev pipeline

✅ **Operator Deployment** (`templates/manager/`):
- Controller manager deployment
- RBAC (ServiceAccount, Roles, RoleBindings)
- Webhooks (MutatingWebhook, ValidatingWebhook)
- cert-manager integration for webhook certificates
- Metrics service
- Prometheus ServiceMonitor (optional)

✅ **CRDs**:
- Agent CRD
- AgentBuild CRD

**What Kustomize Deployment Provides:**

Current setup: `operators/overlays/local/kagenti-operator/kustomization.yaml`
- ✅ References upstream Kustomize config
- ✅ Uses pre-built image from ghcr.io
- ❌ **MISSING**: Tekton ConfigMaps (not in upstream Kustomize!)

---

## Problem Statement

**Issue**: Upstream `github.com/kagenti/kagenti-operator//kagenti-operator/config/default` Kustomize config does NOT include Tekton ConfigMaps.

**Evidence**:
1. Helm chart has `templates/tekton/` directory with 14 ConfigMaps
2. Kustomize config does NOT have equivalent Tekton ConfigMaps
3. Platform-operator previously had these in `operators/overlays/local/platform-operator/tekton-steps.yaml`

**Impact**:
- AgentBuild CRDs will fail to create Tekton pipelines
- No Tekton step ConfigMaps = no way to define build steps
- Agent builds cannot proceed

---

## Solution Options

### Option A: Use Helm Chart (RECOMMENDED ✅)

**Pros**:
- ✅ Includes ALL Tekton ConfigMaps automatically
- ✅ Includes pipeline templates
- ✅ Official upstream deployment method
- ✅ Easier to manage (single source of truth)
- ✅ Values-based configuration (cleaner than patches)

**Cons**:
- ❌ Different deployment pattern than current Kustomize-based setup
- ❌ Need to migrate from ArgoCD Application (Kustomize) to Helm

**Implementation**:
```yaml
# argocd/applications/kind-local/kagenti-operator.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagenti-operator
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/kagenti/kagenti-operator'  # Or use local chart
    targetRevision: v0.2.0-alpha.17
    path: charts/kagenti-operator
    helm:
      values: |
        controllerManager:
          container:
            image:
              repository: ghcr.io/kagenti/kagenti-operator/kagenti-operator
              tag: v0.2.0-alpha.17
        certmanager:
          enable: true
        webhook:
          enable: true
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: kagenti-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Option B: Kustomize + Manual Tekton ConfigMaps

**Pros**:
- ✅ Consistent with current Kustomize deployment pattern
- ✅ No migration needed for ArgoCD Application

**Cons**:
- ❌ Must manually maintain 14 Tekton ConfigMaps
- ❌ Risk of drift from upstream Helm chart
- ❌ More maintenance overhead
- ❌ Duplicate effort (Helm chart already has them)

**Implementation**:
```bash
# Copy Tekton ConfigMaps from Helm chart to Kustomize overlay
cp /Users/ladas/Projects/OCTO/research/ladas-kagenti-operator/charts/kagenti-operator/templates/tekton/*.yaml \
   operators/overlays/local/kagenti-operator/tekton/

# Update kustomization.yaml to include them
```

### Option C: Hybrid (Kustomize + Helm-rendered Tekton ConfigMaps)

**Pros**:
- ✅ Use Kustomize for operator
- ✅ Use Helm to render Tekton ConfigMaps once

**Cons**:
- ❌ Complex setup
- ❌ Still requires manual updates
- ❌ Not worth the complexity

---

## Recommendation

**Use Option A: Helm Chart Deployment**

**Reasoning**:
1. **Completeness**: Helm chart includes everything needed (operator + Tekton ConfigMaps)
2. **Official support**: Helm is the upstream-supported deployment method
3. **Easier maintenance**: Single source of truth, no manual ConfigMap management
4. **Future-proof**: Upstream changes automatically included on version upgrades

**Migration Plan**:
1. Create new Helm-based ArgoCD Application for kagenti-operator
2. Remove old Kustomize-based kagenti-operator Application
3. Remove platform-operator Application completely
4. Sync and verify deployment

---

## CRD Pattern (from Helm Chart Sample)

**File**: `ladas-kagenti-operator/kagenti-operator/config/samples/weather-agent-build-and-deploy.yaml`

### Pattern: Two CRDs

**1. AgentBuild CRD** - Builds the container image:
```yaml
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentBuild
metadata:
  name: weather-agent-build
  namespace: team1
spec:
  mode: dev
  source:
    sourceRepository: "github.com/redhat-et/agent-examples.git"
    sourceRevision: "main"
    sourceSubfolder: "a2a/weather_service"
    sourceCredentials:
      name: github-token-secret
  pipeline:
    namespace: kagenti-system  # Where Tekton runs
    parameters:
      - name: SOURCE_REPO_SECRET
        value: github-token-secret
  buildOutput:
    image: "weather-service"
    imageTag: "v0.0.1"
    imageRegistry: "localhost:5000"
```

**2. Agent CRD** - Deploys the agent using built image:
```yaml
apiVersion: agent.kagenti.dev/v1alpha1
kind: Agent
metadata:
  name: weather-agent
  namespace: team1
spec:
  description: "Weather agent"
  replicas: 1

  # Reference the AgentBuild
  imageSource:
    buildRef:
      name: weather-agent-build  # References AgentBuild above

  # Full pod template
  podTemplateSpec:
    spec:
      containers:
      - name: agent
        env:
        - name: PORT
          value: "8000"
        - name: LLM_API_BASE
          value: "http://ollama.kagenti-system.svc.cluster.local:11434/v1"
        - name: LLM_MODEL
          value: "qwen2.5:7b"
        # ... more env vars
```

**How it works**:
1. Create AgentBuild CRD → kagenti-operator creates Tekton PipelineRun
2. Tekton builds image using ConfigMap steps → pushes to registry
3. Create Agent CRD with `buildRef` → kagenti-operator creates Deployment
4. Deployment uses image from AgentBuild

---

## Next Steps

1. ✅ **Documented**: Helm chart analysis complete
2. ⏳ **Decision**: Choose Helm chart deployment
3. ⏳ **Implementation**: Create Helm-based ArgoCD Application
4. ⏳ **Remove**: platform-operator Application
5. ⏳ **Test**: Deploy weather agent via AgentBuild + Agent CRDs
6. ⏳ **Verify**: E2E tests pass

---

## References

- **Issue #78**: https://github.com/kagenti/kagenti-operator/issues/78
- **Helm Chart**: `ladas-kagenti-operator/charts/kagenti-operator/`
- **Kustomize**: `github.com/kagenti/kagenti-operator//kagenti-operator/config/default`
- **Sample CRDs**: `ladas-kagenti-operator/kagenti-operator/config/samples/`
- **TODO Document**: `TODO_KAGENTI_OPERATOR_WITH_EXAMPLE_AGENT.md`
