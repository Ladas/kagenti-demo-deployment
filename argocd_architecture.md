# Kagenti ArgoCD GitOps Architecture

**Last Updated**: 2025-11-07

## Overview

This document defines the ArgoCD Application architecture for deploying the Kagenti agentic platform using GitOps principles.

## Design Principles

1. **Layered Deployment**: Applications are deployed in sync waves to respect dependencies
2. **Separation of Concerns**: Each logical component is a separate ArgoCD Application
3. **Both Operators**: Deploy both `kagenti-operator` (Agent CRDs) and `platform-operator` (Platform/Component CRDs)
4. **Infrastructure as Code**: All changes via Git commits + ArgoCD sync
5. **Minimal Monoliths**: Break down large applications into focused, manageable pieces

## Sync Wave Strategy

```
Wave 0  → Core Infrastructure (Gateway API, cert-manager, Tekton, Istio)
Wave 5  → Infrastructure Services (Keycloak, Registry, SPIRE)
Wave 10 → Kagenti Operators (kagenti-operator, platform-operator)
Wave 15 → Platform Components (Kagenti UI, Gateway)
Wave 20 → Observability (Grafana, Tempo, Phoenix, Jaeger, OTEL)
Wave 25 → Applications (Agents)
```

## Application Architecture

### **Wave 0 - Core Infrastructure**

These are foundational components with no inter-dependencies. They can be deployed in parallel.

#### **gateway-api** (Wave 0)
- **Type**: Kustomize Application
- **Path**: `components/00-infrastructure/gateway-api`
- **Namespace**: N/A (cluster-scoped CRDs)
- **Purpose**: Gateway API CRDs (HTTPRoute, Gateway, etc.)
- **Dependencies**: None

#### **cert-manager** (Wave 0)
- **Type**: Kustomize Application
- **Path**: `components/00-infrastructure/cert-manager`
- **Namespace**: `cert-manager`
- **Purpose**: TLS certificate management for webhooks and services
- **Dependencies**: None

#### **tekton** (Wave 0)
- **Type**: Kustomize Application
- **Path**: `components/00-infrastructure/tekton`
- **Namespace**: `tekton-pipelines`
- **Purpose**: CI/CD pipeline engine for agent builds
- **Dependencies**: None

#### **istio-base** (Wave 0)
- **Type**: Helm Application
- **Chart**: `istio/base`
- **Namespace**: `istio-system`
- **Purpose**: Istio CRDs and base resources
- **Dependencies**: None

#### **istiod** (Wave 0)
- **Type**: Helm Application
- **Chart**: `istio/istiod`
- **Namespace**: `istio-system`
- **Purpose**: Istio control plane
- **Dependencies**: istio-base (via sync wave ordering)

#### **istio-config** (Wave 0)
- **Type**: Kustomize Application
- **Path**: `components/00-infrastructure/istio`
- **Namespace**: `istio-system`
- **Purpose**: Istio strict mTLS policies, DestinationRules
- **Dependencies**: istiod

---

### **Wave 5 - Infrastructure Services**

Services that provide infrastructure capabilities but depend on core components.

#### **keycloak** (Wave 5)
- **Type**: Kustomize Application
- **Path**: `components/00-infrastructure/keycloak`
- **Namespace**: `keycloak`
- **Purpose**: SSO and authentication provider
- **Dependencies**: Gateway API, Istio

#### **container-registry** (Wave 5)
- **Type**: Kustomize Application
- **Path**: `components/00-infrastructure/container-registry`
- **Namespace**: `cr-system`
- **Purpose**: Local container image registry for agent builds
- **Dependencies**: Gateway API, Istio

#### **spire** (Wave 5)
- **Type**: Helm Application
- **Chart**: `spiffe/spire`
- **Namespace**: `spire-system`
- **Purpose**: SPIFFE/SPIRE for workload identity
- **Dependencies**: Istio

#### **kiali** (Wave 5)
- **Type**: Helm Application
- **Chart**: `kiali/kiali-server`
- **Namespace**: `kiali-system`
- **Purpose**: Istio service mesh observability
- **Dependencies**: Istio, Prometheus (from observability wave)

---

### **Wave 10 - Kagenti Operators**

Both operators are deployed in this wave. They depend on cert-manager and Tekton.

#### **kagenti-operator** (Wave 10)
- **Type**: Helm Application
- **Chart**: `https://github.com/kagenti/kagenti-operator.git//charts/kagenti-operator`
- **Namespace**: `kagenti-system`
- **Purpose**: Manages Agent and AgentBuild CRDs
- **CRDs**: `Agent.agent.kagenti.dev`, `AgentBuild.agent.kagenti.dev`
- **Manager**: `kagenti-controller-manager`
- **Image**: `ghcr.io/kagenti/kagenti-operator/kagenti-operator`
- **Dependencies**: cert-manager (for webhook certs), Tekton (for pipeline templates)
- **Features**:
  - Agent lifecycle management
  - AgentBuild automation (Tekton integration)
  - Webhook validation for Agent resources

#### **platform-operator** (Wave 10)
- **Type**: Helm Application
- **Chart**: `https://github.com/kagenti/kagenti-operator.git//charts/platform-operator`
- **Namespace**: `kagenti-system`
- **Purpose**: Manages Platform and Component CRDs
- **CRDs**: `Platform.kagenti.operator.dev`, `Component.kagenti.operator.dev`
- **Manager**: `agentic-platform-controller-manager`
- **Image**: `ghcr.io/kagenti/kagenti-operator/platform-operator`
- **Dependencies**: cert-manager (for webhook certs), Tekton (for pipeline templates)
- **Features**:
  - Platform composition (infrastructure + agents)
  - Component lifecycle management
  - Webhook validation for Platform/Component resources

**Note**: Both operators can coexist in the same namespace (`kagenti-system`) because:
- Different manager names (`kagenti-controller-manager` vs `agentic-platform-controller-manager`)
- Different CRD groups (`agent.kagenti.dev` vs `kagenti.operator.dev`)
- Different ServiceAccounts (`controller-manager` vs `agentic-platform-controller-manager`)

---

### **Wave 15 - Platform Components**

Platform services that depend on operators and infrastructure.

#### **platform** (Wave 15)
- **Type**: Kustomize Application
- **Path**: `components/01-platform`
- **Namespace**: Multiple (per component)
- **Purpose**: Core platform services
- **Dependencies**: Operators, Keycloak, Gateway API
- **Contains**:
  - Kagenti UI (with Keycloak OAuth integration)
  - Gateway configurations
  - OAuth2 Proxy (if needed)
  - Platform-level resources

---

### **Wave 20 - Observability**

Observability stack for monitoring and tracing.

#### **observability** (Wave 20)
- **Type**: Kustomize Application
- **Path**: `components/02-observability`
- **Namespace**: `observability`
- **Purpose**: Observability and monitoring stack
- **Dependencies**: Istio (for service mesh metrics)
- **Contains**:
  - Grafana (dashboards)
  - Tempo (distributed tracing)
  - Phoenix (AI observability)
  - Jaeger (tracing UI)
  - OTEL Collector (telemetry aggregation)
  - Kube State Metrics
  - Kubernetes Dashboard

---

### **Wave 25 - Applications**

Agent applications and workloads.

#### **agents** (Wave 25)
- **Type**: Kustomize Application
- **Path**: `components/03-applications`
- **Namespace**: `agents`
- **Purpose**: Deploy agent applications
- **Dependencies**: Platform, Operators
- **Contains**:
  - code-agent (plain Deployment for now, migrate to Agent CRD later)
  - research-agent (plain Deployment for now, migrate to Agent CRD later)
  - orchestrator-agent (plain Deployment for now, migrate to Agent CRD later)

**Note**: Agents are currently plain Deployments. With kagenti-operator deployed, we can migrate them to Agent CRDs later for enhanced lifecycle management.

---

## Directory Structure

```
kagenti-demo-deployment/
├── argocd/
│   ├── bootstrap/
│   │   └── kind/
│   │       └── root-app.yaml                    # Root Application (App-of-Apps)
│   │
│   ├── applications/
│   │   ├── base/                                # Reusable Application templates
│   │   │   ├── kustomization.yaml
│   │   │   ├── 00-infrastructure/
│   │   │   │   ├── gateway-api.yaml             # Wave 0
│   │   │   │   ├── cert-manager.yaml            # Wave 0
│   │   │   │   ├── tekton.yaml                  # Wave 0
│   │   │   │   ├── istio-config.yaml            # Wave 0
│   │   │   │   ├── keycloak.yaml                # Wave 5
│   │   │   │   └── container-registry.yaml      # Wave 5
│   │   │   ├── 01-operators/
│   │   │   │   └── kustomization.yaml           # (Operators are Helm, in helm/)
│   │   │   ├── 02-platform/
│   │   │   │   └── platform.yaml                # Wave 15
│   │   │   ├── 03-observability/
│   │   │   │   └── observability.yaml           # Wave 20
│   │   │   └── 04-applications/
│   │   │       └── agents.yaml                  # Wave 25
│   │   │
│   │   ├── helm/                                # Helm-based Applications
│   │   │   ├── kustomization.yaml
│   │   │   ├── istio-base.yaml                  # Wave 0
│   │   │   ├── istiod.yaml                      # Wave 0
│   │   │   ├── spire.yaml                       # Wave 5
│   │   │   ├── kiali.yaml                       # Wave 5
│   │   │   ├── kagenti-operator.yaml            # Wave 10
│   │   │   └── platform-operator.yaml           # Wave 10
│   │   │
│   │   └── kind-local/                          # Kind-specific patches
│   │       ├── kustomization.yaml
│   │       └── server-patch.yaml
│   │
├── components/                                  # Component manifests
│   ├── 00-infrastructure/
│   │   ├── gateway-api/
│   │   ├── cert-manager/
│   │   ├── tekton/
│   │   ├── istio/
│   │   ├── keycloak/
│   │   └── container-registry/
│   ├── 01-platform/
│   │   ├── kagenti-ui/
│   │   └── gateway/
│   ├── 02-observability/
│   │   ├── grafana/
│   │   ├── tempo/
│   │   ├── phoenix/
│   │   ├── jaeger/
│   │   └── otel-collector/
│   └── 03-applications/
│       └── agents/
│
└── scripts/
    └── kind/
        ├── 00-cleanup.sh
        ├── 01-create-cluster.sh
        ├── 02-install-argocd.sh
        └── 03-bootstrap-apps.sh
```

---

## What Changed from Previous Architecture

### **Removed from infrastructure monolith**:
- ✅ **Keycloak** → Separate Application (wave 5)
- ✅ **Container Registry** → Separate Application (wave 5)
- ✅ **Istio base/istiod** → Separate Helm Applications (wave 0)
- ✅ **Kiali** → Separate Helm Application (wave 5)
- 🆕 **Gateway API** → Separate Application (wave 0)
- 🆕 **cert-manager** → Separate Application (wave 0)
- 🆕 **Tekton** → Separate Application (wave 0)
- 🆕 **Istio config** → Separate Application for strict-mtls policies (wave 0)

### **What remains in each component directory**:
- `00-infrastructure/`: Individual deployable units (gateway-api, cert-manager, tekton, istio, keycloak, registry)
- `01-platform/`: Platform services (Kagenti UI, Gateway)
- `02-observability/`: Observability stack
- `03-applications/`: Agent applications

### **New Operator Applications**:
- 🆕 **kagenti-operator** (wave 10) - Agent/AgentBuild CRDs
- 🆕 **platform-operator** (wave 10) - Platform/Component CRDs (renamed from old `kagenti-operator`)

---

## Migration Strategy

Since we're starting fresh (wipe + redeploy):

1. ✅ Wipe cluster: `./scripts/kind/00-cleanup.sh`
2. ✅ Create cluster: `./scripts/kind/01-create-cluster.sh`
3. ✅ Install ArgoCD: `./scripts/kind/02-install-argocd.sh`
4. ✅ Bootstrap Applications: `./scripts/kind/03-bootstrap-apps.sh`
5. ✅ Sync all layers:
   ```bash
   # Wave 0 - Core Infrastructure
   argocd app sync gateway-api cert-manager tekton istio-base istiod istio-config --port-forward --port-forward-namespace argocd --grpc-web

   # Wave 5 - Infrastructure Services
   argocd app sync keycloak container-registry spire kiali --port-forward --port-forward-namespace argocd --grpc-web

   # Wave 10 - Operators
   argocd app sync kagenti-operator platform-operator --port-forward --port-forward-namespace argocd --grpc-web

   # Wave 15 - Platform
   argocd app sync platform --port-forward --port-forward-namespace argocd --grpc-web

   # Wave 20 - Observability
   argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

   # Wave 25 - Applications
   argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web
   ```

---

## Benefits of This Architecture

1. **Clear Dependencies**: Sync waves ensure correct deployment order
2. **Granular Control**: Each component can be synced/rolled back independently
3. **Reduced Blast Radius**: Issues in one component don't affect others
4. **Better GitOps**: Smaller, focused manifests are easier to review and manage
5. **Both Operators**: Full Kagenti operator stack (Agent + Platform CRDs)
6. **Scalable**: Easy to add new components without touching existing ones
7. **Observable**: ArgoCD UI clearly shows health of each component
8. **Clean Separation**: Infrastructure, Platform, Observability, Applications are distinct layers

---

## Future Enhancements

1. **Migrate agents to Agent CRDs**: Once kagenti-operator is stable, convert plain Deployments to Agent resources
2. **Add Platform CR**: Create a Platform resource that composes infrastructure + agents
3. **External Secrets**: Replace Kubernetes Secrets with External Secrets Operator + Vault
4. **Multi-cluster**: Extend to OpenShift/other clusters with Kustomize overlays
5. **Progressive Delivery**: Add Argo Rollouts for canary deployments
6. **Notification**: Integrate ArgoCD notifications for Slack/email alerts
