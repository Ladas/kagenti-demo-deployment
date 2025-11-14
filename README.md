# Kagenti Demo Deployment

GitOps repository for deploying Kagenti AI Agent platform using ArgoCD with the **Components + Overlays** pattern.

## Quick Start

### Kind (Local Development)

```bash
# 1. Create Kind cluster and install ArgoCD
./scripts/kind/01-create-cluster.sh
./scripts/kind/02-install-argocd.sh

# 2. Bootstrap ArgoCD Applications
./scripts/kind/03-bootstrap-apps.sh

# 3. Access ArgoCD and sync applications
open https://localhost:8080  # ArgoCD UI (admin / see terminal output)
```

**Access services** (after ArgoCD syncs all apps):
- ArgoCD: https://localhost:8080
- Grafana: https://grafana.localtest.me:9443
- Kiali: https://kiali.localtest.me:9443
- Phoenix: https://phoenix.localtest.me:9443
- Keycloak: https://keycloak.localtest.me:9443

See [docs/09-deployment/kind-local.md](docs/09-deployment/kind-local.md) for detailed deployment guide.

### Other Environments

| Environment | Status | Guide |
|-------------|--------|-------|
| K3s (Rancher Desktop) | 🚧 Planned | TBD |
| OpenShift Stage | 🚧 Planned | TBD |
| OpenShift Prod | 🚧 Planned | TBD |

## Documentation

### Getting Started

- [Architecture Overview](docs/00-getting-started/architecture-overview.md) - Platform components and design
- [Prerequisites](docs/00-getting-started/prerequisites.md) - Required tools and setup
- [Quick Start](docs/00-getting-started/quick-start.md) - 15-minute deployment walkthrough
- [Documentation Index](docs/README.md) - Complete documentation map

### Infrastructure

- [Kubernetes & Kind](docs/01-infrastructure/kubernetes.md) - Local Kubernetes with Kind
- [Gateway API](docs/01-infrastructure/gateway-api.md) - HTTPRoute and TLS configuration
- [cert-manager](docs/01-infrastructure/cert-manager.md) - TLS certificate management
- [ArgoCD](docs/01-infrastructure/argocd.md) - GitOps deployment

### Service Mesh

- [Istio](docs/02-service-mesh/istio.md) - Service mesh with Gateway API and mTLS
- [Traffic Management](docs/02-service-mesh/traffic-management.md) - Routing and load balancing

### Authentication

- [Keycloak](docs/03-authentication/keycloak.md) - SSO and identity management
- [OAuth2-Proxy](docs/03-authentication/oauth2-proxy.md) - OAuth2 authentication layer

### Observability

- [Distributed Tracing](docs/04-observability/distributed-tracing.md) - Tempo + Phoenix architecture
- [Grafana](docs/04-observability/grafana.md) - Metrics dashboards
- [Kiali](docs/04-observability/kiali.md) - Service mesh visualization
- [Phoenix](docs/04-observability/phoenix.md) - LLM observability
- [Prometheus](docs/04-observability/prometheus.md) - Metrics collection
- [GenAI Semantic Conventions](docs/04-observability/genai-semantic-conventions.md) - AI agent tracing standards

### CI/CD & Operations

- [GitOps Workflows](docs/05-ci-cd/gitops-workflows.md) - ArgoCD and Git workflows
- [Tekton](docs/05-ci-cd/tekton.md) - CI/CD pipelines
- [Troubleshooting](docs/10-operations/troubleshooting.md) - Common issues and solutions

### Security

- [Network Policies](docs/08-security/network-policies.md) - Network isolation
- [Secrets Management](docs/08-security/secrets-management.md) - Secret handling
- [Encryption](docs/08-security/encryption.md) - mTLS and TLS configuration

## Repository Structure

```
kagenti-demo-deployment/
├── argocd/                        # ArgoCD GitOps definitions
│   ├── bootstrap/kind/           # Root Application (App-of-Apps)
│   └── applications/             # Application definitions
│       ├── base/                # Base application templates
│       ├── helm/                # Helm-based applications
│       └── kind-local/          # Kind-specific patches
│
├── components/                    # Reusable Kubernetes manifests
│   ├── 00-infrastructure/       # Foundation (Keycloak, Gateway API, Tekton)
│   ├── 01-platform/            # Platform operators and services
│   ├── 02-observability/       # Monitoring (Grafana, Phoenix, Tempo, Kiali)
│   └── 03-applications/        # Applications (agents)
│
├── scripts/                      # Automation scripts
│   ├── kind/                    # Kind cluster setup
│   ├── deploy/                  # Deployment helpers
│   └── validation/              # Validation scripts
│
├── environments/                 # Environment overlays (legacy)
└── docs/                        # Documentation
```

## Architecture

### Components + Overlays Pattern

This repository uses a hybrid pattern where:
- **Components** (`components/`) contain reusable Kubernetes manifests
- **Overlays** (`argocd/applications/`) reference components with environment-specific patches
- **ArgoCD** deploys using App-of-Apps pattern with sync waves

```
Root App (kagenti-platform-kind)
├── Infrastructure Apps (wave 0-5)
│   ├── cert-manager (Helm)
│   ├── istio-base (Helm)
│   ├── istiod (Helm)
│   ├── gateway-api
│   ├── keycloak
│   ├── oauth2-proxy
│   └── tekton
│
├── Platform Apps (wave 10)
│   ├── kagenti-operator (Helm)
│   └── container-registry
│
├── Observability Apps (wave 15)
│   ├── kiali (Helm)
│   ├── grafana
│   ├── tempo
│   ├── phoenix
│   └── kubernetes-dashboard
│
└── Application Apps (wave 20)
    └── agents
```

**Benefits:**
- No code duplication across environments
- Modular components can be enabled/disabled per environment
- Single source of truth for manifests
- Easy to add new environments

### Security

All services use:
- 🔒 **HTTPS-only access** - TLS termination at Gateway with HTTP→HTTPS redirect
- 🔒 **Istio mTLS STRICT** - Service-to-service encryption
- 🔒 **Keycloak SSO** - OAuth2/OIDC authentication
- 🔒 **NetworkPolicies** - Defense-in-depth network security

### Observability Stack

| Component | Purpose | Authentication |
|-----------|---------|----------------|
| **Tempo** | Infrastructure traces (Istio, databases) | Keycloak `kubernetes` realm |
| **Phoenix** | Agent/LLM traces (OpenInference) | Keycloak `kagenti` realm |
| **Grafana** | Metrics dashboards | Keycloak `kubernetes` realm |
| **Kiali** | Service mesh visualization | Keycloak `kubernetes` realm |
| **Prometheus** | Metrics collection | Internal only |
| **Kubernetes Dashboard** | Cluster management | Keycloak `kubernetes` realm |

**Dual-Backend Tracing:**
- OTEL Collector routes traces based on `openinference.span.kind` attribute
- Infrastructure traces → Tempo (short retention)
- Agent/LLM traces → Phoenix (long retention)

## Resource Requirements (Kind)

**Minimum:**
- CPU: 4 cores
- Memory: 8 GB RAM
- Disk: 20 GB

**Recommended:**
- CPU: 6 cores
- Memory: 12 GB RAM
- Disk: 40 GB

**Total pods:** ~35-40

## Reference Documentation

- [CI/CD Testing](docs/CI_CD_TESTING.md) - Integration test strategy
- [HTTPS Access Guide](HTTPS_ACCESS_GUIDE.md) - Service URLs and access details
- [HTTPS Enforcement](HTTPS_ENFORCEMENT_SUMMARY.md) - TLS implementation details
- [Architecture Details](ARCHITECTURE.md) - Detailed architecture documentation
- [Documentation Progress](DOCS_PROGRESS_2025-11-11.md) - Documentation status

## Contributing

See [CLAUDE.md](CLAUDE.md) for development workflow and GitOps best practices.
