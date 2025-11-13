# Component Inventory & Gap Analysis

**Last Updated**: 2025-11-07
**Purpose**: Track which components from kagenti/kagenti installer are deployed in ArgoCD GitOps setup

---

## Component Mapping: Installer vs ArgoCD Deployment

### Layer 0: Infrastructure (00-infrastructure/)

| Installer Component | Status | ArgoCD Location | Notes |
|-------------------|---------|-----------------|-------|
| **REGISTRY** | ⏸️ Skipped | N/A | Local Kind registry, not needed for GitOps |
| **TEKTON** | ✅ Deployed | components/infrastructure/tekton/ | Tekton Pipelines & Triggers v0.66.0 |
| **CERT_MANAGER** | ✅ Deployed | components/infrastructure/cert-manager/ | Cert-Manager for TLS |
| **ISTIO** | ✅ Deployed | argocd/applications/helm/istio-base.yaml<br>argocd/applications/helm/istiod.yaml | v1.24.2 via Helm |
| **METRICS_SERVER** | ❌ Missing | N/A | Need to add |
| **GATEWAY** (Gateway API) | ✅ Deployed | components/infrastructure/gateway-api/ | Kubernetes Gateway API CRDs |

**Notes**:
- Istio migrated from pre-rendered manifests to Helm charts
- Tekton includes both Pipelines and Triggers
- SPIRE is installer component but not yet in ArgoCD structure

---

### Layer 1: Platform (01-platform/)

| Installer Component | Status | ArgoCD Location | Notes |
|-------------------|---------|-----------------|-------|
| **KEYCLOAK** | ✅ Deployed | components/platform/keycloak/ | OAuth/OIDC provider |
| **OPERATOR** | ✅ Deployed | components/operators/kagenti-operator/ | Kagenti Platform Operator |
| **UI** | ✅ Deployed | components/platform/kagenti-ui/ | Kagenti Web UI with OAuth integration |
| **MCP_GATEWAY** | ✅ Deployed | components/platform/mcp-gateway/ | MCP Gateway for agent communication |
| **TOOLHIVE** | ❌ Missing | N/A | Need to add from installer |
| **SPIRE** | ❌ Missing | N/A | SPIFFE/SPIRE for workload identity |

**Notes**:
- Keycloak OAuth integration working via Job-based secret generation
- UI accessible at kagenti.localtest.me:9443 (HTTPS)
- MCP Gateway deployed but no ingress configured yet
- TOOLHIVE is a new component (not in original deployment)

---

### Layer 2: Observability (02-observability/)

| Installer Component | Status | ArgoCD Location | Notes |
|-------------------|---------|-----------------|-------|
| **ADDONS** | ✅ Partial | components/observability/ | Includes Prometheus, Kiali, Phoenix |
| - Prometheus | ✅ Deployed | components/observability/prometheus/ | Metrics collection |
| - Kiali | ✅ Deployed | argocd/applications/helm/kiali.yaml | v2.4.0 via Helm, Istio service mesh visualization |
| - Phoenix | ✅ Deployed | components/observability/phoenix/ | LLM observability (Arize Phoenix) |
| - Tempo | ✅ Deployed | components/observability/tempo/ | Distributed tracing backend |
| - Grafana | ✅ Deployed | components/observability/grafana/ | Dashboards (OIDC pending) |
| - OTEL Collector | ✅ Deployed | components/observability/otel-collector/ | OpenTelemetry data collection |
| - Jaeger | ✅ Deployed | components/observability/jaeger/ | Jaeger UI for tracing |
| **Kubernetes Dashboard** | ✅ Deployed | argocd/applications/helm/k8s-dashboard.yaml | Deployed via Helm (pending verification) |

**Notes**:
- Kiali migrated to Helm-based deployment
- Grafana OIDC secret Job still pending creation
- Phoenix provides LLM-specific observability features
- Full observability stack integrated with Istio

---

### Layer 3: Applications (03-applications/)

| Installer Component | Status | ArgoCD Location | Notes |
|-------------------|---------|-----------------|-------|
| **AGENTS** | ⏸️ Deployed (not running) | components/agents/ | Agent CRDs deployed, images not built |
| - Research Agent | ⏸️ Pending images | components/agents/research/ | Needs container images |
| - Code Agent | ⏸️ Pending images | components/agents/code/ | Needs container images |
| - Orchestrator Agent | ⏸️ Pending images | components/agents/orchestrator/ | Needs container images |
| **INSPECTOR** | ❌ Missing | N/A | MCP Inspector tool not deployed |

**Notes**:
- Agent CRDs are deployed but pods not running (no images in registry)
- Need to build and push agent images
- Inspector is a debugging/inspection tool for MCP

---

## Component Layer Mapping (TODO_ARGO_CD_STRUCTURE.md Alignment)

### Proposed Reorganization

```
components/
├── 00-infrastructure/          # Layer 0: Cluster infrastructure (sync wave 0)
│   ├── cert-manager/          ✅ Deployed
│   ├── gateway-api/           ✅ Deployed
│   ├── istio/                 ✅ Deployed (via Helm)
│   ├── tekton/                ✅ Deployed
│   ├── metrics-server/        ❌ TODO: Add from installer
│   └── kagenti-deps/          ✅ Deployed (cleanup needed - has duplicates)
│
├── 01-platform/               # Layer 1: Platform services (sync wave 10)
│   ├── keycloak/              ✅ Deployed
│   ├── mcp-gateway/           ✅ Deployed
│   ├── kagenti-ui/            ✅ Deployed
│   ├── kagenti-operator/      ✅ Deployed (currently in operators/)
│   ├── toolhive/              ❌ TODO: Add from installer
│   └── spire/                 ❌ TODO: Add from installer
│
├── 02-observability/          # Layer 2: Observability stack (sync wave 20)
│   ├── otel-collector/        ✅ Deployed
│   ├── tempo/                 ✅ Deployed
│   ├── phoenix/               ✅ Deployed
│   ├── grafana/               ✅ Deployed (OIDC Job pending)
│   ├── prometheus/            ✅ Deployed
│   ├── kiali/                 ✅ Deployed (via Helm)
│   ├── jaeger/                ✅ Deployed
│   └── k8s-dashboard/         ✅ Deployed (via Helm, pending verification)
│
└── 03-applications/           # Layer 3: Business applications (sync wave 30)
    ├── agents/
    │   ├── research/          ⏸️ CRD deployed, image pending
    │   ├── code/              ⏸️ CRD deployed, image pending
    │   └── orchestrator/      ⏸️ CRD deployed, image pending
    └── tools/
        └── mcp-inspector/     ❌ TODO: Add from installer
```

---

## Installation Order (from kagenti/kagenti installer)

The installer deploys components in this order:

1. **Infrastructure First**:
   - REGISTRY (skipped in ArgoCD setup)
   - TEKTON
   - CERT_MANAGER
   - OPERATOR
   - TOOLHIVE
   - ISTIO
   - METRICS_SERVER

2. **Istio-Dependent Components** (only if ISTIO deployed):
   - GATEWAY (Gateway API)
   - ADDONS (Prometheus, Kiali, Phoenix)
   - KEYCLOAK
   - SPIRE
   - MCP_GATEWAY
   - AGENTS
   - UI
   - INSPECTOR

**Key Insight**: Installer has dependencies:
- Everything after Istio depends on Istio being ready
- This validates the layered sync wave approach in TODO_ARGO_CD_STRUCTURE.md

---

## Gap Analysis

### Missing Components (from installer)

1. **METRICS_SERVER**: Kubernetes metrics server for HPA
   - Priority: Medium
   - Location: Should go in 00-infrastructure/

2. **TOOLHIVE**: Tool management/discovery
   - Priority: Medium
   - Location: Should go in 01-platform/

3. **SPIRE**: SPIFFE workload identity
   - Priority: Low (optional security enhancement)
   - Location: Should go in 01-platform/

4. **INSPECTOR**: MCP Inspector debugging tool
   - Priority: Low (development tool)
   - Location: Should go in 03-applications/tools/

### Incomplete Deployments

1. **Grafana OIDC**: Secret Job not created yet
   - Priority: High
   - Blocks: Grafana OAuth login

2. **Agent Images**: Not built/pushed to registry
   - Priority: High
   - Blocks: Agent pod startup

3. **Kubernetes Dashboard**: Deployed but not verified
   - Priority: Medium
   - Need to verify access and integration

---

## Deployment Coverage

| Layer | Components | Deployed | Missing | Coverage |
|-------|------------|----------|---------|----------|
| **Infrastructure** | 6 | 5 | 1 (metrics-server) | 83% |
| **Platform** | 6 | 4 | 2 (toolhive, spire) | 67% |
| **Observability** | 8 | 8 | 0 | 100% |
| **Applications** | 4 | 3 (CRDs only) | 1 (inspector) | 75% |
| **Overall** | 24 | 20 | 4 | 83% |

---

## Next Steps

### Phase 1: Directory Reorganization (Current Task)

1. Create layered structure:
   ```bash
   mkdir -p components/00-infrastructure
   mkdir -p components/01-platform
   mkdir -p components/02-observability
   mkdir -p components/03-applications
   ```

2. Move existing components:
   ```bash
   # Infrastructure
   mv components/infrastructure/* components/00-infrastructure/

   # Platform
   mv components/platform/* components/01-platform/
   mv components/operators/kagenti-operator components/01-platform/

   # Observability
   mv components/observability/* components/02-observability/

   # Applications
   mv components/agents components/03-applications/
   ```

3. Clean up old directories:
   ```bash
   rmdir components/infrastructure components/platform components/operators components/observability
   ```

### Phase 2: Add Missing Components

1. Add metrics-server to 00-infrastructure/
2. Add toolhive to 01-platform/
3. Add inspector to 03-applications/tools/
4. (Optional) Add spire to 01-platform/

### Phase 3: Complete ArgoCD Best Practices

1. Create AppProjects (argocd/projects/)
2. Add sync waves to Applications
3. Create ApplicationSets for multi-env
4. Implement root App of Apps

### Phase 4: Complete Pending Deployments

1. Create Grafana OIDC secret Job
2. Build and push agent images
3. Verify all pods are Ready
4. Test end-to-end agent creation

---

## References

- Kagenti Installer: https://github.com/kagenti/kagenti/tree/main/kagenti/installer
- TODO_ARGO_CD_STRUCTURE.md: ../TODO_ARGO_CD_STRUCTURE.md
- Current ArgoCD Apps: argocd/applications/

---

**Status**: Ready to begin Phase 1 reorganization
