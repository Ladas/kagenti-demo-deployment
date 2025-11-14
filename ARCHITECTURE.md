# Kagenti Platform Architecture

**Last Updated**: 2025-11-10

## Overview

The Kagenti Platform is a GitOps-managed AI agent orchestration platform deployed on Kubernetes using ArgoCD. All infrastructure, platform services, and applications are defined as code and deployed via ArgoCD sync.

## Deployment Structure

### Single Source of Truth

**No Duplications**: Each service is deployed via ONE method only:
- **Keycloak**: Operator-based (`components/00-infrastructure/keycloak/`)
- **SPIRE**: Helm values (`components/00-infrastructure/spire/`)
- **Container Registry**: Helm chart (`argocd/applications/helm/container-registry.yaml`)
- **Istio**: Helm charts (`argocd/applications/helm/istio-*.yaml`)
- **All Others**: Kustomize (`components/`)

### Component Layers

```
components/
├── 00-infrastructure/     # Core infrastructure (sync wave 0-5)
│   ├── cert-manager.yaml
│   ├── gateway-api-chart/
│   ├── tekton/
│   ├── istio/
│   ├── keycloak/          # Operator v26.4.1 + SPIFFE
│   ├── spire/             # Workload Identity
│   ├── oauth2-proxy/
│   └── mcp-inspector/
│
├── 01-platform/           # Platform services (sync wave 10-15)
│   ├── kagenti-ui/
│   ├── kagenti-operator/  # Tekton pipelines for agents
│   ├── platform-operator/ # Platform UI/management
│   ├── gateway/
│   └── tls/
│
├── 02-observability/      # Monitoring stack (sync wave 20)
│   ├── grafana/
│   ├── tempo/
│   ├── phoenix/
│   ├── otel-collector/
│   ├── kube-state-metrics/
│   └── kubernetes-dashboard/
│
└── 03-applications/       # AI agents (sync wave 25)
    └── agents/
```

## Key Technologies

### Authentication & Identity
- **Keycloak v26.4.1**: SSO with SPIFFE preview features enabled
- **SPIRE**: Workload identity (trust domain: `kagenti.dev`)
- **OAuth2-Proxy**: Per-service authentication proxies

### Service Mesh & Security
- **Istio**: Service mesh with mTLS STRICT mode
- **Gateway API**: Kubernetes-native ingress
- **Cert-Manager**: Automatic TLS certificate management

### GitOps & CI/CD
- **ArgoCD**: GitOps continuous delivery
- **Tekton**: CI/CD pipelines for building agents
- **Two Operators**:
  - `kagenti-operator`: Tekton pipeline management for agent builds
  - `platform-operator`: Platform UI and management

### Observability
- **Grafana**: Dashboards and visualization
- **Tempo**: Distributed tracing
- **Phoenix**: LLM observability
- **OTEL Collector**: OpenTelemetry collection

## Encryption Architecture

**ALL network traffic is encrypted via Istio mTLS (STRICT mode)**:

```
App → Istio Sidecar → mTLS → Network → Istio Sidecar → App
     (localhost HTTP)  (encrypted)           (localhost HTTP)
```

- Applications speak HTTP to local sidecar (same pod)
- Sidecars transparently encrypt ALL network traffic
- Automatic certificate rotation via Istio
- No application TLS configuration needed

See [ENCRYPTION_ARCHITECTURE.md](./docs/ENCRYPTION_ARCHITECTURE.md) for details.

## Access Patterns

### Local Development (Kind)

All services accessible via `localtest.me` DNS wildcard pointing to localhost:

```
https://kagenti.localtest.me:9443      # Kagenti UI
https://keycloak.localtest.me:9443     # Keycloak Admin
https://grafana.localtest.me:9443      # Grafana
https://phoenix.localtest.me:9443      # Phoenix AI Observability
https://argocd.localtest.me:9443       # ArgoCD UI
https://spire-tornjak.localtest.me:9443  # SPIRE Management
```

Run `./scripts/show-access-info.sh` for full access information.

### Production (OpenShift)

Services use proper DNS names with Let's Encrypt certificates.

## Deployment Methods by Service

| Service | Method | Location | Rationale |
|---------|--------|----------|-----------|
| **Keycloak** | Operator | `components/00-infrastructure/keycloak/` | Declarative realm management, SPIFFE support |
| **SPIRE** | Helm | `components/00-infrastructure/spire/` | Official SPIFFE charts |
| **Istio** | Helm | `argocd/applications/helm/istio-*.yaml` | Upstream Istio charts |
| **Container Registry** | Helm | `argocd/applications/helm/container-registry.yaml` | Simple, dev-only |
| **Kiali** | Helm | `argocd/applications/helm/kiali.yaml` | Official Kiali charts |
| **Tekton** | Kustomize | `components/00-infrastructure/tekton/` | Raw YAML sufficient |
| **Cert-Manager** | Kustomize | `components/00-infrastructure/cert-manager.yaml` | CRD-only |
| **Gateway API** | Kustomize | `components/00-infrastructure/gateway-api-chart/` | CRD-only |
| **OAuth2-Proxy** | Kustomize | `components/00-infrastructure/oauth2-proxy/` | Multiple instances |
| **Grafana** | Kustomize | `components/02-observability/grafana/` | Custom dashboards |
| **Tempo** | Kustomize | `components/02-observability/tempo/` | Simple deployment |
| **Phoenix** | Kustomize | `components/02-observability/phoenix/` | Custom config |
| **OTEL Collector** | Kustomize | `components/02-observability/otel-collector/` | Custom pipeline |
| **Kagenti UI** | Kustomize | `components/01-platform/kagenti-ui/` | Stateless app |
| **Operators** | Helm | `argocd/applications/helm/*-operator.yaml` | Official operator charts |

## ArgoCD Sync Waves

Applications deploy in order:

1. **Wave -5**: Istio Base CRDs
2. **Wave 0**: Core Infrastructure (cert-manager, gateway-api, tekton)
3. **Wave 5**: Infrastructure Services (Istio, SPIRE, Keycloak)
4. **Wave 10**: Operators (kagenti-operator, platform-operator)
5. **Wave 15**: Platform (Kagenti UI, Gateway, Realms)
6. **Wave 20**: Observability (Grafana, Tempo, Phoenix)
7. **Wave 25**: Applications (AI Agents, Kiali)

## Secret Management

**Development (Kind)**:
- Secrets generated by Jobs at deployment time
- Random passwords via `/dev/urandom`
- No hardcoded credentials in Git

**Production (OpenShift)**:
- External Secrets Operator + Vault
- Sealed Secrets for encrypted secrets in Git

## Known Issues

### ConfigMap SharedResourceWarnings

Both `kagenti-operator` and `platform-operator` create Tekton pipeline ConfigMaps, causing ArgoCD `SharedResourceWarnings`.

**Solution (Applied)**: ServerSideApply enabled in both Applications

**Future Enhancement**: Namespace separation
- `kagenti-operator`: Agent build pipelines (limited permissions)
- `platform-operator`: Platform-wide management (elevated privileges)

See [TODO_ARGO_CLEANUP.md](./TODO_ARGO_CLEANUP.md) Phase 2.3 for details.

## Documentation

- **[CLAUDE.md](./CLAUDE.md)**: GitOps workflow and development guide
- **[argocd_architecture.md](./argocd_architecture.md)**: Detailed ArgoCD structure
- **[ENCRYPTION_ARCHITECTURE.md](./docs/ENCRYPTION_ARCHITECTURE.md)**: mTLS and encryption details
- **[TODO_ARGO_CLEANUP.md](./TODO_ARGO_CLEANUP.md)**: Cleanup plan and decisions
- **[scripts/show-access-info.sh](./scripts/show-access-info.sh)**: Access information script
- **[scripts/platform-status.sh](./scripts/platform-status.sh)**: Health check script

## Quick Start

```bash
# 1. Create Kind cluster + ArgoCD
./scripts/kind/01-create-cluster.sh
./scripts/kind/02-install-argocd.sh
./scripts/kind/03-bootstrap-apps.sh

# 2. Deploy infrastructure
argocd app sync infrastructure --port-forward --port-forward-namespace argocd --grpc-web

# 3. Deploy platform
argocd app sync platform --port-forward --port-forward-namespace argocd --grpc-web

# 4. Deploy observability
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# 5. Check platform health
./scripts/platform-status.sh

# 6. Get access info
./scripts/show-access-info.sh
```

## Version Information

- **Kubernetes**: v1.31 (Kind)
- **ArgoCD**: v2.9.3
- **Istio**: v1.24.2
- **Keycloak**: v26.4.1 (with SPIFFE features)
- **SPIRE**: Latest via Helm
- **Gateway API**: v1.3.0
- **Cert-Manager**: Latest stable

---

**Maintained by**: Kagenti Platform Team
**Repository**: https://github.com/Ladas/kagenti-demo-deployment
