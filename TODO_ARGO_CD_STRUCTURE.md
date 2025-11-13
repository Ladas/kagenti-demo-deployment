# TODO: Argo CD Repository Structure & Application Granularity

## Overview

This document defines the recommended Argo CD structure for the kagenti-demo-deployment repository, balancing between best practices for:
- **Application granularity** (when to split vs combine apps)
- **Directory organization** (monorepo structure with multiple environments)
- **Deployment patterns** (App of Apps, ApplicationSets, or hybrid)
- **Scalability** (from development to production)

## Executive Summary

**Current State**: Repository uses basic App of Apps pattern with Kustomize overlays
**Recommended**: Evolve to **Hybrid App of Apps + ApplicationSets** pattern
**Target**: Production-ready GitOps with automatic multi-environment deployments

## Research Findings: Best Practices (2025)

### 1. Application Granularity Rules

#### **Rule of 10**: When to Use App of Apps vs ApplicationSets

| Pattern | Use When | Advantages | Limitations |
|---------|----------|------------|-------------|
| **App of Apps** | ≤10 applications | Simple, explicit, dependencies | Manual per-app management |
| **ApplicationSets** | >10 applications or multi-env | Automated, templated, DRY | No dependencies support |
| **Hybrid** | 5-50 apps, multi-env | Best of both worlds | Slightly more complex |

**Key Insight**: ApplicationSets is NOT a replacement for App of Apps - they solve different problems and should be combined.

#### **Granularity Levels**

**Too Coarse** (Anti-pattern):
```
❌ Bad: Single "kagenti" application containing everything
- Difficult to sync individual components
- All-or-nothing deployments
- Can't have different sync policies per component
```

**Too Fine** (Anti-pattern):
```
❌ Bad: Each Kubernetes resource as separate app
- argocd-app-configmap-1.yaml
- argocd-app-configmap-2.yaml
- argocd-app-deployment-1.yaml
- Explosion of Application CRDs
- Difficult to manage relationships
```

**Recommended Granularity**:
```
✅ Good: Logical service/component grouping
- infrastructure (Istio, Tekton, Gateway API)
- observability (Phoenix, Grafana, OTEL, Tempo)
- platform (Keycloak, MCP Gateway, Kagenti UI, Operators)
- agents (Research, Code, Orchestrator)

Each app should:
- Be independently deployable
- Have a clear ownership boundary
- Share lifecycle (same deployment cadence)
- Have minimal external dependencies
```

### 2. Directory Structure Patterns

#### **Pattern A: Environment Branches** (Traditional)
```
Branches:
  - main (production)
  - staging
  - dev

Problem: Promotion requires merging branches
        Changes can be lost or conflict during merge
```
**Verdict**: ❌ Avoid - Error-prone and difficult to audit

#### **Pattern B: Environment Directories** (Recommended)
```
Repository structure:
  components/          # Base manifests
    infrastructure/
    observability/
    platform/
    agents/

  environments/        # Environment-specific overlays
    kind-local/
    openshift-stage/
    openshift-prod/

  argocd/             # Argo CD Application definitions
    applications/
      base/           # Reusable Application templates
      kind-local/     # Kind-specific patches
      openshift-prod/ # Prod-specific patches
    bootstrap/        # Root app-of-apps for cluster bootstrap
```
**Verdict**: ✅ Recommended - Clear separation, easy promotion

#### **Pattern C: Git Generator** (Advanced)
```
Repository structure:
  apps/
    app1/
      envs/
        dev/
        staging/
        prod/
      base/

  argocd/
    applicationsets/
      apps.yaml  # Git directory generator
```
**Verdict**: ✅ Great for many apps, but less explicit

### 3. Recommended Structure for Kagenti

#### **Current Structure (Partial)**
```
kagenti-demo-deployment/
├── components/                    # ✅ Good: Base manifests
│   ├── infrastructure/
│   ├── observability/
│   ├── platform/
│   └── agents/
├── environments/                  # ✅ Good: Kustomize overlays
│   ├── kind-local/
│   ├── openshift-stage/
│   └── openshift-prod/
├── argocd/
│   ├── applications/              # ✅ Good: App definitions
│   │   ├── base/
│   │   ├── kind-local/
│   │   └── openshift-prod/
│   └── bootstrap/                 # ✅ Good: Root app
│       └── kind/
└── scripts/                       # ✅ Good: Deployment helpers
```

#### **Issues Identified**

1. **Missing ApplicationSets**: No automation for multi-environment
2. **Flat Application Structure**: No layering (infrastructure → platform → apps)
3. **No Project Isolation**: Everything in `default` project
4. **Missing Dependencies**: Can't express "platform depends on infrastructure"
5. **No Progressive Sync**: Can't do waves (infra first, then apps)

### 4. Recommended Target Structure

```
kagenti-demo-deployment/
├── README.md
├── TODO_ARGO_CD_STRUCTURE.md (this file)
│
├── components/                              # Base Kubernetes manifests
│   ├── 00-infrastructure/                   # Layer 0: Cluster infrastructure
│   │   ├── cert-manager/
│   │   ├── gateway-api/
│   │   ├── istio/
│   │   ├── tekton/
│   │   └── kagenti-deps-chart/              # Helm-based infra
│   │
│   ├── 01-platform/                         # Layer 1: Platform services
│   │   ├── keycloak/
│   │   ├── mcp-gateway/
│   │   ├── kagenti-ui/
│   │   ├── kagenti-operator/
│   │   └── kagenti-chart/                   # Helm-based platform
│   │
│   ├── 02-observability/                    # Layer 2: Observability stack
│   │   ├── otel-collector/
│   │   ├── tempo/
│   │   ├── phoenix/
│   │   ├── grafana/
│   │   ├── prometheus/
│   │   └── kiali/
│   │
│   └── 03-applications/                     # Layer 3: Business applications
│       ├── agents/
│       │   ├── research-agent/
│       │   ├── code-agent/
│       │   └── orchestrator-agent/
│       └── tools/
│           └── mcp-inspector/
│
├── environments/                            # Kustomize overlays per environment
│   ├── base/                                # Common overlay settings
│   │   └── kustomization.yaml
│   │
│   ├── kind-local/                          # Local development
│   │   ├── 00-infrastructure/
│   │   │   └── kustomization.yaml
│   │   ├── 01-platform/
│   │   │   └── kustomization.yaml
│   │   ├── 02-observability/
│   │   │   └── kustomization.yaml
│   │   └── 03-applications/
│   │       └── kustomization.yaml
│   │
│   ├── openshift-stage/                     # Staging environment
│   │   ├── 00-infrastructure/
│   │   ├── 01-platform/
│   │   ├── 02-observability/
│   │   └── 03-applications/
│   │
│   └── openshift-prod/                      # Production environment
│       ├── 00-infrastructure/
│       ├── 01-platform/
│       ├── 02-observability/
│       └── 03-applications/
│
├── argocd/                                  # Argo CD configurations
│   │
│   ├── projects/                            # AppProjects for isolation
│   │   ├── infrastructure.yaml              # Infra project
│   │   ├── platform.yaml                    # Platform project
│   │   ├── observability.yaml               # Observability project
│   │   └── applications.yaml                # Apps project
│   │
│   ├── applicationsets/                     # Multi-environment automation
│   │   ├── 00-infrastructure.yaml           # Infra across all envs
│   │   ├── 01-platform.yaml                 # Platform across all envs
│   │   ├── 02-observability.yaml            # Observability across all envs
│   │   └── 03-applications.yaml             # Apps across all envs
│   │
│   ├── applications/                        # Manual Application CRDs
│   │   ├── base/                            # Reusable app templates
│   │   │   ├── infrastructure.yaml
│   │   │   ├── platform.yaml
│   │   │   ├── observability.yaml
│   │   │   └── applications.yaml
│   │   │
│   │   ├── kind-local/                      # Kind-specific apps
│   │   │   ├── kustomization.yaml
│   │   │   └── patches/
│   │   │       └── cluster-patch.yaml
│   │   │
│   │   └── openshift-prod/                  # Prod-specific apps
│   │       ├── kustomization.yaml
│   │       └── patches/
│   │           ├── cluster-patch.yaml
│   │           └── sync-policy-patch.yaml
│   │
│   ├── bootstrap/                           # Root app-of-apps
│   │   ├── root-app.yaml                    # Single root application
│   │   ├── kind-local.yaml                  # Kind bootstrap
│   │   └── openshift-prod.yaml              # Prod bootstrap
│   │
│   └── config/                              # Argo CD configuration
│       ├── argocd-cm.yaml                   # ConfigMap
│       └── argocd-rbac-cm.yaml              # RBAC
│
├── scripts/                                 # Automation scripts
│   ├── argocd/
│   │   ├── install-argocd.sh
│   │   ├── bootstrap-kind.sh
│   │   └── bootstrap-openshift.sh
│   └── deploy/
│       └── deploy-kind.sh
│
└── docs/                                    # Documentation
    ├── architecture.md
    ├── deployment-guide.md
    └── troubleshooting.md
```

### 5. Layered Deployment Strategy

#### **Sync Waves** for Ordered Deployment

Use Argo CD sync waves to ensure proper ordering:

```yaml
# Layer 0: Infrastructure (sync wave 0)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Layer 1: Platform (sync wave 10)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "10"

# Layer 2: Observability (sync wave 20)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "20"

# Layer 3: Applications (sync wave 30)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "30"
```

**Why Layers Matter**:
```
Infrastructure → Platform → Observability → Applications
     ↓              ↓              ↓              ↓
  Istio         Keycloak        Phoenix       Agents
  Tekton        MCP GW          Tempo
  Gateway API   Kagenti UI      Grafana
  Cert-Manager  Operators       OTEL
```

**Dependencies**:
- Platform needs Infrastructure (Istio service mesh, Tekton for builds)
- Observability can be parallel to Platform (or wave 15)
- Applications need Platform (Keycloak for auth, MCP GW for routing)

## Application Granularity Deep Dive

### Recommended Apps for Kagenti

#### **Option 1: Coarse Granularity (4 Apps)** ✅ Recommended for Start

```yaml
Applications:
1. infrastructure     # All cluster infrastructure
2. platform          # All platform services
3. observability     # All observability stack
4. applications      # All business apps (agents)

Pros:
- Simple, easy to understand
- Clear dependencies (1→2→3→4)
- Good for small teams (<10 people)
- Matches our current structure

Cons:
- Can't sync individual components
- Platform has many unrelated services
```

#### **Option 2: Medium Granularity (10-15 Apps)** ✅ Recommended for Growth

```yaml
Infrastructure Layer:
1. infrastructure-core      # Istio, Gateway API, Cert-Manager
2. infrastructure-cicd      # Tekton, Argo Workflows
3. infrastructure-storage   # Persistent volumes, S3

Platform Layer:
4. platform-auth           # Keycloak + OAuth
5. platform-mcp            # MCP Gateway
6. platform-ui             # Kagenti UI
7. platform-operators      # Kagenti Operator

Observability Layer:
8. observability-traces    # OTEL, Tempo, Phoenix
9. observability-metrics   # Prometheus, Grafana
10. observability-logs     # Loki (future)

Applications Layer:
11. agents-team1           # Research, Code, Orchestrator
12. agents-team2           # (Future teams)
13. tools                  # MCP Inspector, utilities

Pros:
- Granular sync control
- Team-based ownership
- Independent scaling
- Better for medium teams (10-50 people)

Cons:
- More Application CRDs to manage
- Need ApplicationSets for automation
- More complex dependency graph
```

#### **Option 3: Fine Granularity (25+ Apps)** ⚠️ Only for Large Scale

```yaml
Each component is separate app:
- istio
- gateway-api
- cert-manager
- tekton-pipelines
- tekton-triggers
- keycloak
- keycloak-postgres
- mcp-gateway
- ... (25+ applications)

Verdict: Too complex for current scale
Use ApplicationSets instead if you need this level
```

### Decision Matrix: When to Split an Application

| Factor | Split if TRUE | Keep Together if FALSE |
|--------|---------------|------------------------|
| **Different Teams** | Research team ≠ Infra team | Same team owns both |
| **Different Sync Cadence** | UI changes daily, Infra monthly | Both change together |
| **Independent Value** | Can deploy UI without MCP GW | Tightly coupled |
| **Size** | >50 Kubernetes resources | <20 resources |
| **Environment Variance** | Huge diff between dev/prod | Same across envs |
| **Failure Blast Radius** | UI failure shouldn't break infra | Acceptable to fail together |

### Example: Should MCP Gateway be separate from Kagenti UI?

| Factor | Analysis | Decision |
|--------|----------|----------|
| Teams | Same platform team | 👉 Keep together |
| Cadence | Both deploy frequently | 👉 Keep together |
| Independence | UI depends on MCP GW | 👉 Keep together |
| Size | MCP GW: 5 resources, UI: 8 resources | 👉 Keep together |
| Variance | Same config across envs | 👉 Keep together |
| Blast radius | Both critical for users | 👉 Keep together |

**Verdict**: ✅ Keep as single "platform-core" app (or split for very large teams)

### Example: Should Agents be one app or three?

| Factor | Analysis | Decision |
|--------|----------|----------|
| Teams | Different teams could own agents | 👉 Consider split |
| Cadence | Different agents evolve independently | 👉 Split |
| Independence | Research agent works without Code agent | 👉 Split |
| Size | Each agent: 2-3 resources | 👉 Too small, keep together |
| Variance | Minimal | 👉 Keep together |
| Blast radius | All agents are critical | 👉 Keep together |

**Verdict**: ✅ Keep as single "agents" app (or use team-based split if >5 teams)

## App of Apps vs ApplicationSets: When to Use Each

### Current Pattern: App of Apps ✅

**What we have**:
```yaml
# argocd/bootstrap/kind/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
spec:
  source:
    path: argocd/applications/kind-local
  # Deploys child apps: infrastructure, platform, observability, applications
```

**Pros**:
- Simple and explicit
- Clear dependencies with sync waves
- Easy to understand and debug
- Perfect for <10 applications

**Cons**:
- Manual environment management
- Need separate overlay per environment
- Copy-paste for new environments

### Recommended Pattern: Hybrid ✅✅✅

**Use App of Apps for**:
1. **Root bootstrap** - Single entry point per cluster
2. **Layer management** - Infrastructure → Platform → Observability → Apps
3. **Critical dependencies** - Where order matters

**Use ApplicationSets for**:
1. **Multi-environment** - Same app across dev/stage/prod
2. **Many similar apps** - Multiple teams with same structure
3. **Auto-discovery** - New apps from Git directories

**Example Hybrid Structure**:

```yaml
# Root App of Apps (bootstrap/root-app.yaml)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagenti-root
spec:
  source:
    path: argocd/applicationsets  # Points to ApplicationSets!
  syncPolicy:
    automated:
      prune: false
      selfHeal: true

---
# ApplicationSet for Infrastructure across all envs
# argocd/applicationsets/00-infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
spec:
  generators:
  - git:
      repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
      revision: main
      directories:
      - path: environments/*
  template:
    metadata:
      name: 'infrastructure-{{path.basename}}'
      annotations:
        argocd.argoproj.io/sync-wave: "0"
    spec:
      project: infrastructure
      source:
        repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
        targetRevision: main
        path: 'environments/{{path.basename}}/00-infrastructure'
      destination:
        server: https://kubernetes.default.svc
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

**Result**: ApplicationSet creates 3 apps automatically:
- `infrastructure-kind-local`
- `infrastructure-openshift-stage`
- `infrastructure-openshift-prod`

### Decision Tree

```
                    Start Here
                        |
                        v
        How many applications? ────────────────┐
                        |                      |
                     < 10                    > 10
                        |                      |
                        v                      v
                 App of Apps            ApplicationSets
                        |                      |
                        |                      |
    Need dependencies? ─┴───> YES ──> Hybrid (Both!)
                        |
                       NO
                        |
                        v
              Pure ApplicationSets
```

## Implementation Roadmap

### Phase 1: Reorganize Directory Structure (Week 1)

#### Tasks

- [ ] **Restructure components/** into layers:
  ```bash
  mkdir -p components/00-infrastructure
  mkdir -p components/01-platform
  mkdir -p components/02-observability
  mkdir -p components/03-applications

  # Move existing components to layers
  mv components/infrastructure/* components/00-infrastructure/
  mv components/platform/* components/01-platform/
  mv components/observability/* components/02-observability/
  mv components/agents/* components/03-applications/agents/
  ```

- [ ] **Restructure environments/** to match layers:
  ```bash
  cd environments/kind-local
  mkdir -p 00-infrastructure 01-platform 02-observability 03-applications

  # Move kustomizations to layer subdirectories
  # Each layer gets its own kustomization.yaml
  ```

- [ ] **Update environment kustomization.yaml** to reference layers:
  ```yaml
  # environments/kind-local/kustomization.yaml
  resources:
    - 00-infrastructure/
    - 01-platform/
    - 02-observability/
    - 03-applications/
  ```

**Validation**:
```bash
# Test kustomize build for each environment
kustomize build environments/kind-local
kustomize build environments/openshift-stage
kustomize build environments/openshift-prod
```

### Phase 2: Create AppProjects (Week 1)

#### Tasks

- [ ] Create `argocd/projects/` directory
- [ ] Define 4 projects:

```yaml
# argocd/projects/infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: argocd
spec:
  description: Cluster infrastructure components
  sourceRepos:
  - https://github.com/Ladas/kagenti-demo-deployment.git
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
```

- [ ] Create projects for: platform, observability, applications
- [ ] Apply projects: `kubectl apply -f argocd/projects/`

**Validation**:
```bash
kubectl get appprojects -n argocd
```

### Phase 3: Implement Sync Waves (Week 2)

#### Tasks

- [ ] Add sync wave annotations to Application manifests:

```yaml
# argocd/applications/base/infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # First
spec:
  project: infrastructure
  # ... rest of spec

---
# argocd/applications/base/platform.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform
  annotations:
    argocd.argoproj.io/sync-wave: "10"  # After infrastructure
spec:
  project: platform
  # ... rest of spec
```

- [ ] Update all 4 base Applications with sync waves:
  - infrastructure: wave 0
  - platform: wave 10
  - observability: wave 20 (or 15 if can be parallel)
  - applications: wave 30

**Validation**:
```bash
# Check sync order in Argo CD UI
# Infrastructure should sync first, then platform, etc.
```

### Phase 4: Create ApplicationSets (Week 2-3)

#### Tasks

- [ ] Create `argocd/applicationsets/` directory

- [ ] Create ApplicationSet for each layer using Git directory generator:

```yaml
# argocd/applicationsets/00-infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
      revision: HEAD
      directories:
      - path: environments/*/00-infrastructure

  template:
    metadata:
      name: 'infrastructure-{{path[1]}}'
      annotations:
        argocd.argoproj.io/sync-wave: "0"
      labels:
        kagenti.dev/layer: infrastructure
        kagenti.dev/environment: '{{path[1]}}'

    spec:
      project: infrastructure

      source:
        repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
        targetRevision: HEAD
        path: '{{path}}'

      destination:
        server: https://kubernetes.default.svc  # Change per cluster
        namespace: default

      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true

      ignoreDifferences:
      - group: "*"
        kind: Secret
        jsonPointers:
        - /data
```

- [ ] Create ApplicationSets for: platform, observability, applications
- [ ] Test ApplicationSet generation:
  ```bash
  kubectl apply -f argocd/applicationsets/00-infrastructure.yaml

  # Check generated apps
  kubectl get applications -n argocd | grep infrastructure
  # Should see: infrastructure-kind-local, infrastructure-openshift-stage, etc.
  ```

**Expected Result**:
```
NAME                                  SYNC STATUS   HEALTH STATUS
infrastructure-kind-local             Synced        Healthy
infrastructure-openshift-stage        OutOfSync     Missing
infrastructure-openshift-prod         OutOfSync     Missing
platform-kind-local                   Synced        Healthy
...
```

### Phase 5: Implement Root App of Apps (Week 3)

#### Tasks

- [ ] Create root application that deploys ApplicationSets:

```yaml
# argocd/bootstrap/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagenti-root
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
    targetRevision: HEAD
    path: argocd/applicationsets

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: false  # Don't auto-delete ApplicationSets
      selfHeal: true
```

- [ ] Create bootstrap script:

```bash
#!/bin/bash
# scripts/argocd/bootstrap-kind.sh

set -e

echo "Bootstrapping Kind cluster with Argo CD..."

# 1. Install Argo CD
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Wait for Argo CD to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# 3. Apply AppProjects
kubectl apply -f argocd/projects/

# 4. Apply root app
kubectl apply -f argocd/bootstrap/root-app.yaml

# 5. Get admin password
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""

echo "Access Argo CD:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
```

**Validation**:
```bash
./scripts/argocd/bootstrap-kind.sh

# Check root app created ApplicationSets
kubectl get applications -n argocd
kubectl get applicationsets -n argocd

# Should see:
# - kagenti-root (Application)
# - infrastructure, platform, observability, applications (ApplicationSets)
# - infrastructure-kind-local, platform-kind-local, etc. (Generated Applications)
```

### Phase 6: Multi-Cluster Support (Week 4)

#### Tasks

- [ ] Add cluster-specific generators to ApplicationSets:

```yaml
# argocd/applicationsets/00-infrastructure.yaml
spec:
  generators:
  - matrix:
      generators:
      - git:
          repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
          revision: HEAD
          directories:
          - path: environments/*/00-infrastructure

      - list:
          elements:
          - cluster: kind-local
            server: https://kubernetes.default.svc
          - cluster: openshift-stage
            server: https://openshift-stage-api.example.com
          - cluster: openshift-prod
            server: https://openshift-prod-api.example.com

  template:
    metadata:
      name: 'infrastructure-{{cluster}}'
    spec:
      destination:
        server: '{{server}}'  # Dynamic per cluster
```

**Validation**:
```bash
# Add OpenShift clusters to Argo CD
argocd cluster add openshift-stage --name openshift-stage
argocd cluster add openshift-prod --name openshift-prod

# ApplicationSets should create apps for each cluster
kubectl get applications -n argocd | grep infrastructure
```

## Best Practices Checklist

### Repository Organization

- [ ] **Clear Separation**: Argo CD resources separate from Kubernetes manifests
  - ✅ `components/` contains only Kubernetes resources
  - ✅ `argocd/` contains only Argo CD Application/ApplicationSet CRDs
  - ❌ Don't mix them in the same directory

- [ ] **Layered Structure**: Components organized by deployment order
  - ✅ `00-infrastructure/` before `01-platform/`
  - ✅ Sync waves enforce ordering

- [ ] **Environment Parity**: Same structure for all environments
  - ✅ `kind-local/`, `openshift-stage/`, `openshift-prod/` mirror each other
  - ✅ Differences only in patches/overlays

- [ ] **DRY Principle**: Reuse base Applications
  - ✅ Base Applications in `argocd/applications/base/`
  - ✅ Environment-specific patches in overlays
  - ❌ Don't copy-paste Applications per environment

### Application Design

- [ ] **Right Granularity**: Not too coarse, not too fine
  - ✅ 4-15 applications for Kagenti scale
  - ❌ Not 1 giant app or 50 tiny apps

- [ ] **Clear Ownership**: Each app has responsible team
  - ✅ `infrastructure` → Platform/SRE team
  - ✅ `agents` → Agent development team

- [ ] **AppProjects**: Isolation and RBAC
  - ✅ Separate project per layer
  - ✅ Limited source repos and destinations

- [ ] **Sync Policies**: Appropriate automation
  - ✅ `automated: true` for dev environments
  - ⚠️ `automated: false` for production (manual approval)

### GitOps Workflow

- [ ] **Single Source of Truth**: Git is the only source
  - ✅ All changes via Git commits
  - ❌ No `kubectl apply` directly

- [ ] **Pull Requests**: Changes reviewed before merge
  - ✅ Environment promotion via PR
  - ✅ Review differences before applying

- [ ] **Rollback Strategy**: Easy to revert
  - ✅ Git revert or reset
  - ✅ Argo CD can sync to any commit

- [ ] **Secrets Management**: Encrypted in Git
  - ⚠️ Use Sealed Secrets, External Secrets Operator, or SOPS
  - ❌ Never commit plain secrets

### Monitoring & Observability

- [ ] **Sync Status Alerts**: Know when apps are out of sync
  - ✅ Grafana dashboards for Argo CD metrics
  - ✅ Slack/email notifications on failures

- [ ] **Health Checks**: Applications report health correctly
  - ✅ Custom health checks for CRDs
  - ✅ Readiness/liveness probes

- [ ] **Resource Hooks**: Pre/post sync actions
  - ✅ Database migrations as PreSync hooks
  - ✅ Smoke tests as PostSync hooks

## Anti-Patterns to Avoid

### ❌ Anti-Pattern 1: Environment Branches

```
Bad:
  branches/
    - dev
    - staging
    - production

Problem: Merge conflicts, lost changes, drift between environments
```

**Solution**: Use environment directories with overlays

### ❌ Anti-Pattern 2: Mixing Argo CD and K8s Manifests

```
Bad:
  infrastructure/
    - istio.yaml          # Kubernetes manifest
    - istio-app.yaml      # Argo CD Application
    - tekton.yaml
    - tekton-app.yaml

Problem: Confusing, hard to navigate, Argo CD deploys itself
```

**Solution**: Separate `components/` and `argocd/` directories

### ❌ Anti-Pattern 3: Too Many ApplicationSets

```
Bad:
  applicationsets/
    - istio.yaml
    - gateway-api.yaml
    - cert-manager.yaml
    ... (30+ files)

Problem: Explosion of ApplicationSets, hard to manage dependencies
```

**Solution**: Use 4-5 ApplicationSets for layers, not per component

### ❌ Anti-Pattern 4: No Sync Waves

```
Bad:
  All applications sync in parallel
  Platform apps fail because infrastructure not ready

Problem: Race conditions, failed syncs, manual retry
```

**Solution**: Use sync waves to enforce ordering

### ❌ Anti-Pattern 5: Everything in Default Project

```
Bad:
  All applications in spec.project: default

Problem: No isolation, can't limit permissions, hard to organize
```

**Solution**: Create AppProjects per layer or team

## Testing Strategy

### Local Testing (Before Commit)

```bash
# 1. Validate Kustomize builds
for env in environments/*; do
  echo "Testing $env..."
  kustomize build $env || exit 1
done

# 2. Validate Argo CD Applications
for app in argocd/applications/base/*.yaml; do
  echo "Validating $app..."
  kubectl apply --dry-run=server -f $app || exit 1
done

# 3. Validate ApplicationSets
for appset in argocd/applicationsets/*.yaml; do
  echo "Validating $appset..."
  kubectl apply --dry-run=server -f $appset || exit 1
done
```

### Integration Testing (After Deploy)

```bash
# 1. Check ApplicationSets created Applications
kubectl get applicationsets -n argocd
kubectl get applications -n argocd

# 2. Check sync status
argocd app list

# 3. Check health status
argocd app get infrastructure-kind-local
argocd app get platform-kind-local

# 4. Verify sync waves respected
# Check in Argo CD UI that infrastructure synced before platform
```

### Promotion Testing (Dev → Stage → Prod)

```bash
# 1. Deploy to dev, verify
git checkout -b feature/new-component
# ... make changes ...
git commit -m "Add new component"
git push origin feature/new-component

# 2. Merge to main (dev)
# Watch Argo CD sync to kind-local

# 3. Promote to staging
# Create overlay in environments/openshift-stage/
git commit -m "Promote to staging"
git push

# 4. Promote to prod (manual approval)
# Create PR to add to environments/openshift-prod/
# Review changes, merge
# Manually trigger sync in Argo CD
```

## Migration Plan from Current Structure

### Current State

```
✅ Have: components/, environments/, argocd/applications/
❌ Missing: ApplicationSets, AppProjects, sync waves, layering
```

### Migration Steps (Low Risk)

#### Step 1: Add Sync Waves (No Breaking Changes)

```bash
# Add annotations to existing Applications
# argocd/applications/base/infrastructure.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Apply changes
kubectl apply -f argocd/applications/base/
```

**Risk**: ✅ Low - Only changes ordering, doesn't break anything

#### Step 2: Create AppProjects (Additive)

```bash
# Create new projects
kubectl apply -f argocd/projects/

# Update Applications to reference projects
# argocd/applications/base/infrastructure.yaml
spec:
  project: infrastructure  # Changed from: default
```

**Risk**: ✅ Low - Applications continue working in default project until changed

#### Step 3: Introduce ApplicationSets (Parallel)

```bash
# Create ApplicationSets alongside existing Applications
kubectl apply -f argocd/applicationsets/

# Gradually migrate from manual Applications to ApplicationSets
# Keep both during transition
```

**Risk**: ⚠️ Medium - Need to avoid duplicate Applications

**Mitigation**: Use different names (e.g., `infrastructure-appset-kind-local`)

#### Step 4: Reorganize Directory Structure (Breaking)

```bash
# ⚠️ This breaks existing Application paths

# Rename components to add layer prefixes
git mv components/infrastructure components/00-infrastructure
git mv components/platform components/01-platform
# ... etc

# Update Application paths
# argocd/applications/base/infrastructure.yaml
spec:
  source:
    path: components/00-infrastructure  # Updated path
```

**Risk**: ⚠️ High - All Applications need path updates

**Mitigation**: Do in single PR, test thoroughly in dev first

#### Step 5: Implement Root App of Apps (Final)

```bash
# Create root app
kubectl apply -f argocd/bootstrap/root-app.yaml

# Delete manual Applications (now managed by root)
kubectl delete -f argocd/applications/kind-local/
```

**Risk**: ⚠️ High - Changes management model

**Mitigation**: Test in separate cluster first

### Recommended Migration Order

```
Week 1: ✅ Low Risk
  - Add sync waves
  - Create AppProjects
  - Test in kind-local

Week 2: ⚠️ Medium Risk
  - Create ApplicationSets (parallel to existing)
  - Test ApplicationSet generation
  - Validate in kind-local

Week 3: ⚠️ High Risk
  - Reorganize directory structure
  - Update all Application paths
  - Test in kind-local, then promote to stage

Week 4: 🎯 Final
  - Implement root app of apps
  - Migrate stage environment
  - Document new workflow

Week 5: 🎉 Production
  - Migrate prod environment
  - Train team on new structure
  - Update documentation
```

## Reference Examples

### Minimal Example: 4-App Structure

```
kagenti-demo-deployment/
├── components/
│   ├── 00-infrastructure/
│   ├── 01-platform/
│   ├── 02-observability/
│   └── 03-applications/
├── environments/
│   └── kind-local/
│       ├── 00-infrastructure/kustomization.yaml
│       ├── 01-platform/kustomization.yaml
│       ├── 02-observability/kustomization.yaml
│       └── 03-applications/kustomization.yaml
└── argocd/
    ├── projects/
    │   ├── infrastructure.yaml
    │   ├── platform.yaml
    │   ├── observability.yaml
    │   └── applications.yaml
    ├── applications/
    │   └── base/
    │       ├── infrastructure.yaml
    │       ├── platform.yaml
    │       ├── observability.yaml
    │       └── applications.yaml
    └── bootstrap/
        └── root-app.yaml
```

**Result**: 4 Applications, clear dependencies, simple to understand

### Advanced Example: ApplicationSets + Multi-Cluster

```yaml
# argocd/applicationsets/infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
spec:
  generators:
  - matrix:
      generators:
      # Generator 1: Git directories (environments)
      - git:
          repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
          revision: HEAD
          directories:
          - path: environments/*/00-infrastructure

      # Generator 2: Clusters
      - list:
          elements:
          - cluster: kind-local
            server: https://kubernetes.default.svc
            syncPolicy: automated
          - cluster: openshift-stage
            server: https://api.stage.example.com
            syncPolicy: automated
          - cluster: openshift-prod
            server: https://api.prod.example.com
            syncPolicy: manual  # Require manual approval

  template:
    metadata:
      name: 'infra-{{cluster}}-{{path.basename}}'
      annotations:
        argocd.argoproj.io/sync-wave: "0"
      labels:
        environment: '{{path.basename}}'
        cluster: '{{cluster}}'
    spec:
      project: infrastructure
      source:
        repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: '{{server}}'
        namespace: default
      syncPolicy:
        automated: '{{syncPolicy}}'
        syncOptions:
        - CreateNamespace=true
```

**Result**: Automatically creates apps for all environment+cluster combinations

## Glossary

- **Application**: Argo CD CRD representing a deployed app
- **ApplicationSet**: Argo CD CRD that generates multiple Applications from templates
- **App of Apps**: Pattern where one Application deploys other Applications
- **AppProject**: Argo CD CRD for isolation, RBAC, and organization
- **Sync Wave**: Annotation controlling Application deployment order
- **Kustomize Overlay**: Environment-specific configuration patches
- **Git Generator**: ApplicationSet generator that reads Git repository structure
- **List Generator**: ApplicationSet generator with hardcoded list of values
- **Matrix Generator**: Combines multiple generators (cartesian product)
- **Sync Policy**: Rules for when/how Argo CD syncs Applications
- **Health Check**: Logic determining if Application is healthy
- **Resource Hook**: Job that runs before/after sync

## Resources

### Official Documentation
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

### Best Practices Guides
- [Codefresh Argo CD Best Practices](https://codefresh.io/blog/argo-cd-best-practices/)
- [Structuring Argo CD Repositories](https://codefresh.io/blog/how-to-structure-your-argo-cd-repositories-using-application-sets/)
- [App of Apps vs ApplicationSets](https://bytegoblin.io/blog/argocd-deployment-patterns-app-of-apps-vs-applicationsets)

### Example Repositories
- [Argo CD App of Apps Example](https://github.com/hendrikmaus/argo-cd-app-of-apps)
- [Kustomize GitOps Example](https://github.com/hseligson1/kustomize-gitops-example)

---

**Last Updated**: 2025-11-07
**Maintained By**: Kagenti Platform Team
**Status**: Draft - Ready for Implementation
