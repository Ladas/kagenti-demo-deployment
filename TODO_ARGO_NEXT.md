# ArgoCD ApplicationSets Migration Plan

**Version**: 1.0
**Date**: 2025-11-10
**Status**: Planning Phase - Implementation Ready
**Goal**: Migrate from environment-specific ArgoCD Application overlays to scalable ApplicationSets

---

## Executive Summary

This plan migrates the ArgoCD deployment strategy from **manually patching Applications per environment** to **automatically generating Applications via ApplicationSets**. This reduces duplication, improves scalability, and makes adding new environments trivial.

**Current Approach** (Option A):
- Duplicate ArgoCD Application patches in `argocd/applications/kind-local/`, `argocd/applications/openshift-stage/`, `argocd/applications/openshift-prod/`
- Each environment manually patches Application `spec.source.path` to point to correct overlay
- Adding a new environment requires creating new patch file

**New Approach** (Option B):
- Single ApplicationSet definition per component in `argocd/appsets/`
- ApplicationSet automatically generates Applications for all environments
- Adding a new environment = adding one entry to ApplicationSet generator list

---

## What Are ApplicationSets?

**ApplicationSets** are a native ArgoCD feature that automatically generates multiple ArgoCD Applications from templates.

### Key Concepts

**Without ApplicationSets (Current)**:
```yaml
# argocd/applications/base/keycloak.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
spec:
  source:
    path: components/00-infrastructure/keycloak/base

# argocd/applications/kind-local/kustomization.yaml
patches:
  - target:
      name: keycloak
    patch: |-
      - op: replace
        path: /spec/source/path
        value: components/00-infrastructure/keycloak/overlays/kind-local

# argocd/applications/openshift-prod/kustomization.yaml
patches:
  - target:
      name: keycloak
    patch: |-
      - op: replace
        path: /spec/source/path
        value: components/00-infrastructure/keycloak/overlays/openshift-prod
```

**With ApplicationSets (New)**:
```yaml
# argocd/appsets/keycloak.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: keycloak
spec:
  generators:
    - list:
        elements:
          - env: kind-local
            overlay: kind-local
          - env: openshift-prod
            overlay: openshift-prod
  template:
    metadata:
      name: 'keycloak-{{env}}'
    spec:
      source:
        path: 'components/00-infrastructure/keycloak/overlays/{{overlay}}'
```

**Result**: ApplicationSet creates 2 Applications automatically:
- `keycloak-kind-local` → points to `overlays/kind-local`
- `keycloak-openshift-prod` → points to `overlays/openshift-prod`

---

## Benefits of ApplicationSets

| Aspect | Current (Manual Patches) | ApplicationSets |
|--------|-------------------------|-----------------|
| **Environment Addition** | Create new `argocd/applications/{env}/` directory with patches for ALL apps | Add one line to each ApplicationSet generator |
| **Application Duplication** | 3 files per app (base + 2 environment patches) | 1 file per app (ApplicationSet) |
| **Consistency** | Manual - prone to copy/paste errors | Automatic - guaranteed consistency |
| **Visibility** | Scattered across directories | Single source of truth per component |
| **Scalability** | Linear growth (1 patch file per app per env) | Constant (1 ApplicationSet per app) |
| **Multi-Cluster** | Complex - requires manual cluster configuration | Built-in - cluster generator support |

---

## Migration Plan: Option B Implementation

### Phase 1: Test with Keycloak Only

**Goal**: Prove ApplicationSets work for one component before migrating all components.

**Prerequisites**:
- [ ] ArgoCD ApplicationSet controller installed (should be enabled by default in ArgoCD 2.6+)
- [ ] Verify ApplicationSet CRD exists: `kubectl get crd applicationsets.argoproj.io`

**Tasks**:

#### Step 1.1: Create Keycloak Operator Infrastructure

Create operator installation methods in components:

```bash
mkdir -p components/00-infrastructure/keycloak/operator/upstream
mkdir -p components/00-infrastructure/keycloak/operator/olm
mkdir -p components/00-infrastructure/keycloak/overlays/kind-local
mkdir -p components/00-infrastructure/keycloak/overlays/openshift-stage
mkdir -p components/00-infrastructure/keycloak/overlays/openshift-prod
```

**Files to Create**:

1. **Upstream Operator (for Kind)**

`components/00-infrastructure/keycloak/operator/upstream/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: keycloak-operator

resources:
  # Install CRDs and operator from upstream
  - https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.7/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
  - https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.7/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
  - https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.7/kubernetes/kubernetes.yml

labels:
  - pairs:
      app.kubernetes.io/name: keycloak-operator
      app.kubernetes.io/component: operator
      app.kubernetes.io/managed-by: kustomize
      kagenti.dev/operator-method: upstream
    includeSelectors: true

commonAnnotations:
  description: "Upstream Keycloak Operator for Kubernetes"
```

2. **OLM Operator (for OpenShift)**

`components/00-infrastructure/keycloak/operator/olm/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: keycloak

resources:
  - operatorgroup.yaml
  - subscription.yaml

labels:
  - pairs:
      app.kubernetes.io/name: keycloak-operator
      app.kubernetes.io/component: operator
      app.kubernetes.io/managed-by: olm
      kagenti.dev/operator-method: olm
    includeSelectors: false

commonAnnotations:
  description: "Red Hat Keycloak Operator via OLM"
```

`components/00-infrastructure/keycloak/operator/olm/operatorgroup.yaml`:
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: keycloak-operators
  namespace: keycloak
spec:
  targetNamespaces:
    - keycloak
```

`components/00-infrastructure/keycloak/operator/olm/subscription.yaml`:
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhbk-operator
  namespace: keycloak
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  channel: stable-v22
  name: rhbk-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual  # Change to Automatic after first successful deployment
  startingCSV: rhbk-operator.v22.0.7  # Pin version for production
  config:
    env:
      - name: RELATED_IMAGE_KEYCLOAK
        value: registry.redhat.io/rhbk/keycloak-rhel9:22
```

3. **Reorganize Base Directory**

Move current files to base (if not already structured):

```bash
# Current structure (if files are at root of keycloak/)
# Move to base/
mv components/00-infrastructure/keycloak/*.yaml components/00-infrastructure/keycloak/base/ 2>/dev/null || true
```

`components/00-infrastructure/keycloak/base/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: keycloak

resources:
  - namespace.yaml
  - postgres-statefulset.yaml
  - db-secret-generation-job.yaml
  - keycloak-cr.yaml
  - realm-import-kubernetes.yaml
  - realm-import-kagenti.yaml
  - mtls-policy.yaml
  - httproute.yaml

labels:
  - pairs:
      app.kubernetes.io/name: keycloak
      app.kubernetes.io/part-of: kagenti
      app.kubernetes.io/component: authentication
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: false

commonAnnotations:
  config.kubernetes.io/origin: "components/00-infrastructure/keycloak/base"
  description: "Keycloak SSO - Shared application configuration (operator-agnostic)"
```

4. **Create Kind Overlay**

`components/00-infrastructure/keycloak/overlays/kind-local/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: keycloak

resources:
  - ../../operator/upstream       # 🎯 Use upstream operator for Kind
  - ../../base                     # Shared application config

commonLabels:
  kagenti.dev/environment: kind-local
  kagenti.dev/cluster-type: kind

patches:
  # Single replica for dev
  - patch: |-
      - op: replace
        path: /spec/instances
        value: 1
    target:
      kind: Keycloak
      name: keycloak

  # Dev hostname
  - patch: |-
      - op: replace
        path: /spec/hostname/hostname
        value: keycloak.localtest.me
    target:
      kind: Keycloak
      name: keycloak

  # Use embedded PostgreSQL (dev only)
  - patch: |-
      - op: replace
        path: /spec/db/host
        value: postgres
    target:
      kind: Keycloak
      name: keycloak

  # Lower resources for dev
  - patch: |-
      - op: replace
        path: /spec/resources/requests/cpu
        value: 250m
      - op: replace
        path: /spec/resources/requests/memory
        value: 512Mi
      - op: replace
        path: /spec/resources/limits/cpu
        value: 500m
      - op: replace
        path: /spec/resources/limits/memory
        value: 1Gi
    target:
      kind: Keycloak
      name: keycloak

images:
  # Use upstream image for Kind
  - name: quay.io/keycloak/keycloak
    newTag: 26.0.7

commonAnnotations:
  description: "Keycloak for Kind local development - upstream operator"
```

5. **Create OpenShift Stage Overlay**

`components/00-infrastructure/keycloak/overlays/openshift-stage/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: keycloak

resources:
  - ../../operator/olm            # 🎯 Use OLM operator for OpenShift
  - ../../base                     # Shared application config

commonLabels:
  kagenti.dev/environment: openshift-stage
  kagenti.dev/cluster-type: openshift

patches:
  # High availability (2 replicas for stage)
  - patch: |-
      - op: replace
        path: /spec/instances
        value: 2
    target:
      kind: Keycloak
      name: keycloak

  # Stage hostname
  - patch: |-
      - op: replace
        path: /spec/hostname/hostname
        value: keycloak.stage.example.com
    target:
      kind: Keycloak
      name: keycloak

  # External managed PostgreSQL
  - patch: |-
      - op: replace
        path: /spec/db/host
        value: postgres.database.svc.cluster.local
    target:
      kind: Keycloak
      name: keycloak

  # Production-level resources
  - patch: |-
      - op: replace
        path: /spec/resources/requests/cpu
        value: 500m
      - op: replace
        path: /spec/resources/requests/memory
        value: 1Gi
      - op: replace
        path: /spec/resources/limits/cpu
        value: 1000m
      - op: replace
        path: /spec/resources/limits/memory
        value: 2Gi
    target:
      kind: Keycloak
      name: keycloak

images:
  # Use Red Hat certified image
  - name: quay.io/keycloak/keycloak
    newName: registry.redhat.io/rhbk/keycloak-rhel9
    newTag: "22"

commonAnnotations:
  description: "Keycloak for OpenShift staging - OLM operator"
```

6. **Create OpenShift Prod Overlay**

`components/00-infrastructure/keycloak/overlays/openshift-prod/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: keycloak-prod

resources:
  - ../../operator/olm            # 🎯 Use OLM operator for OpenShift
  - ../../base                     # Shared application config
  - pdb.yaml                       # PodDisruptionBudget for prod

commonLabels:
  kagenti.dev/environment: openshift-prod
  kagenti.dev/cluster-type: openshift

patches:
  # High availability (3 replicas for prod)
  - patch: |-
      - op: replace
        path: /spec/instances
        value: 3
    target:
      kind: Keycloak
      name: keycloak

  # Production hostname
  - patch: |-
      - op: replace
        path: /spec/hostname/hostname
        value: keycloak.prod.example.com
    target:
      kind: Keycloak
      name: keycloak

  # External managed PostgreSQL (prod)
  - patch: |-
      - op: replace
        path: /spec/db/host
        value: postgres-ha.database.svc.cluster.local
    target:
      kind: Keycloak
      name: keycloak

  # Production resources (higher limits)
  - patch: |-
      - op: replace
        path: /spec/resources/requests/cpu
        value: 1000m
      - op: replace
        path: /spec/resources/requests/memory
        value: 2Gi
      - op: replace
        path: /spec/resources/limits/cpu
        value: 2000m
      - op: replace
        path: /spec/resources/limits/memory
        value: 4Gi
    target:
      kind: Keycloak
      name: keycloak

  # Enable monitoring
  - patch: |-
      - op: add
        path: /metadata/annotations/prometheus.io~1scrape
        value: "true"
      - op: add
        path: /metadata/annotations/prometheus.io~1port
        value: "8080"
    target:
      kind: Keycloak
      name: keycloak

images:
  # Use Red Hat certified image
  - name: quay.io/keycloak/keycloak
    newName: registry.redhat.io/rhbk/keycloak-rhel9
    newTag: "22"

commonAnnotations:
  description: "Keycloak for OpenShift production - OLM operator with HA"
```

`components/00-infrastructure/keycloak/overlays/openshift-prod/pdb.yaml`:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: keycloak-pdb
  namespace: keycloak-prod
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: keycloak
```

---

#### Step 1.2: Create Keycloak ApplicationSet

Create the ApplicationSet that will generate Applications for all environments:

`argocd/appsets/keycloak.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: keycloak
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
  labels:
    kagenti.dev/layer: infrastructure
    kagenti.dev/component: keycloak
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  # How to generate Applications
  generators:
    - list:
        elements:
          # Environment 1: Kind Local
          - env: kind-local
            cluster: in-cluster
            server: https://kubernetes.default.svc
            namespace: keycloak
            overlay: kind-local
            operatorMethod: upstream
            syncWave: "5"
            autoSync: "true"
            prune: "true"

          # Environment 2: OpenShift Stage
          - env: openshift-stage
            cluster: openshift-stage
            server: https://api.stage.openshift.com:6443
            namespace: keycloak
            overlay: openshift-stage
            operatorMethod: olm
            syncWave: "5"
            autoSync: "false"  # Manual sync for stage
            prune: "true"

          # Environment 3: OpenShift Prod
          - env: openshift-prod
            cluster: openshift-prod
            server: https://api.prod.openshift.com:6443
            namespace: keycloak-prod
            overlay: openshift-prod
            operatorMethod: olm
            syncWave: "5"
            autoSync: "false"  # Manual sync for prod
            prune: "false"     # No auto-prune in prod

  # Application template (used for all generated Applications)
  template:
    metadata:
      name: 'keycloak-{{env}}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '{{syncWave}}'
        notifications.argoproj.io/subscribe.on-sync-succeeded.slack: kagenti-deployments
      labels:
        kagenti.dev/layer: infrastructure
        kagenti.dev/component: keycloak
        kagenti.dev/environment: '{{env}}'
        kagenti.dev/cluster: '{{cluster}}'
        kagenti.dev/operator-method: '{{operatorMethod}}'
      finalizers:
        - resources-finalizer.argocd.argoproj.io

    spec:
      project: infrastructure  # Use infrastructure AppProject for RBAC

      source:
        repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
        targetRevision: main
        path: 'components/00-infrastructure/keycloak/overlays/{{overlay}}'

      destination:
        server: '{{server}}'
        namespace: '{{namespace}}'

      syncPolicy:
        automated:
          prune: '{{prune}}'
          selfHeal: '{{autoSync}}'
          allowEmpty: false
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
          - PrunePropagationPolicy=foreground
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m

      # Health checks
      ignoreDifferences:
        # OLM-managed resources (Subscription status updated by OLM)
        - group: operators.coreos.com
          kind: Subscription
          jsonPointers:
            - /status

        # InstallPlan created by OLM
        - group: operators.coreos.com
          kind: InstallPlan
          jsonPointers:
            - /status
```

**What This Does**:
- Creates 3 Applications: `keycloak-kind-local`, `keycloak-openshift-stage`, `keycloak-openshift-prod`
- Each Application points to its respective overlay in `components/00-infrastructure/keycloak/overlays/`
- Kind uses upstream operator, OpenShift uses OLM
- Stage and prod require manual sync (safer)

---

#### Step 1.3: Create AppProject for Infrastructure

Create an AppProject to manage RBAC and permissions:

`argocd/projects/infrastructure.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: argocd
spec:
  description: Infrastructure layer components (Keycloak, Istio, etc.)

  # Allowed Git repositories
  sourceRepos:
    - https://github.com/Ladas/kagenti-demo-deployment.git
    - https://github.com/keycloak/keycloak-k8s-resources.git

  # Allowed destination clusters
  destinations:
    - namespace: 'keycloak*'
      server: '*'
    - namespace: 'istio-system'
      server: '*'
    - namespace: 'cert-manager'
      server: '*'

  # Cluster resource permissions
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'

  # Namespace resource permissions
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'

  # Orphaned resource monitoring
  orphanedResources:
    warn: true
```

---

#### Step 1.4: Update Bootstrap to Deploy ApplicationSets

Create a new bootstrap structure that deploys ApplicationSets:

`argocd/bootstrap/kind/root-appset.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagenti-appsets-kind
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
    targetRevision: main
    path: argocd/appsets  # 🎯 Deploy all ApplicationSets

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**This replaces the current root-app.yaml approach.**

---

#### Step 1.5: Test Keycloak ApplicationSet

**Testing Procedure**:

1. **Verify Current State**:
```bash
# Check existing Keycloak deployment
kubectl get keycloak -n keycloak
kubectl get deployment -n keycloak

# Check ArgoCD Applications
argocd app list | grep keycloak
```

2. **Deploy AppProject**:
```bash
kubectl apply -f argocd/projects/infrastructure.yaml

# Verify
kubectl get appproject -n argocd infrastructure
```

3. **Deploy Keycloak ApplicationSet**:
```bash
kubectl apply -f argocd/appsets/keycloak.yaml

# Verify ApplicationSet created
kubectl get applicationset -n argocd keycloak

# Verify generated Applications
kubectl get application -n argocd | grep keycloak
# Should show: keycloak-kind-local, keycloak-openshift-stage, keycloak-openshift-prod
```

4. **Check Generated Applications**:
```bash
# View generated Application
kubectl get application keycloak-kind-local -n argocd -o yaml

# Verify path points to overlay
# Should see: path: components/00-infrastructure/keycloak/overlays/kind-local
```

5. **Sync Keycloak (Kind)**:
```bash
# Manual sync first time
argocd app sync keycloak-kind-local

# Monitor deployment
kubectl get pods -n keycloak -w

# Verify operator deployed
kubectl get deployment -n keycloak-operator keycloak-operator

# Verify Keycloak CR
kubectl get keycloak -n keycloak

# Verify realm imports
kubectl get keycloakrealmimport -n keycloak
```

6. **Validation**:
```bash
# Check Keycloak pods running
kubectl wait --for=condition=Ready pod -l app=keycloak -n keycloak --timeout=300s

# Test Keycloak endpoint
curl -k https://keycloak.localtest.me:9443/realms/kubernetes/.well-known/openid-configuration

# Verify OAuth2-Proxy can connect
kubectl logs -n oauth2-proxy -l app=kiali-oauth2-proxy | grep -i "keycloak"
```

**Success Criteria**:
- [ ] ApplicationSet creates 3 Applications (kind-local, openshift-stage, openshift-prod)
- [ ] `keycloak-kind-local` Application points to `overlays/kind-local`
- [ ] Upstream operator deployed to `keycloak-operator` namespace
- [ ] Keycloak CR deployed and healthy
- [ ] Realm imports successful
- [ ] OAuth2-Proxy can authenticate against Keycloak

---

### Phase 2: Migrate Remaining OLM-Capable Components

**Goal**: Apply ApplicationSet pattern to all components that have OLM operators available.

**Components to Migrate** (from TODO_ARGO_CLEANUP.md):

| Component | Upstream Operator | Red Hat OLM Operator | Priority |
|-----------|-------------------|----------------------|----------|
| **Istio** | Helm (istio/istio) | Sail Operator (Service Mesh 3.0) | HIGH |
| **Tekton** | Kustomize YAML | OpenShift Pipelines Operator | MEDIUM |
| **cert-manager** | Kustomize YAML | cert-manager Operator for OpenShift | MEDIUM |
| **Kiali** | Helm (kiali/kiali-server) | Kiali Operator (bundled with Service Mesh) | MEDIUM |

#### Step 2.1: Istio ApplicationSet

**Directory Structure**:
```
components/00-infrastructure/istio/
├── base/
│   ├── istio-config.yaml          # Shared: AuthorizationPolicy, PeerAuthentication
│   ├── mtls-strict.yaml
│   └── request-authentication.yaml
├── operator/
│   ├── helm/                      # Kind: Upstream Helm charts
│   │   ├── istio-base/
│   │   └── istiod/
│   └── sail/                      # OpenShift: Sail Operator
│       ├── subscription.yaml
│       └── istio-cr.yaml
└── overlays/
    ├── kind-local/                # Uses operator/helm
    ├── openshift-stage/           # Uses operator/sail
    └── openshift-prod/            # Uses operator/sail
```

**ApplicationSet**:
`argocd/appsets/istio.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: istio
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: kind-local
            overlay: kind-local
            operatorMethod: helm
          - env: openshift-stage
            overlay: openshift-stage
            operatorMethod: sail
          - env: openshift-prod
            overlay: openshift-prod
            operatorMethod: sail
  template:
    metadata:
      name: 'istio-{{env}}'
    spec:
      source:
        path: 'components/00-infrastructure/istio/overlays/{{overlay}}'
      # ... rest of template
```

---

#### Step 2.2: Tekton ApplicationSet

**Directory Structure**:
```
components/00-infrastructure/tekton/
├── base/
│   ├── pipelines/                 # Shared pipeline definitions
│   └── tasks/                     # Shared task definitions
├── operator/
│   ├── upstream/                  # Kind: Upstream Tekton YAML
│   │   └── release.yaml
│   └── olm/                       # OpenShift: OpenShift Pipelines Operator
│       └── subscription.yaml
└── overlays/
    ├── kind-local/
    ├── openshift-stage/
    └── openshift-prod/
```

**ApplicationSet**:
`argocd/appsets/tekton.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tekton
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: kind-local
            overlay: kind-local
            operatorMethod: upstream
          - env: openshift-stage
            overlay: openshift-stage
            operatorMethod: olm
          - env: openshift-prod
            overlay: openshift-prod
            operatorMethod: olm
  template:
    metadata:
      name: 'tekton-{{env}}'
    spec:
      source:
        path: 'components/00-infrastructure/tekton/overlays/{{overlay}}'
      # ... rest of template
```

---

#### Step 2.3: cert-manager ApplicationSet

**Directory Structure**:
```
components/00-infrastructure/cert-manager/
├── base/
│   ├── issuers/                   # Shared: ClusterIssuer definitions
│   └── certificates/              # Shared: Certificate CRs
├── operator/
│   ├── upstream/                  # Kind: Upstream cert-manager
│   │   └── cert-manager.yaml
│   └── olm/                       # OpenShift: cert-manager Operator
│       └── subscription.yaml
└── overlays/
    ├── kind-local/
    ├── openshift-stage/
    └── openshift-prod/
```

**ApplicationSet**:
`argocd/appsets/cert-manager.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cert-manager
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: kind-local
            overlay: kind-local
            operatorMethod: upstream
          - env: openshift-stage
            overlay: openshift-stage
            operatorMethod: olm
          - env: openshift-prod
            overlay: openshift-prod
            operatorMethod: olm
  template:
    metadata:
      name: 'cert-manager-{{env}}'
    spec:
      source:
        path: 'components/00-infrastructure/cert-manager/overlays/{{overlay}}'
      # ... rest of template
```

---

#### Step 2.4: Kiali ApplicationSet

**Directory Structure**:
```
components/02-observability/kiali/
├── base/
│   └── kiali-cr.yaml              # Shared: Kiali CR configuration
├── operator/
│   ├── helm/                      # Kind: Kiali Helm chart
│   │   └── values.yaml
│   └── olm/                       # OpenShift: Kiali Operator
│       └── subscription.yaml
└── overlays/
    ├── kind-local/
    ├── openshift-stage/
    └── openshift-prod/
```

**ApplicationSet**:
`argocd/appsets/kiali.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kiali
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: kind-local
            overlay: kind-local
            operatorMethod: helm
          - env: openshift-stage
            overlay: openshift-stage
            operatorMethod: olm
          - env: openshift-prod
            overlay: openshift-prod
            operatorMethod: olm
  template:
    metadata:
      name: 'kiali-{{env}}'
    spec:
      source:
        path: 'components/02-observability/kiali/overlays/{{overlay}}'
      # ... rest of template
```

---

### Phase 3: Migrate All Remaining Components

**Goal**: Apply ApplicationSet pattern to all components (even those without OLM).

**Components Without OLM** (still benefit from ApplicationSets for multi-environment):

| Component | Deployment Method | Environments |
|-----------|-------------------|--------------|
| **Grafana** | Kustomize | kind-local, openshift-stage, openshift-prod |
| **Tempo** | Kustomize | kind-local, openshift-stage, openshift-prod |
| **Phoenix** | Kustomize | kind-local, openshift-stage, openshift-prod |
| **OAuth2-Proxy** | Kustomize | kind-local, openshift-stage, openshift-prod |
| **SPIRE** | Helm | kind-local, openshift-stage, openshift-prod |
| **Kagenti UI** | Kustomize | kind-local, openshift-stage, openshift-prod |
| **Kagenti Operators** | Helm | kind-local, openshift-stage, openshift-prod |

**Example: Grafana ApplicationSet**

`argocd/appsets/grafana.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: grafana
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: kind-local
            overlay: kind-local
            replicas: 1
            storage: emptyDir
          - env: openshift-stage
            overlay: openshift-stage
            replicas: 2
            storage: pvc
          - env: openshift-prod
            overlay: openshift-prod
            replicas: 3
            storage: pvc
  template:
    metadata:
      name: 'grafana-{{env}}'
    spec:
      source:
        path: 'components/02-observability/grafana/overlays/{{overlay}}'
      # ... rest of template
```

**Tasks**:
- [ ] Create overlays for each component in `components/`
- [ ] Create ApplicationSet for each component in `argocd/appsets/`
- [ ] Test each ApplicationSet individually
- [ ] Update bootstrap to deploy all ApplicationSets

---

## Migration Checklist

### Prerequisites

- [ ] ArgoCD ApplicationSet controller enabled
- [ ] Verify ApplicationSet CRD: `kubectl get crd applicationsets.argoproj.io`
- [ ] Create backup of current ArgoCD Applications: `kubectl get applications -n argocd -o yaml > backup-applications.yaml`
- [ ] Review ApplicationSet documentation: https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/

### Phase 1: Keycloak (Test Case)

- [ ] Create `components/00-infrastructure/keycloak/operator/upstream/`
- [ ] Create `components/00-infrastructure/keycloak/operator/olm/`
- [ ] Create `components/00-infrastructure/keycloak/overlays/kind-local/`
- [ ] Create `components/00-infrastructure/keycloak/overlays/openshift-stage/`
- [ ] Create `components/00-infrastructure/keycloak/overlays/openshift-prod/`
- [ ] Create `argocd/appsets/keycloak.yaml`
- [ ] Create `argocd/projects/infrastructure.yaml`
- [ ] Test ApplicationSet: `kubectl apply -f argocd/appsets/keycloak.yaml`
- [ ] Verify Applications created: `kubectl get applications -n argocd | grep keycloak`
- [ ] Sync `keycloak-kind-local` Application
- [ ] Verify Keycloak deployed and healthy
- [ ] Verify OAuth2-Proxy can connect to Keycloak
- [ ] Document learnings and issues

### Phase 2: OLM-Capable Components

**For each component (Istio, Tekton, cert-manager, Kiali)**:
- [ ] Create `components/.../operator/upstream/` (or helm/)
- [ ] Create `components/.../operator/olm/`
- [ ] Create `components/.../overlays/{kind-local,openshift-stage,openshift-prod}/`
- [ ] Create `argocd/appsets/{component}.yaml`
- [ ] Test ApplicationSet deployment
- [ ] Verify component deployed correctly in each environment

### Phase 3: All Remaining Components

**For each component (Grafana, Tempo, Phoenix, OAuth2-Proxy, etc.)**:
- [ ] Create `components/.../overlays/{kind-local,openshift-stage,openshift-prod}/`
- [ ] Create `argocd/appsets/{component}.yaml`
- [ ] Test ApplicationSet deployment
- [ ] Verify component deployed correctly

### Cleanup

- [ ] Remove `argocd/applications/base/` (replaced by ApplicationSets)
- [ ] Remove `argocd/applications/kind-local/` (no longer needed)
- [ ] Remove `argocd/applications/openshift-prod/` (no longer needed)
- [ ] Update `argocd/bootstrap/kind/root-app.yaml` to deploy `argocd/appsets/`
- [ ] Update documentation in `README.md`, `DEPLOYMENT.md`
- [ ] Create `docs/applicationsets-guide.md`

---

## Final Structure

After migration, the repository structure will be:

```
kagenti-demo-deployment/
│
├── components/                                   # Kubernetes manifests
│   ├── 00-infrastructure/
│   │   ├── keycloak/
│   │   │   ├── base/                            # Shared config
│   │   │   ├── operator/
│   │   │   │   ├── upstream/                   # Kind deployment
│   │   │   │   └── olm/                        # OpenShift deployment
│   │   │   └── overlays/
│   │   │       ├── kind-local/
│   │   │       ├── openshift-stage/
│   │   │       └── openshift-prod/
│   │   │
│   │   ├── istio/                               # Same pattern
│   │   ├── tekton/                              # Same pattern
│   │   ├── cert-manager/                        # Same pattern
│   │   └── ...
│   │
│   ├── 01-platform/
│   │   ├── kagenti-ui/
│   │   │   ├── base/
│   │   │   └── overlays/
│   │   └── ...
│   │
│   ├── 02-observability/
│   │   ├── grafana/
│   │   │   ├── base/
│   │   │   └── overlays/
│   │   ├── kiali/                               # OLM-capable
│   │   └── ...
│   │
│   └── 03-applications/
│       └── agents/
│           ├── base/
│           └── overlays/
│
└── argocd/
    ├── appsets/                                 # 🎯 ApplicationSets (1 per component)
    │   ├── keycloak.yaml
    │   ├── istio.yaml
    │   ├── tekton.yaml
    │   ├── cert-manager.yaml
    │   ├── kiali.yaml
    │   ├── grafana.yaml
    │   ├── tempo.yaml
    │   ├── phoenix.yaml
    │   ├── oauth2-proxy.yaml
    │   ├── spire.yaml
    │   ├── kagenti-ui.yaml
    │   ├── kagenti-operator.yaml
    │   └── agents.yaml
    │
    ├── projects/                                # AppProjects for RBAC
    │   ├── infrastructure.yaml
    │   ├── platform.yaml
    │   ├── observability.yaml
    │   └── applications.yaml
    │
    └── bootstrap/
        ├── kind/
        │   └── root-appset.yaml                # Deploys argocd/appsets/
        ├── openshift-stage/
        │   └── root-appset.yaml
        └── openshift-prod/
            └── root-appset.yaml
```

---

## Benefits Realized

### Before (Manual Application Patches)

**Adding a new environment** (e.g., `k3s-local`):
1. Create `argocd/applications/k3s-local/kustomization.yaml`
2. Copy all patches from `kind-local/`
3. Manually update 18+ Application patches
4. Test each Application individually
5. Fix copy/paste errors
6. Repeat for every component

**Total effort**: 4-6 hours, error-prone

### After (ApplicationSets)

**Adding a new environment** (e.g., `k3s-local`):
1. Create overlays in `components/` for each component
2. Add one entry to each ApplicationSet generator:
   ```yaml
   - env: k3s-local
     overlay: k3s-local
     server: https://kubernetes.default.svc
   ```
3. ApplicationSets automatically create all Applications
4. Test bootstrap deployment

**Total effort**: 1-2 hours, automated, no copy/paste

---

## Rollback Plan

If ApplicationSets cause issues, rollback is simple:

1. **Delete ApplicationSets**:
```bash
kubectl delete applicationset -n argocd --all
```

2. **Restore Manual Applications**:
```bash
kubectl apply -f backup-applications.yaml
```

3. **Re-deploy old bootstrap**:
```bash
kubectl apply -f argocd/bootstrap/kind/root-app.yaml
```

**All components will continue working** - only the ArgoCD deployment method changes, not the underlying Kubernetes manifests.

---

## Testing Strategy

### Unit Testing (Per ApplicationSet)

For each ApplicationSet:
```bash
# 1. Verify ApplicationSet syntax
kubectl apply --dry-run=client -f argocd/appsets/keycloak.yaml

# 2. Deploy ApplicationSet
kubectl apply -f argocd/appsets/keycloak.yaml

# 3. Verify Applications generated
kubectl get applications -n argocd | grep keycloak

# 4. Check Application paths
kubectl get application keycloak-kind-local -n argocd -o jsonpath='{.spec.source.path}'
# Expected: components/00-infrastructure/keycloak/overlays/kind-local

# 5. Sync one Application
argocd app sync keycloak-kind-local

# 6. Verify deployment
kubectl get all -n keycloak
```

### Integration Testing (Full Stack)

Test complete platform deployment:
```bash
# 1. Delete all existing Applications
kubectl delete applications -n argocd --all

# 2. Deploy all ApplicationSets
kubectl apply -f argocd/appsets/

# 3. Wait for ApplicationSets to generate Applications
sleep 10

# 4. Verify all Applications created
kubectl get applications -n argocd

# 5. Sync infrastructure layer
argocd app sync -l kagenti.dev/layer=infrastructure

# 6. Wait for infrastructure ready
kubectl wait --for=condition=Ready pod -l kagenti.dev/layer=infrastructure --all-namespaces --timeout=600s

# 7. Sync platform layer
argocd app sync -l kagenti.dev/layer=platform

# 8. Sync observability layer
argocd app sync -l kagenti.dev/layer=observability

# 9. Verify all services accessible
curl -k https://keycloak.localtest.me:9443
curl -k https://grafana.localtest.me:9443
curl -k https://kiali.localtest.me:9443
```

---

## Documentation Updates

### New Documents to Create

1. **`docs/applicationsets-guide.md`**
   - What are ApplicationSets
   - How to add new environment
   - How to add new component
   - Troubleshooting guide

2. **`docs/multi-environment-deployment.md`**
   - Environment strategy (Kind, OpenShift Stage, OpenShift Prod)
   - Overlay pattern explanation
   - Component structure standards

### Documents to Update

1. **`README.md`**
   - Update deployment section to reference ApplicationSets
   - Update architecture diagrams
   - Add ApplicationSet examples

2. **`DEPLOYMENT.md`**
   - Update bootstrap procedure
   - Reference ApplicationSets instead of manual Applications
   - Add multi-cluster deployment guide

3. **`TODO_ARGO_CLEANUP.md`**
   - Mark Phase 2-3 as completed (if using ApplicationSets)
   - Update with ApplicationSet implementation status

---

## Success Criteria

### Phase 1 Complete When:
- [ ] Keycloak ApplicationSet deployed
- [ ] 3 Applications generated (kind-local, openshift-stage, openshift-prod)
- [ ] `keycloak-kind-local` deploys upstream operator successfully
- [ ] Keycloak accessible and OAuth2-Proxy working
- [ ] Zero manual Application patches needed
- [ ] Documentation created

### Phase 2 Complete When:
- [ ] Istio, Tekton, cert-manager, Kiali ApplicationSets deployed
- [ ] All OLM-capable components use operator pattern
- [ ] OpenShift environments use OLM operators
- [ ] Kind environment uses upstream/Helm operators
- [ ] All components healthy in all environments

### Phase 3 Complete When:
- [ ] All components migrated to ApplicationSets
- [ ] Old `argocd/applications/base/`, `kind-local/`, `openshift-prod/` removed
- [ ] Bootstrap updated to deploy ApplicationSets
- [ ] Documentation complete
- [ ] Full platform deployment tested in all environments

---

## Timeline Estimate

| Phase | Duration | Complexity | Blockers |
|-------|----------|------------|----------|
| **Phase 1: Keycloak** | 1 day | Medium | Requires cluster access, OLM testing |
| **Phase 2: OLM Components** | 2-3 days | Medium-High | Requires OpenShift cluster access |
| **Phase 3: All Components** | 3-4 days | Medium | Requires multi-environment testing |
| **Documentation** | 1 day | Low | None |

**Total Estimated Time**: 7-9 days

---

## References

### ApplicationSet Documentation
- Official Docs: https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/
- Generators: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/
- Template Fields: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Template/

### OLM Documentation
- See `docs/OLM_ARGOCD_COMPARISON.md`
- See `docs/OLM_CONFIGURATION_REALITY.md`

### Related Documents
- `TODO_ARGO_CLEANUP.md` - Original cleanup plan
- `README.md` - Main repository documentation
- `DEPLOYMENT.md` - Deployment procedures

---

**IMPORTANT**: Start with Phase 1 (Keycloak only) to validate the ApplicationSet pattern before migrating all components. Do NOT migrate everything at once.

**Next Steps**:
1. Review this plan
2. Create `argocd/appsets/` directory
3. Begin Phase 1: Keycloak ApplicationSet implementation
4. Test thoroughly before proceeding to Phase 2

---

**Last Updated**: 2025-11-10
**Author**: Platform Engineering Team
**Status**: Ready for Implementation
