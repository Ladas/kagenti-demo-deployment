# Kagenti Demo Deployment

**GitOps-managed AI Agent Platform** deployed on Kubernetes using ArgoCD with the **Components + Overlays** pattern.

**Current Environment**: Kind (Local Development) ✅
**Planned**: OpenShift (Staging & Production) 🚧

---

## 🎯 What is Kagenti?

Kagenti is a **production-ready AI agent orchestration platform** built on Kubernetes with:

- **GitOps Deployment** - All infrastructure defined as code, deployed via ArgoCD
- **Service Mesh Security** - Istio mTLS STRICT mode for all pod-to-pod communication
- **SSO Authentication** - Keycloak with OAuth2/OIDC for unified access control
- **Distributed Tracing** - Dual-backend (Tempo for infrastructure, Phoenix for AI/LLM traces)
- **Comprehensive Observability** - Grafana, Prometheus, Loki, Kiali for full platform visibility
- **Tekton CI/CD** - Automated agent build pipelines with operator-based workflows

**Key Architecture Documents**:
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Detailed platform architecture and deployment layers
- **[CLAUDE.md](./CLAUDE.md)** - Development workflow, GitOps practices, TDD approach
- **[TODO_SECURITY.md](./TODO_SECURITY.md)** - Comprehensive security roadmap (Kind → OpenShift)

---

## 🚀 Quick Start (15 Minutes)

### One-Command Deployment

```bash
# Complete cluster redeploy (auto-detects repo/branch)
./scripts/quick-redeploy.sh
```

**What it does**:
1. ✅ **Auto-detects** repository and branch (works with PRs/forks in GitHub Actions)
2. ✅ **Destroys** existing Kind cluster
3. ✅ **Creates** new Kind cluster with registry
4. ✅ **Installs** ArgoCD
5. ✅ **Bootstraps** applications (uses detected repo/branch automatically)
6. ✅ **Prompts** for operator images (build/load/skip)
7. ✅ **Prompts** for agent images (build from source/load pre-built/skip)
8. ✅ **Syncs** root application and child apps
9. ✅ **Shows** final status and access URLs

**Branch Detection** (automatic):
- **Local development**: Uses current Git branch
- **GitHub Actions PR**: Automatically uses PR branch and fork repository
- **Default**: Falls back to `main` branch from upstream repo

**Interactive Prompts** (local only, auto-skipped in CI):

**Operator Images** (kagenti-operator, kagenti-platform-operator):
- `y` - Load pre-built images from Docker (30 seconds) ✅ **Recommended**
- `n` - Rebuild from source (2-5 minutes)
- `skip` - Skip loading (operators will show ImagePullBackOff)

**Agent Images** (research-agent, code-agent, orchestrator-agent):
- `y` - Build from source (2-5 minutes)
- `n` - Load pre-built images (30 seconds)
- `skip` - Skip agents (agents will show ImagePullBackOff) ✅ **Default**

**Environment Variables** (optional):
```bash
# Custom agent source location
export AGENT_SOURCE_DIR=/path/to/your/agent-repo
./scripts/quick-redeploy.sh

# Skip all prompts (CI mode)
CI=true ./scripts/quick-redeploy.sh

# Specify operator mode
export OPERATOR_IMAGE_MODE=rebuild  # rebuild|load|skip
./scripts/quick-redeploy.sh
```

---

### Manual Step-by-Step Deployment

For more control, run scripts individually:

```bash
# 1. Create Kind cluster
./scripts/kind/01-create-cluster.sh

# 2. Install ArgoCD
./scripts/kind/02-install-argocd.sh

# 3. Bootstrap ArgoCD Applications
./scripts/kind/03-bootstrap-apps.sh

# 4. (Optional) Load agent images
./scripts/kind/04-load-agent-images.sh build  # or 'load'

# 5. Sync root application (creates all child apps)
argocd app sync kagenti-platform-kind \
  --port-forward --port-forward-namespace argocd --grpc-web \
  --timeout 600

# 6. Monitor deployment progress
./scripts/monitor-argocd-apps.sh 900  # 15-minute timeout

# 7. Check platform health
./scripts/platform-status.sh
```

---

## 🧪 Test-Driven Development (TDD)

**Kagenti follows GitOps + TDD workflow** as documented in [CLAUDE.md](./CLAUDE.md).

### Core Principle

> **ALWAYS test after deployment changes**

All platform changes go through:
1. ✅ **Edit** manifests in Git
2. ✅ **Validate** syntax with `kustomize build`
3. ✅ **Commit** and push to branch
4. ✅ **Sync** via ArgoCD
5. ✅ **Test** with pytest integration tests
6. ✅ **Merge** when tests pass

### Quick Test Commands

```bash
# Fast validation (critical apps only, ~30s)
pytest tests/validation/test_app_state.py -v --only-critical

# Full platform health check (includes automated tests)
./scripts/platform-status.sh

# Specific component tests
pytest tests/integration/test_observability.py -v

# Full test suite with HTML report
pytest tests/ -v --html=report.html --self-contained-html
```

**Test Coverage** (see [docs/CI_CD_TESTING.md](./docs/CI_CD_TESTING.md)):
- ✅ ArgoCD application state validation
- ✅ Pod health checks across all namespaces
- ✅ Service accessibility via Gateway
- ✅ OAuth authentication flows
- ✅ Observability stack integration (Grafana, Tempo, Phoenix)
- ✅ Istio mTLS STRICT mode verification
- ✅ Certificate readiness checks

**Integration with Observability** (see [CLAUDE.md](./CLAUDE.md#monitoring--access)):
- Real-time test results in Grafana dashboards
- Alert testing via Grafana API
- Trace validation in Tempo and Phoenix
- Log aggregation in Loki

---

## 🐳 Loading Agent Images

### Option 1: Use Example Agents (Quick Test)

```bash
# Build from local source
export AGENT_SOURCE_DIR=/path/to/agent-examples-local
./scripts/kind/04-load-agent-images.sh build

# Or load pre-built images
./scripts/kind/04-load-agent-images.sh load
```

**Default agent source** (can be overridden):
```bash
AGENT_SOURCE_DIR=/Users/ladas/Projects/OCTO/research/agent-examples-local
```

### Option 2: Use Your Own Agent Repository

**Point to your own agent repo** by setting environment variable before deployment:

```bash
# Set custom agent source directory
export AGENT_SOURCE_DIR=/path/to/my-agent-repo

# Run quick-redeploy (will use your repo)
./scripts/quick-redeploy.sh
# Select 'y' when prompted for agent images
```

**Requirements** for custom repo:
- Directory structure: `a2a/{agent-name}/Dockerfile`
- Agents: `research-agent`, `code-agent`, `orchestrator-agent`
- Images will be tagged: `localhost:5000/{agent}:v0.0.15`

### Option 3: Use Operator-Based Builds (Production Workflow)

**For production-like builds** using Tekton + kagenti-operator:

```bash
# 1. Setup agent source repo in Kubernetes
./scripts/dev/setup-agent-source-repo.sh

# 2. Trigger builds via Tekton pipelines
./scripts/dev/trigger-agent-builds.sh

# 3. Monitor build progress
kubectl get pipelineruns -n kagenti-operator -w
```

See [components/03-applications/agents/agent-builds/README.md](./components/03-applications/agents/agent-builds/README.md) for details.

**🚧 Note**: Legacy build script (`04-load-agent-images.sh`) is for quick local dev only. Use operator-based workflow for production.

---

## 🌐 Access Services

**All services accessible via `localtest.me` DNS wildcard** (points to localhost):

```bash
# Get comprehensive access information
./scripts/show-access-info.sh
```

| Service | URL | Default Credentials | Purpose |
|---------|-----|---------------------|---------|
| **ArgoCD** | https://argocd.localtest.me:9443 | `admin` / (see `/tmp/argocd-pass.txt`) | GitOps deployment |
| **Keycloak** | https://keycloak.localtest.me:9443 | `admin` / `admin123` (dev) | SSO identity provider |
| **Grafana** | https://grafana.localtest.me:9443 | `admin` / `admin123` (dev) | Metrics dashboards |
| **Phoenix** | https://phoenix.localtest.me:9443 | Keycloak `kagenti` realm | LLM observability |
| **Kiali** | https://kiali.localtest.me:9443 | Keycloak `kubernetes` realm | Service mesh visualization |
| **Kagenti UI** | https://kagenti.localtest.me:9443 | Keycloak `kagenti` realm | Platform management |
| **Kubernetes Dashboard** | https://k8s-dashboard.localtest.me:9443 | Keycloak `kubernetes` realm | Cluster management |

**🔒 Security**:
- ✅ All traffic encrypted (TLS 1.3 at Gateway, mTLS STRICT between services)
- ✅ SSO authentication via Keycloak
- ✅ OAuth2-Proxy for services without native auth
- ✅ Self-signed certificates (Kind only - production uses Let's Encrypt)

See [docs/08-security/encryption.md](./docs/08-security/encryption.md) for encryption architecture.

---

## 📊 Platform Status & Monitoring

### Quick Health Check

```bash
# Comprehensive platform status (includes pytest tests)
./scripts/platform-status.sh
```

**Checks**:
- ✅ ArgoCD applications (health & sync status)
- ✅ Platform pods (all namespaces)
- ✅ Gateway & certificates
- ✅ Istio mTLS STRICT verification
- ✅ Service accessibility (via Gateway)
- ✅ OAuth authentication flows
- ✅ **Automated pytest integration tests** (runs real tests)

### Monitor ArgoCD Sync Progress

```bash
# Monitor with 15-minute timeout, formatted tables
./scripts/monitor-argocd-apps.sh 900
```

**Shows**:
- Formatted ArgoCD application status table (with colors)
- Formatted pod status by namespace table
- Progress tracking with elapsed time
- Smart failure logic (only fails on CRITICAL apps degraded)
- Monitors ALL apps (critical + optional observability, Kiali, Ollama)

### Observability

**Built-in dashboards**:
- **Grafana**: Metrics, dashboards, alerts (https://grafana.localtest.me:9443)
- **Phoenix**: LLM traces, agent observability (https://phoenix.localtest.me:9443)
- **Kiali**: Service mesh topology (https://kiali.localtest.me:9443)
- **Prometheus**: Metrics storage (internal only, accessible via Grafana)

See [docs/04-observability/](./docs/04-observability/) for detailed observability documentation.

---

## 🏗️ Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitOps Layer                             │
│  ArgoCD (App-of-Apps) → Components + Overlays → Kubernetes     │
└─────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Security Layer                              │
│  TLS 1.3 (Gateway) + Istio mTLS STRICT + Keycloak SSO         │
└─────────────────────────────────────────────────────────────────┘
                                ↓
┌──────────────┬──────────────┬──────────────┬─────────────────┐
│ Infrastructure│  Platform    │ Observability│  Applications  │
│ (Wave 0-5)   │ (Wave 10-15) │ (Wave 20)    │ (Wave 25-30)   │
├──────────────┼──────────────┼──────────────┼─────────────────┤
│ Gateway API  │ Operators    │ Grafana      │ AI Agents      │
│ cert-manager │ Kagenti UI   │ Tempo        │ Kiali          │
│ Istio        │ Keycloak     │ Phoenix      │ K8s Dashboard  │
│ Tekton       │ OAuth2-Proxy │ Prometheus   │                │
│              │              │ Loki         │                │
└──────────────┴──────────────┴──────────────┴─────────────────┘
```

**See [ARCHITECTURE.md](./ARCHITECTURE.md)** for:
- Detailed component diagrams
- Deployment layers and sync waves
- Service mesh architecture
- Secrets management (Kind vs OpenShift)
- Network architecture with mTLS
- Access patterns and authentication flows

### Components + Overlays Pattern

```
components/                    # Base Kubernetes manifests (reusable)
├── 00-infrastructure/        # Core (Gateway, cert-manager, Istio, Keycloak)
├── 01-platform/             # Platform services (Operators, UI)
├── 02-observability/        # Monitoring (Grafana, Tempo, Phoenix, Prometheus)
└── 03-applications/         # Applications (AI Agents)

argocd/applications/
├── base/                    # Base Application templates
├── kind-local/             # Kind-specific patches (localtest.me, self-signed certs)
└── openshift/              # OpenShift patches (Routes, SCCs) 🚧 PLANNED
```

**Benefits**:
- ✅ No code duplication across environments
- ✅ Modular components (enable/disable per environment)
- ✅ Single source of truth
- ✅ Easy to add new environments (e.g., OpenShift staging/prod)

### Security Architecture

**Defense-in-Depth (6 Layers)** - see [TODO_SECURITY.md](./TODO_SECURITY.md):

1. **Perimeter** - Gateway API, TLS 1.3, cert-manager
2. **Identity** - Keycloak SSO, OAuth2-Proxy, SPIRE (planned)
3. **Network** - Istio mTLS STRICT, NetworkPolicies (limited), AuthorizationPolicies
4. **Application** - Pod Security Standards (partial), RBAC (basic)
5. **Data** - Secrets encryption at rest (🚧 planned), Vault (🚧 planned)
6. **Runtime** - Falco (🚧 planned), OPA/Kyverno (🚧 planned)

**Current Status**:
- ✅ **IMPLEMENTED**: TLS 1.3, Istio mTLS STRICT, Keycloak SSO, OAuth2-Proxy, basic RBAC
- ⚠️ **PARTIAL**: NetworkPolicies (only observability namespace), Pod Security Standards
- 🚧 **PLANNED**: CI/CD security scanning, etcd encryption, Vault, Falco, comprehensive NetworkPolicies

See **[TODO_SECURITY.md](./TODO_SECURITY.md)** for complete security roadmap.

---

## 🚧 Roadmap: OpenShift Deployment

**Next Phase**: Deploy to OpenShift (Staging & Production)

### What's Different in OpenShift

| Component | Kind (Local) | OpenShift (Production) |
|-----------|-------------|------------------------|
| **Ingress** | Gateway API + MetalLB | OpenShift Routes |
| **Certificates** | Self-signed (cert-manager) | Let's Encrypt |
| **Secrets** | Sealed Secrets (Git) | External Secrets Operator + Vault |
| **Pod Security** | Baseline mode | Restricted mode (SCC) |
| **NetworkPolicies** | Permissive (dev-friendly) | Strict (default-deny) |
| **Observability** | In-cluster (Grafana, Tempo) | Hybrid (in-cluster + Grafana Cloud) |
| **Encryption at Rest** | None (etcd base64 only) | FIPS-validated cryptography |

### Preparation Checklist

See **[TODO_SECURITY.md](./TODO_SECURITY.md)** for ultra-detailed implementation tasks:

**Phase 1: Foundation (P0 - Critical)** - 3-6 months:
- [ ] **CI/CD Security Scanning** - Multi-layer pipeline (Trivy, Snyk, Checkov, Kubescape, Semgrep)
- [ ] **Expand NetworkPolicies** - Default-deny + allow-specific for all namespaces
- [ ] **OpenShift SCCs** - SecurityContextConstraints for all components
- [ ] **etcd Encryption** - Secrets encrypted at rest
- [ ] **Sealed Secrets** - Encrypted secrets in Git
- [ ] **Pod Security Standards** - Baseline (Kind), Restricted (OpenShift)
- [ ] **Audit Logging** - Kubernetes API audit logs → Loki

**Phase 2: Hardening (P1 - High)** - 6-12 months:
- [ ] **External Secrets Operator + Vault** - Centralized secret management
- [ ] **Container Image Scanning** - Trivy in Tekton pipelines
- [ ] **Enhanced RBAC** - Least-privilege ServiceAccounts
- [ ] **Secret Rotation** - Automated 90-day rotation
- [ ] **Istio AuthorizationPolicies** - Layer 7 access control

**Phase 3: Production Ready (P2 - Medium)** - 12-18 months:
- [ ] **Falco** - Runtime threat detection
- [ ] **OPA/Kyverno** - Policy enforcement
- [ ] **MFA** - Keycloak multi-factor authentication
- [ ] **Rate Limiting** - Istio EnvoyFilter
- [ ] **Compliance** - SOC 2, GDPR, HIPAA readiness

**Detailed tasks, code examples, validation steps**: [TODO_SECURITY.md](./TODO_SECURITY.md)

---

## 📚 Documentation

### Core Documentation

| Document | Description |
|----------|-------------|
| **[ARCHITECTURE.md](./ARCHITECTURE.md)** | Detailed platform architecture, deployment layers, diagrams |
| **[CLAUDE.md](./CLAUDE.md)** | Development workflow, GitOps best practices, TDD approach |
| **[TODO_SECURITY.md](./TODO_SECURITY.md)** | Comprehensive security roadmap (Kind → OpenShift) |
| **[docs/README.md](./docs/README.md)** | Complete documentation index |

### Getting Started

- [Architecture Overview](docs/00-getting-started/architecture-overview.md) - Platform components and design
- [Prerequisites](docs/00-getting-started/prerequisites.md) - Required tools and setup
- [Quick Start](docs/00-getting-started/quick-start.md) - 15-minute deployment walkthrough

### Infrastructure & Platform

- [Kubernetes & Kind](docs/01-infrastructure/kubernetes.md) - Local Kubernetes with Kind
- [ArgoCD](docs/01-infrastructure/argocd.md) - GitOps deployment
- [Gateway API](docs/01-infrastructure/gateway-api.md) - HTTPRoute and TLS configuration
- [cert-manager](docs/01-infrastructure/cert-manager.md) - TLS certificate management

### Service Mesh & Security

- [Istio](docs/02-service-mesh/istio.md) - Service mesh with Gateway API and mTLS
- [Traffic Management](docs/02-service-mesh/traffic-management.md) - Routing and load balancing
- [Encryption Architecture](docs/08-security/encryption.md) - TLS 1.3 + Istio mTLS STRICT
- [Network Policies](docs/08-security/network-policies.md) - Network isolation
- [Secrets Management](docs/08-security/secrets-management.md) - Secret handling
- [Security Roadmap](docs/08-security/security-roadmap.md) - Security maturity model

### Authentication & Authorization

- [Keycloak](docs/03-authentication/keycloak.md) - SSO and identity management
- [OAuth2-Proxy](docs/03-authentication/oauth2-proxy.md) - OAuth2 authentication layer

### Observability & Monitoring

- [Distributed Tracing](docs/04-observability/distributed-tracing.md) - Tempo + Phoenix architecture
- [Grafana](docs/04-observability/grafana.md) - Metrics dashboards
- [Phoenix](docs/04-observability/phoenix.md) - LLM observability
- [Kiali](docs/04-observability/kiali.md) - Service mesh visualization
- [Prometheus](docs/04-observability/prometheus.md) - Metrics collection
- [Loki](docs/04-observability/loki.md) - Log aggregation
- [GenAI Semantic Conventions](docs/04-observability/genai-semantic-conventions.md) - AI agent tracing standards
- [Alerting Architecture](docs/04-observability/alerting-architecture.md) - Alert configuration and management
- [Adding New Alerts](docs/04-observability/ADDING_NEW_ALERTS.md) - How to add custom alerts
- [Alert Runbooks](docs/runbooks/alerts/README.md) - Troubleshooting guides for all alerts

### CI/CD & Operations

- [GitOps Workflows](docs/05-ci-cd/gitops-workflows.md) - ArgoCD and Git workflows
- [Tekton](docs/05-ci-cd/tekton.md) - CI/CD pipelines
- [CI/CD Testing](docs/CI_CD_TESTING.md) - Integration test strategy
- [Troubleshooting](docs/10-operations/troubleshooting.md) - Common issues and solutions

### AI Agents & Platform

- [Agents](docs/07-platform/agents.md) - AI agent architecture
- [Agent Import](docs/AGENT_IMPORT.md) - How to import agents via UI

---

## 🛠️ Repository Structure

```
kagenti-demo-deployment/
├── argocd/                        # ArgoCD GitOps definitions
│   ├── bootstrap/kind/           # Root Application (App-of-Apps)
│   └── applications/             # Application definitions
│       ├── base/                # Base application templates
│       ├── helm/                # Helm-based applications
│       ├── kind-local/          # Kind-specific patches
│       └── openshift/           # OpenShift patches (🚧 PLANNED)
│
├── components/                    # Reusable Kubernetes manifests
│   ├── 00-infrastructure/       # Foundation (Wave 0-5)
│   │   ├── cert-manager.yaml
│   │   ├── gateway-api-chart/
│   │   ├── istio/
│   │   ├── keycloak/
│   │   ├── oauth2-proxy/
│   │   ├── spire/
│   │   └── tekton/
│   ├── 01-platform/            # Platform services (Wave 10-15)
│   │   ├── gateway/
│   │   ├── kagenti-ui/
│   │   ├── kagenti-operator/
│   │   └── platform-operator/
│   ├── 02-observability/       # Monitoring (Wave 20)
│   │   ├── grafana/
│   │   ├── tempo/
│   │   ├── phoenix/
│   │   ├── prometheus/
│   │   ├── loki/
│   │   └── kiali/
│   ├── 03-applications/        # Applications (Wave 25-30)
│   │   └── agents/
│   └── 08-security/           # Security configs (🚧 PLANNED)
│       ├── network-policies/
│       ├── pod-security/
│       ├── rbac/
│       └── sealed-secrets/
│
├── scripts/                      # Automation scripts
│   ├── quick-redeploy.sh        # ⭐ One-command deployment
│   ├── platform-status.sh       # Platform health check
│   ├── monitor-argocd-apps.sh   # Monitor sync progress
│   ├── show-access-info.sh      # Service URLs and credentials
│   ├── kind/                    # Kind cluster setup
│   │   ├── 01-create-cluster.sh
│   │   ├── 02-install-argocd.sh
│   │   ├── 03-bootstrap-apps.sh
│   │   └── 04-load-agent-images.sh
│   └── dev/                     # Developer tools
│       ├── setup-agent-source-repo.sh
│       └── trigger-agent-builds.sh
│
├── tests/                        # Integration & validation tests
│   ├── integration/             # Component integration tests
│   └── validation/              # Platform validation tests
│
├── environments/                 # Environment overlays (🚧 LEGACY)
│   └── openshift-stage/         # OpenShift staging example
│
└── docs/                        # Documentation
    ├── 00-getting-started/
    ├── 01-infrastructure/
    ├── 02-service-mesh/
    ├── 03-authentication/
    ├── 04-observability/
    ├── 05-ci-cd/
    ├── 07-platform/
    ├── 08-security/
    ├── 09-deployment/
    ├── 10-operations/
    └── runbooks/
```

---

## 💻 Resource Requirements

### Kind (Local Development)

**Minimum**:
- CPU: 4 cores
- Memory: 8 GB RAM
- Disk: 20 GB

**Recommended**:
- CPU: 6 cores
- Memory: 12 GB RAM
- Disk: 40 GB

**Total pods**: ~35-40 (infrastructure + observability + agents)

### OpenShift (Production)

**Cluster Size** (recommended):
- Master nodes: 3x (4 vCPU, 16 GB RAM)
- Worker nodes: 5x (8 vCPU, 32 GB RAM)
- Storage: 500 GB+ (persistent volumes)

See [TODO_SECURITY.md](./TODO_SECURITY.md) for production security requirements.

---

## 🔧 Troubleshooting

### Common Issues

**Issue: Pods stuck in ImagePullBackOff**

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Verify image in Kind
docker exec kagenti-demo-control-plane crictl images | grep <image>

# Load missing images
./scripts/kind/04-load-agent-images.sh load
```

**Issue: ArgoCD app stuck OutOfSync**

```bash
# Force sync
argocd app sync <app-name> --force \
  --port-forward --port-forward-namespace argocd --grpc-web
```

**Issue: Services not accessible via Gateway**

```bash
# Check Gateway status
kubectl get gateway -A
kubectl describe gateway external-gateway -n default

# Check HTTPRoutes
kubectl get httproute -A
```

**Full troubleshooting guide**: [docs/10-operations/troubleshooting.md](./docs/10-operations/troubleshooting.md)

**Alert troubleshooting**: [docs/04-observability/ALERT_FIX_SUMMARY.md](./docs/04-observability/ALERT_FIX_SUMMARY.md)

---

## 🤝 Contributing

See [CLAUDE.md](./CLAUDE.md) for:
- Development workflow and GitOps best practices
- TDD approach with pytest integration
- How to add new components
- Branch-based development strategy
- Testing and validation procedures

**Key Principles**:
1. ✅ All changes via Git (no `kubectl apply`)
2. ✅ Test before merge (pytest integration tests)
3. ✅ Sync via ArgoCD (`argocd app sync`)
4. ✅ Validate with `./scripts/platform-status.sh`

---

## 📖 Further Reading

### Internal Documentation

- [argocd_architecture.md](./argocd_architecture.md) - ArgoCD architecture and sync waves
- [docs/08-security/encryption.md](./docs/08-security/encryption.md) - Encryption and mTLS details
- [OBSERVABILITY_ARCHITECTURE.md](./docs/OBSERVABILITY_ARCHITECTURE.md) - Dual-backend tracing architecture
- [HTTPS_ACCESS_GUIDE.md](./HTTPS_ACCESS_GUIDE.md) - Service URLs and access details
- [HTTPS_ENFORCEMENT_SUMMARY.md](./HTTPS_ENFORCEMENT_SUMMARY.md) - TLS implementation details

### External Resources

- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Istio mTLS](https://istio.io/latest/docs/concepts/security/#mutual-tls-authentication)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)

---

## 📝 License

Apache 2.0

## 🏢 Maintained By

**Kagenti Platform Team**
**Repository**: https://github.com/Ladas/kagenti-demo-deployment

---

**Status Legend**:
- ✅ **Implemented** - Ready to use
- ⚠️ **Partial** - Working but incomplete
- 🚧 **Planned** - Documented in roadmap
- 🔴 **Critical** - High priority
