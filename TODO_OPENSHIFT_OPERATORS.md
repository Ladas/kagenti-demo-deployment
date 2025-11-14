# TODO: OpenShift Operator Strategy for Production Deployment

**Version**: 1.0
**Last Updated**: 2025-01-15
**Status**: Research Complete - Ready for Implementation

## Table of Contents

- [Executive Summary](#executive-summary)
- [OpenShift Operator Availability](#openshift-operator-availability)
- [Deployment Strategy](#deployment-strategy)
- [Current Repository State](#current-repository-state)
- [Gap Analysis](#gap-analysis)
- [Implementation Roadmap](#implementation-roadmap)
- [References](#references)

## Executive Summary

This document defines the operator deployment strategy for **production-grade** Kagenti platform deployment on both **Kind (dev)** and **OpenShift (stage/prod)** environments using a unified GitOps approach.

**Key Decisions**:
1. ✅ **Kind**: Use upstream operators (Istio, Tekton, cert-manager) via Helm/YAML
2. ✅ **OpenShift**: Use Red Hat certified operators from OperatorHub when available
3. ✅ **Unified GitOps**: Single repository with environment-specific overlays
4. ✅ **ArgoCD App-of-Apps**: Manual sync with sync waves for deployment ordering

**Current State** (as of 2025-01-15):
- Repository structure follows 2025 best practices (layered: 00-infrastructure, 01-platform, 02-observability, 03-applications)
- ArgoCD GitOps deployment working for Kind
- OpenShift environments partially configured (stage/prod directories exist)
- Missing: OpenShift-specific operator configurations

---

## OpenShift Operator Availability

### Certified Red Hat Operators (Available in OperatorHub)

Based on research ([Red Hat Documentation](https://docs.redhat.com/), [OperatorHub.io](https://operatorhub.io/)), the following operators are available for OpenShift:

#### 1. **OpenShift Pipelines (Tekton)** ✅ Available

| Aspect | Details |
|--------|---------|
| **Operator Name** | Red Hat OpenShift Pipelines |
| **Based On** | Tekton Pipelines (upstream) |
| **Current Version** | Based on Tekton v0.50+ |
| **Installation Method** | OperatorHub (OLM-based) |
| **Namespace** | `openshift-pipelines` (cluster-scoped) |
| **Differences from Upstream** | Enterprise hardening, security patches, Red Hat support |
| **Support** | Included with OpenShift subscription |
| **Documentation** | [OpenShift Pipelines Docs](https://docs.openshift.com/container-platform/latest/cicd/pipelines/understanding-openshift-pipelines.html) |

**Capabilities**:
- Tekton Pipelines, Triggers, Chains, Results
- Kubernetes-native CI/CD
- Integrated with OpenShift Console
- RBAC and multi-tenancy support

**Installation** (OpenShift Console):
```
Operators → OperatorHub → Search "OpenShift Pipelines" → Install
```

**Installation** (CLI):
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

#### 2. **cert-manager Operator** ✅ Available (GA as of April 2025)

| Aspect | Details |
|--------|---------|
| **Operator Name** | cert-manager Operator for Red Hat OpenShift |
| **Based On** | cert-manager v1.16.5 (upstream) |
| **Current Version** | 1.16.2 (operator) |
| **Installation Method** | OperatorHub (OLM-based) |
| **Namespace** | `cert-manager-operator` (cluster-scoped) |
| **Differences from Upstream** | Red Hat branding, support, OpenShift-specific configurations |
| **Support** | Included with OpenShift subscription (GA) |
| **Documentation** | [cert-manager for OpenShift Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift) |

**Capabilities**:
- TLS certificate management
- Integration with Istio-CSR (Technology Preview)
- OpenShift Service Mesh integration
- Automatic certificate renewal

**Installation** (OpenShift Console):
```
Operators → OperatorHub → Search "cert-manager" → Install
```

**Installation** (CLI):
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  channel: stable-v1
  name: openshift-cert-manager-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

#### 3. **OpenShift Service Mesh (Istio)** ✅ Available

| Aspect | Details |
|--------|---------|
| **Operator Name** | Red Hat OpenShift Service Mesh |
| **Based On** | Istio (upstream) via Maistra |
| **Current Version** | Service Mesh 2.x (Maistra-based) |
| **New Version** | Service Mesh 3.0 (upstream Istio via Sail Operator) - GA Q1 2025 |
| **Installation Method** | OperatorHub (OLM-based) |
| **Namespace** | `openshift-operators` (cluster-scoped) |
| **Key Differences** | Multi-tenancy, ServiceMeshControlPlane CRD, opt-in sidecar injection |
| **Support** | Included with OpenShift subscription |
| **Documentation** | [OpenShift Service Mesh Docs](https://docs.openshift.com/container-platform/latest/service_mesh/v2x/ossm-about.html) |

**Important Changes for 2025**:
- **Service Mesh 2.x**: Based on Maistra (Istio fork) with multi-tenant operator
- **Service Mesh 3.0 (NEW)**: Uses **Sail Operator** for pure upstream Istio
  - Faster release cadence (3x/year, within weeks of upstream release)
  - Single `Istio` CRD instead of `ServiceMeshControlPlane`
  - Uses upstream Istio Helm values
  - No more Maistra-specific resources
  - **GA targeted for Q1 2025** ([Red Hat Blog](https://www.redhat.com/en/blog/red-hat-openshift-service-mesh-3-frequently-asked-questions))

**Migration Path**:
- For new deployments: Use Service Mesh 3.0 (Sail Operator) when GA
- For existing: Service Mesh 2.x is supported, migration guide available

**Installation (Service Mesh 2.x)**:
```yaml
# 1. Install Elasticsearch Operator (for tracing)
# 2. Install Jaeger Operator
# 3. Install Kiali Operator
# 4. Install Service Mesh Operator

apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

**Installation (Service Mesh 3.0 - Sail Operator)**:
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: sailoperator
  namespace: openshift-operators
spec:
  channel: stable
  name: sailoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

#### 4. **Kiali Operator** ✅ Available

| Aspect | Details |
|--------|---------|
| **Operator Name** | Kiali Operator |
| **Installation Method** | Bundled with OpenShift Service Mesh |
| **Standalone** | Also available separately in OperatorHub |
| **Documentation** | [Kiali Docs](https://kiali.io/docs/) |

**Note**: When using OpenShift Service Mesh, Kiali is automatically installed and managed.

### Operators NOT Available as Certified Red Hat Operators

These operators must be deployed using upstream Helm/YAML manifests on OpenShift:

#### 1. **Kagenti Platform Operator** ❌ Not in OperatorHub

- **Status**: Community operator (not Red Hat certified)
- **Deployment Method**:
  - **Kind**: Helm chart from GitHub
  - **OpenShift**: Helm chart from GitHub (same as Kind)
- **Repository**: https://github.com/kagenti/kagenti-operator/tree/main/charts/platform-operator

#### 2. **Kagenti Agent Operator** ❌ Not in OperatorHub

- **Status**: Community operator (not Red Hat certified)
- **Deployment Method**:
  - **Kind**: Helm chart from GitHub
  - **OpenShift**: Helm chart from GitHub (same as Kind)
- **Repository**: https://github.com/kagenti/kagenti-operator/tree/main/charts/kagenti-operator

---

## Deployment Strategy

### Unified GitOps Approach

Use **environment-specific overlays** in a single repository to handle both Kind and OpenShift deployments:

```
components/
├── 00-infrastructure/
│   ├── istio/                      # Base Istio config (used by Kind)
│   ├── tekton/                     # Base Tekton config (used by Kind)
│   ├── cert-manager/               # Base cert-manager config (used by Kind)
│   ├── openshift-service-mesh/     # OpenShift Service Mesh (used by OpenShift)
│   ├── openshift-pipelines/        # OpenShift Pipelines (used by OpenShift)
│   └── openshift-cert-manager/     # cert-manager for OpenShift
│
├── 01-platform/
│   ├── kagenti-operator/           # Helm chart (both Kind and OpenShift)
│   └── platform-operator/          # Helm chart (both Kind and OpenShift)
│
environments/
├── kind-local/
│   └── kustomization.yaml          # References upstream operators
│
├── openshift-stage/
│   └── kustomization.yaml          # References OpenShift operators
│
└── openshift-prod/
    └── kustomization.yaml          # References OpenShift operators
```

### Operator Selection Matrix

| Operator | Kind (Dev) | OpenShift Stage | OpenShift Prod | Reason |
|----------|------------|-----------------|----------------|--------|
| **Istio** | Upstream Helm | OpenShift Service Mesh 3 (Sail) | OpenShift Service Mesh 3 (Sail) | Red Hat support, multi-tenancy |
| **Tekton** | Upstream YAML | OpenShift Pipelines Operator | OpenShift Pipelines Operator | Red Hat support, Console integration |
| **cert-manager** | Upstream YAML | cert-manager for OpenShift | cert-manager for OpenShift | Red Hat support, GA since April 2025 |
| **Kiali** | Upstream YAML | Bundled with Service Mesh | Bundled with Service Mesh | Automatic installation |
| **Kagenti Platform Op** | Helm (GitHub) | Helm (GitHub) | Helm (GitHub) | No OpenShift certified operator |
| **Kagenti Agent Op** | Helm (GitHub) | Helm (GitHub) | Helm (GitHub) | No OpenShift certified operator |

### Why Use OpenShift Operators in Production?

✅ **Enterprise Support**: Included with Red Hat OpenShift subscription
✅ **Security Updates**: CVE patches delivered faster than upstream
✅ **Integrated with OpenShift Console**: Web UI for operator lifecycle management
✅ **OLM (Operator Lifecycle Manager)**: Automatic updates, dependency resolution
✅ **Compliance**: Meets enterprise security/compliance requirements
✅ **Stability**: Tested and certified on specific OpenShift versions

---

## Current Repository State

### ✅ What's Working

1. **Directory Structure**: Follows 2025 best practices
   ```
   components/
   ├── 00-infrastructure/    ✅ Layered structure
   ├── 01-platform/          ✅ Operators separate from apps
   ├── 02-observability/     ✅ Observability stack
   └── 03-applications/      ✅ AI agents

   environments/
   ├── kind-local/           ✅ Kind-specific overlays
   ├── k3s-local/            ✅ K3s-specific overlays
   ├── openshift-stage/      ⚠️ Partial configuration
   └── openshift-prod/       ⚠️ Partial configuration

   argocd/
   ├── applications/
   │   ├── base/00-infrastructure/   ✅ Infrastructure apps
   │   ├── helm/                     ✅ Helm-based apps
   │   ├── kind-local/               ✅ Kind overlays
   │   └── openshift-prod/           ⚠️ Partial overlays
   └── bootstrap/kind/               ✅ Root app-of-apps
   ```

2. **ArgoCD GitOps**: Working for Kind
   - App-of-Apps pattern implemented
   - Manual sync with sync waves (wave 0, 10, 20, 30)
   - Automated sync for child apps

3. **Operator Deployment**: Both operators deployed via ArgoCD Helm apps
   - Platform Operator: version 0.2.0-alpha.15
   - Agent Operator: latest tag from ghcr.io

### ⚠️ What's Missing for OpenShift

1. **OpenShift Operator Subscriptions**: No OLM Subscription manifests for:
   - OpenShift Pipelines Operator
   - cert-manager for OpenShift
   - OpenShift Service Mesh 3 (Sail Operator)

2. **OpenShift-Specific Configurations**:
   - ServiceMeshControlPlane CR (if using Service Mesh 2.x)
   - Istio CR (if using Service Mesh 3.0 Sail Operator)
   - OpenShift Routes instead of/alongside HTTPRoutes

3. **Environment Separation**:
   - OpenShift environments reference Kind operator configurations
   - Need separate OpenShift operator paths

4. **ArgoCD ApplicationSets**:
   - Not using ApplicationSets for multi-environment automation
   - All apps manually defined (no auto-discovery)

---

## Gap Analysis

### Gap 1: OpenShift Operator Deployment Method

**Current**: All environments use upstream Helm/YAML operators
**Target**: OpenShift uses OLM-based certified operators

**Impact**: Missing enterprise support and OpenShift Console integration

**Fix**: Create OpenShift-specific operator Subscriptions

### Gap 2: Service Mesh Version Mismatch

**Current**: Repository configured for upstream Istio
**Target**: OpenShift should use Service Mesh 3.0 (Sail Operator) when GA

**Impact**: Can't use OpenShift Service Mesh features (multi-tenancy, Console UI)

**Fix**: Add Service Mesh 3.0 Istio CR configuration for OpenShift environments

### Gap 3: Missing Argo CD ApplicationSets

**Current**: Manual Application CRs for each app
**Target**: ApplicationSets for automatic multi-environment deployment

**Impact**: Manual overhead for adding new environments, no DRY principle

**Fix**: Implement ApplicationSets as per TODO_ARGO_CD_STRUCTURE.md recommendations

### Gap 4: Incomplete OpenShift Environment Overlays

**Current**: openshift-stage and openshift-prod directories partially configured
**Target**: Complete Kustomize overlays with OpenShift-specific patches

**Impact**: Can't deploy to OpenShift environments

**Fix**: Complete OpenShift overlay configurations

---

## Implementation Roadmap

### Phase 1: OpenShift Operator Configurations (Week 1)

#### 1.1. Create OpenShift Operator Subscriptions

**Tasks**:
- [ ] Create `components/00-infrastructure/openshift-pipelines/` directory
- [ ] Add Subscription CR for OpenShift Pipelines Operator
- [ ] Create `components/00-infrastructure/openshift-cert-manager/` directory
- [ ] Add Subscription CR for cert-manager Operator
- [ ] Create `components/00-infrastructure/openshift-service-mesh/` directory
- [ ] Add Subscription CR for Sail Operator (Service Mesh 3.0)

**Example Subscription**:
```yaml
# components/00-infrastructure/openshift-pipelines/subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

#### 1.2. Create Service Mesh 3.0 Configuration

**Tasks**:
- [ ] Create Istio CR for Sail Operator
- [ ] Configure service mesh for Kagenti workloads
- [ ] Set up multi-tenancy if needed

**Example Istio CR**:
```yaml
# components/00-infrastructure/openshift-service-mesh/istio-controlplane.yaml
apiVersion: operator.istio.io/v1alpha1
kind: Istio
metadata:
  name: default
spec:
  version: v1.22.0  # Latest Istio version
  namespace: istio-system
  updateStrategy:
    type: InPlace
  values:
    global:
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
    meshConfig:
      accessLogFile: /dev/stdout
      enableTracing: true
      defaultConfig:
        tracing:
          zipkin:
            address: jaeger-collector.istio-system:9411
```

### Phase 2: Environment-Specific Kustomize Overlays (Week 2)

#### 2.1. Complete openshift-stage Overlay

**Tasks**:
- [ ] Update `environments/openshift-stage/kustomization.yaml`
- [ ] Reference OpenShift operator components
- [ ] Add OpenShift-specific patches (Routes, SCCs, etc.)
- [ ] Configure resource quotas and limits

**Example kustomization.yaml**:
```yaml
# environments/openshift-stage/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # OpenShift Operators (OLM-based)
  - ../../components/00-infrastructure/openshift-pipelines
  - ../../components/00-infrastructure/openshift-cert-manager
  - ../../components/00-infrastructure/openshift-service-mesh

  # Kagenti Operators (Helm-based, same as Kind)
  - ../../components/01-platform/kagenti-operator
  - ../../components/01-platform/platform-operator

  # Platform services
  - ../../components/01-platform/kagenti-ui
  - ../../components/01-platform/keycloak

  # Observability
  - ../../components/02-observability/grafana
  - ../../components/02-observability/kiali  # Skip if bundled with Service Mesh

  # Agents
  - ../../components/03-applications/agents

patches:
  # OpenShift-specific patches
  - path: patches/grafana-route.yaml
  - path: patches/grafana-openshift-scc.yaml
  - path: patches/kagenti-ui-route.yaml

namespace: kagenti-system

commonLabels:
  environment: stage
  cluster: openshift-stage
```

#### 2.2. Complete openshift-prod Overlay

Same as stage but with production-specific configurations:
- Higher replica counts
- Stricter resource limits
- PodDisruptionBudgets
- Manual sync policy

### Phase 3: ArgoCD ApplicationSets (Week 3)

#### 3.1. Create ApplicationSets for Multi-Environment

**Tasks**:
- [ ] Create `argocd/applicationsets/` directory
- [ ] Create ApplicationSet for each layer (infrastructure, platform, observability, applications)
- [ ] Use Git directory generator to auto-discover environments

**Example ApplicationSet**:
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
      revision: main
      directories:
      - path: environments/*

  template:
    metadata:
      name: 'infrastructure-{{path.basename}}'
      annotations:
        argocd.argoproj.io/sync-wave: "0"
      labels:
        kagenti.dev/layer: infrastructure
        kagenti.dev/environment: '{{path.basename}}'

    spec:
      project: default

      source:
        repoURL: https://github.com/Ladas/kagenti-demo-deployment.git
        targetRevision: main
        path: '{{path}}'
        kustomize:
          commonLabels:
            environment: '{{path.basename}}'

      destination:
        server: https://kubernetes.default.svc  # Override per cluster
        namespace: default

      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true
```

#### 3.2. Update Root App to Deploy ApplicationSets

**Tasks**:
- [ ] Modify `argocd/bootstrap/kind/root-app.yaml` to point to `applicationsets/`
- [ ] Create similar bootstrap for OpenShift

### Phase 4: Testing and Validation (Week 4)

#### 4.1. Kind Environment Testing

**Tasks**:
- [ ] Deploy to fresh Kind cluster
- [ ] Verify all upstream operators install correctly
- [ ] Test full platform deployment (infrastructure → platform → observability → applications)
- [ ] Verify tracing works end-to-end

#### 4.2. OpenShift Staging Testing

**Tasks**:
- [ ] Deploy to OpenShift stage cluster
- [ ] Verify OLM operators install correctly
- [ ] Verify Service Mesh 3.0 (Sail Operator) works
- [ ] Verify cert-manager for OpenShift generates certificates
- [ ] Verify OpenShift Pipelines integration
- [ ] Test Kagenti platform deployment

#### 4.3. Production Deployment

**Tasks**:
- [ ] Review production overlay configuration
- [ ] Deploy to OpenShift prod cluster
- [ ] Monitor operator health
- [ ] Document any issues/workarounds

---

## References

### Official Documentation

#### Red Hat OpenShift Operators
- **OpenShift Pipelines**: [Docs](https://docs.openshift.com/container-platform/latest/cicd/pipelines/understanding-openshift-pipelines.html)
- **cert-manager for OpenShift**: [Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)
- **OpenShift Service Mesh 2.x**: [Docs](https://docs.openshift.com/container-platform/latest/service_mesh/v2x/ossm-about.html)
- **OpenShift Service Mesh 3.0 (Sail)**: [Blog](https://www.redhat.com/en/blog/introducing-a-new-operator-for-istio-on-openshift)
- **Service Mesh vs Istio Differences**: [Docs](https://docs.openshift.com/container-platform/4.17/service_mesh/v2x/ossm-vs-community.html)

#### Upstream Projects
- **Istio Documentation**: [istio.io/docs](https://istio.io/latest/docs/)
- **Tekton Pipelines**: [tekton.dev/docs/pipelines](https://tekton.dev/docs/pipelines/)
- **cert-manager**: [cert-manager.io/docs](https://cert-manager.io/docs/)
- **Kiali**: [kiali.io/docs](https://kiali.io/docs/)

#### Kagenti Project
- **Kagenti Operators**: [GitHub](https://github.com/kagenti/kagenti-operator)
- **Platform Operator**: [README](https://github.com/kagenti/kagenti-operator/blob/main/platform-operator/README.md)
- **Agent Operator**: [README](https://github.com/kagenti/kagenti-operator/blob/main/kagenti-operator/README.md)

### Related Documentation in This Repository
- [TODO: Argo CD Repository Structure](./TODO_ARGO_CD_STRUCTURE.md) - GitOps best practices
- [TODO: Distributed Tracing Setup](./TODO_TRACING.md) - OpenTelemetry integration
- [Kagenti Operators Guide](./docs/kagenti_operators.md) - Operator architecture
- [Documentation Index](./docs/README.md) - Complete documentation

---

**Document Version**: 1.0
**Last Updated**: 2025-01-15
**Maintained By**: Kagenti Platform Team
**Status**: Research Complete - Ready for Implementation
