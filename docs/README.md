# Kagenti Platform Documentation

**Version**: 2.2
**Last Updated**: 2025-11-13
**Status**: Production Ready

Welcome to the comprehensive documentation for the Kagenti AI Agent Platform - a Kubernetes-native platform for deploying and managing AI agents with full observability, GitOps, and service mesh integration.

---

## Table of Contents

- [Quick Navigation](#quick-navigation)
- [Documentation Structure](#documentation-structure)
- [Getting Started](#getting-started)
- [By Technology Stack](#by-technology-stack)
- [By Environment](#by-environment)
- [By User Role](#by-user-role)
- [Contributing](#contributing)

---

## Quick Navigation

### 🚀 New Users Start Here

1. **[Prerequisites](./00-getting-started/prerequisites.md)** - System requirements and tool installation
2. **[Quick Start Guide](./00-getting-started/quick-start.md)** - Deploy locally in 15 minutes
3. **[Architecture Overview](./00-getting-started/architecture-overview.md)** - Platform architecture and components

### 📚 Core Guides

| Guide | Description | Status |
|-------|-------------|--------|
| **[Prerequisites](./00-getting-started/prerequisites.md)** | System requirements and tool installation | ✅ Ready |
| **[Quick Start](./00-getting-started/quick-start.md)** | 15-minute local deployment | ✅ Ready |
| **[Kubernetes & Kind](./01-infrastructure/kubernetes.md)** | Local K8s development with Kind | ✅ Ready |
| **[Gateway API](./01-infrastructure/gateway-api.md)** | HTTPRoute, TLS termination, Istio integration | ✅ Ready |
| **[cert-manager](./01-infrastructure/cert-manager.md)** | Automated TLS certificate management | ✅ Ready |
| **[ArgoCD GitOps](./01-infrastructure/argocd.md)** | GitOps deployment with ApplicationSets | ✅ Ready |
| **[Istio Service Mesh](./02-service-mesh/istio.md)** | Ambient mode, Gateway API, mTLS | ✅ Ready |
| **[Traffic Management](./02-service-mesh/traffic-management.md)** | Routing, retries, circuit breaking, canary | ✅ Ready |
| **[Keycloak SSO](./03-authentication/keycloak.md)** | Authentication and identity management | ✅ Ready |
| **[OAuth2-Proxy](./03-authentication/oauth2-proxy.md)** | OAuth2 authentication proxy for services | ✅ Ready |
| **[Distributed Tracing](./04-observability/distributed-tracing.md)** | OpenTelemetry + Tempo + Phoenix setup | ✅ Ready |
| **[Phoenix](./04-observability/phoenix.md)** | LLM and AI agent observability | ✅ Ready |
| **[Kiali](./04-observability/kiali.md)** | Service mesh visualization | ✅ Ready |
| **[Grafana Dashboards](./04-observability/grafana.md)** | Metrics visualization and OIDC | ✅ Ready |
| **[Prometheus Metrics](./04-observability/prometheus.md)** | ServiceMonitor, PromQL, alerting | ✅ Ready |
| **[Korrel8r](./04-observability/korrel8r.md)** | Signal correlation engine | 📋 Planned |
| **[GenAI Conventions](./04-observability/genai-semantic-conventions.md)** | **MANDATORY for all AI agents** | ✅ Ready |
| **[AI Agents](./07-platform/agents.md)** | A2A protocol, agent deployment, orchestration | ✅ Ready |
| **[Kind Deployment](./09-deployment/kind-local.md)** | Local development environment setup | ✅ Ready |

### 🔗 Quick Links

- **Repository**: [kagenti-demo-deployment](https://github.com/Ladas/kagenti-demo-deployment)
- **Planning Docs**: [TODO_ARGO_CLEANUP.md](../TODO_ARGO_CLEANUP.md), [TODO_ARGO_NEXT.md](../TODO_ARGO_NEXT.md), [TODO_DOCS_CLEANUP.md](../TODO_DOCS_CLEANUP.md)
- **Old Documentation**: [old_docs/](../old_docs/) (reference only)

---

## Documentation Structure

Our documentation is organized by technology stack component for easy navigation:

```
docs/
├── 00-getting-started/     # Quick start, prerequisites, architecture
├── 01-infrastructure/      # ArgoCD, cert-manager, Gateway API
├── 02-service-mesh/        # Istio configuration and traffic management
├── 03-authentication/      # Keycloak, OAuth2-Proxy, RBAC
├── 04-observability/       # Tracing, Grafana, Prometheus, Kiali
├── 05-ci-cd/               # Tekton Pipelines and GitOps workflows
├── 06-operators/           # Kagenti platform and agent operators
├── 07-platform/            # Kagenti UI, agents, MCP servers
├── 08-security/            # Encryption, secrets, network policies
├── 09-deployment/          # Environment-specific deployment guides
└── 10-operations/          # Monitoring, troubleshooting, runbooks
```

---

## Getting Started

### For Local Development (Kind)

1. **Read** [Quick Start Guide](./00-getting-started/quick-start.md)
2. **Deploy** platform in 15 minutes
3. **Access** services via `localhost` port-forwards
4. **Explore** [Observability Stack](./04-observability/)

### For OpenShift Deployment

1. **Review** [OpenShift Local Setup](./09-deployment/openshift-local.md) *(coming soon)*
2. **Understand** [OLM vs Kubernetes Operators](../old_docs/OLM_ARGOCD_COMPARISON.md)
3. **Deploy** using [Migration Guide](./09-deployment/migration-guide.md) *(coming soon)*
4. **Harden** with [Security Guides](./08-security/)

---

## By Technology Stack

### Infrastructure (01-infrastructure/)

Core platform infrastructure components.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Kubernetes & Kind** | Local K8s development with Kind | [kubernetes.md](./01-infrastructure/kubernetes.md) | ✅ Ready |
| **Gateway API** | HTTPRoute, TLS termination, Istio integration | [gateway-api.md](./01-infrastructure/gateway-api.md) | ✅ Ready |
| **cert-manager** | Automated TLS certificate management and renewal | [cert-manager.md](./01-infrastructure/cert-manager.md) | ✅ Ready |
| **ArgoCD** | GitOps with App-of-Apps pattern | [argocd.md](./01-infrastructure/argocd.md) | ✅ Ready |
| **Container Registry** | Local image registry | [container-registry.md](./01-infrastructure/container-registry.md) | 🚧 Coming Soon |

**External References**:
- [Kubernetes Docs](https://kubernetes.io/docs/)
- [Argo CD Docs](https://argo-cd.readthedocs.io/)
- [cert-manager Docs](https://cert-manager.io/docs/)
- [Gateway API Docs](https://gateway-api.sigs.k8s.io/)

---

### Service Mesh (02-service-mesh/)

Istio service mesh for traffic management and security.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Istio** | Ambient mode, Gateway API, mTLS | [istio.md](./02-service-mesh/istio.md) | ✅ Ready |
| **Traffic Management** | Routing, retries, timeouts, circuit breaking | [traffic-management.md](./02-service-mesh/traffic-management.md) | ✅ Ready |

**External References**:
- [Istio Docs](https://istio.io/latest/docs/)
- [OpenShift Service Mesh 3.0](https://docs.openshift.com/container-platform/latest/service_mesh/v3x/ossm-about.html)

---

### Authentication (03-authentication/)

Identity management and authentication.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Keycloak** | SSO and identity provider | [keycloak.md](./03-authentication/keycloak.md) | ✅ Ready |
| **OAuth2-Proxy** | OAuth2 authentication proxy | [oauth2-proxy.md](./03-authentication/oauth2-proxy.md) | ✅ Ready |
| **RBAC** | Role-based access control | [rbac.md](./03-authentication/rbac.md) | 🚧 Coming Soon |

**External References**:
- [Keycloak Docs](https://www.keycloak.org/documentation)
- [OAuth2-Proxy Docs](https://oauth2-proxy.github.io/oauth2-proxy/)

---

### Observability (04-observability/)

Monitoring, metrics, logging, and distributed tracing.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Distributed Tracing** | OpenTelemetry + Tempo + Phoenix | [distributed-tracing.md](./04-observability/distributed-tracing.md) | ✅ Ready |
| **Phoenix** | LLM and AI agent observability | [phoenix.md](./04-observability/phoenix.md) | ✅ Ready |
| **Kiali** | Service mesh visualization | [kiali.md](./04-observability/kiali.md) | ✅ Ready |
| **Grafana** | Dashboards, datasources, OIDC | [grafana.md](./04-observability/grafana.md) | ✅ Ready |
| **Prometheus** | ServiceMonitor, PromQL, alerting | [prometheus.md](./04-observability/prometheus.md) | ✅ Ready |
| **Loki** | Log aggregation with LogQL | [loki.md](./04-observability/loki.md) | 📋 Planned |
| **Korrel8r** | Signal correlation engine | [korrel8r.md](./04-observability/korrel8r.md) | 📋 Planned |
| **GenAI Conventions** | **MANDATORY for all AI agents** | [genai-semantic-conventions.md](./04-observability/genai-semantic-conventions.md) | ✅ Ready |

**External References**:
- [OpenTelemetry Docs](https://opentelemetry.io/docs/)
- [OpenTelemetry GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- [Grafana Tempo Docs](https://grafana.com/docs/tempo/)
- [Arize Phoenix Docs](https://arize.com/docs/phoenix/)
- [Grafana Docs](https://grafana.com/docs/grafana/)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Loki Docs](https://grafana.com/docs/loki/)
- [Kiali Docs](https://kiali.io/docs/)

---

### CI/CD (05-ci-cd/)

Continuous integration and deployment.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Tekton** | GitHub Actions, CI/CD workflows, test automation | [tekton.md](./05-ci-cd/tekton.md) | ✅ Ready |
| **GitOps Workflows** | App-of-Apps, ApplicationSets, multi-environment deployment | [gitops-workflows.md](./05-ci-cd/gitops-workflows.md) | ✅ Ready |

**External References**:
- [Tekton Docs](https://tekton.dev/docs/)
- [OpenShift Pipelines](https://docs.openshift.com/pipelines/)

---

### Operators (06-operators/)

Kubernetes operators for platform management.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Platform Operator** | Platform-level resources | [platform-operator.md](./06-operators/platform-operator.md) | 🚧 Coming Soon |
| **Agent Operator** | Agent management | [agent-operator.md](./06-operators/agent-operator.md) | 🚧 Coming Soon |
| **CRDs** | Custom Resource Definitions | [crds.md](./06-operators/crds.md) | 🚧 Coming Soon |
| **Troubleshooting** | Operator issues | [troubleshooting.md](./06-operators/troubleshooting.md) | 🚧 Coming Soon |

**External References**:
- [Kagenti Operator Repository](https://github.com/kagenti/kagenti-operator)
- [Operator Pattern (Kubernetes)](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)

---

### Platform (07-platform/)

Kagenti platform services and AI agents.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **AI Agents** | A2A protocol, agent deployment, orchestration, observability | [agents.md](./07-platform/agents.md) | ✅ Ready |
| **Kagenti UI** | Web interface | [kagenti-ui.md](./07-platform/kagenti-ui.md) | 🚧 Coming Soon |
| **MCP Servers** | Model Context Protocol | [mcp-servers.md](./07-platform/mcp-servers.md) | 🚧 Coming Soon |

**External References**:
- [Kagenti Main Repository](https://github.com/kagenti/kagenti)
- [A2A Protocol](https://a2aprotocol.ai/)
- [Agent2Agent GitHub](https://github.com/a2aproject/A2A)

---

### Security (08-security/)

Security hardening and best practices.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Encryption** | TLS, mTLS, data-at-rest encryption | [encryption.md](./08-security/encryption.md) | ✅ Ready |
| **Security Roadmap** | Current security posture and planned enhancements | [security-roadmap.md](./08-security/security-roadmap.md) | ✅ Ready |
| **Secrets Management** | Sealed Secrets, External Secrets, Vault integration | [secrets-management.md](./08-security/secrets-management.md) | ✅ Ready |
| **Network Policies** | Default-deny, namespace isolation, pod segmentation | [network-policies.md](./08-security/network-policies.md) | ✅ Ready |

**External References**:
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [Istio Security](https://istio.io/latest/docs/concepts/security/)

---

### Deployment (09-deployment/)

Environment-specific deployment procedures.

| Environment | Description | Guide | Status |
|-------------|-------------|-------|--------|
| **Kind (Local)** | Local development with Kind clusters | [kind-local.md](./09-deployment/kind-local.md) | ✅ Ready |
| **OpenShift Local** | OpenShift CRC | [openshift-local.md](./09-deployment/openshift-local.md) | 🚧 Coming Soon |
| **OpenShift Stage** | Staging environment | [openshift-stage.md](./09-deployment/openshift-stage.md) | 🚧 Coming Soon |
| **OpenShift Prod** | Production environment | [openshift-prod.md](./09-deployment/openshift-prod.md) | 🚧 Coming Soon |
| **Migration Guide** | Kubernetes → OpenShift OLM | [migration-guide.md](./09-deployment/migration-guide.md) | 🚧 Coming Soon |

**External References**:
- [Kind Docs](https://kind.sigs.k8s.io/)
- [OpenShift Docs](https://docs.openshift.com/)
- [OpenShift Local (CRC)](https://developers.redhat.com/products/openshift-local)

---

### Operations (10-operations/)

Day-2 operations and maintenance.

| Component | Description | Guide | Status |
|-----------|-------------|-------|--------|
| **Troubleshooting** | Platform-wide issue resolution and diagnostics | [troubleshooting.md](./10-operations/troubleshooting.md) | ✅ Ready |
| **Monitoring** | Setup and alerts | [monitoring.md](./10-operations/monitoring.md) | 🚧 Coming Soon |
| **Backup & Restore** | Backup procedures | [backup-restore.md](./10-operations/backup-restore.md) | 🚧 Coming Soon |
| **Disaster Recovery** | DR procedures | [disaster-recovery.md](./10-operations/disaster-recovery.md) | 🚧 Coming Soon |

**External References**:
- [Prometheus Alerting](https://prometheus.io/docs/alerting/)
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)

---

## By Environment

### Kind (Local Development)

**Quick Deployment**:
```bash
# 1. Deploy platform
./scripts/deploy/deploy-kind.sh

# 2. Verify deployment
kubectl get pods -A

# 3. Access services
kubectl port-forward svc/grafana -n observability 3000:80
```

**Guides**:
- [Quick Start](./00-getting-started/quick-start.md) - Fast automated deployment
- [Kind Deployment](./09-deployment/kind-local.md) - Detailed setup and workflows
- [AI Agents](./07-platform/agents.md) - Agent deployment and development
- [Local Testing](./10-operations/troubleshooting.md)

---

### OpenShift (Staging/Production)

**Migration Path**:
1. Review [OLM vs Kubernetes](../old_docs/OLM_ARGOCD_COMPARISON.md)
2. Understand [OLM Configuration](../old_docs/OLM_CONFIGURATION_REALITY.md)
3. Follow [Migration Guide](./09-deployment/migration-guide.md) *(coming soon)*

**Guides**:
- [OpenShift Local](./09-deployment/openshift-local.md) *(coming soon)*
- [OpenShift Stage](./09-deployment/openshift-stage.md) *(coming soon)*
- [OpenShift Prod](./09-deployment/openshift-prod.md) *(coming soon)*

---

## By User Role

### Platform Engineers

**Essential Guides**:
1. [ArgoCD GitOps](./01-infrastructure/argocd.md) *(coming soon)*
2. [Distributed Tracing](./04-observability/distributed-tracing.md)
3. [Keycloak SSO](./03-authentication/keycloak.md)
4. [Istio Service Mesh](./02-service-mesh/istio.md) *(coming soon)*
5. [Operators](./06-operators/) *(coming soon)*

**Planning Docs**:
- [ArgoCD Cleanup Plan](../TODO_ARGO_CLEANUP.md)
- [ApplicationSets Migration](../TODO_ARGO_NEXT.md)
- [Docs Cleanup Plan](../TODO_DOCS_CLEANUP.md)

---

### SRE / Operations

**Essential Guides**:
1. [Monitoring](./10-operations/monitoring.md) *(coming soon)*
2. [Troubleshooting](./10-operations/troubleshooting.md) *(coming soon)*
3. [Backup & Restore](./10-operations/backup-restore.md) *(coming soon)*
4. [Runbooks](./10-operations/runbooks/) *(coming soon)*

**Old Docs** (for reference):
- [Platform Validation Report](../old_docs/PLATFORM-VALIDATION-REPORT.md)
- [SOP Platform Operations](../old_docs/SOP-PLATFORM-OPERATIONS.md)

---

### Developers

**Essential Guides**:
1. [Quick Start](./00-getting-started/quick-start.md)
2. [Kind Deployment](./09-deployment/kind-local.md) - Local development environment
3. [AI Agents Development](./07-platform/agents.md) - A2A protocol and agent deployment
4. [MCP Servers](./07-platform/mcp-servers.md) *(coming soon)*
5. [Troubleshooting](./10-operations/troubleshooting.md)

---

### Architects

**Essential Guides**:
1. [Architecture Overview](./00-getting-started/architecture-overview.md) *(coming soon)*
2. [Security Model](./08-security/) *(coming soon)*
3. [Deployment Strategies](./09-deployment/) *(coming soon)*

**Old Docs** (for reference):
- [Kagenti Dependencies Decomposition](../old_docs/KAGENTI_DEPS_DECOMPOSITION.md)
- [OpenShift Strategy](../old_docs/OPENSHIFT.md)

---

## Contributing

### Adding New Documentation

1. **Choose Directory**: Select appropriate directory (00-10)
2. **Follow Template**: Use [TODO_DOCS_CLEANUP.md](../TODO_DOCS_CLEANUP.md#standard-document-template)
3. **Verify Sources**: Include verified sources for every subsection
4. **Test Examples**: Ensure all code examples work
5. **Update README**: Add entry to this file

### Documentation Standards

Every document must include:
- ✅ Table of Contents
- ✅ Overview section
- ✅ Verified sources (with links)
- ✅ Configuration examples
- ✅ Troubleshooting section
- ✅ **Alternatives section**
- ✅ **Next Steps section**
- ✅ **References section**

### Verification Checklist

Before publishing:
- [ ] All links tested and working
- [ ] All code examples execute successfully
- [ ] All sources verified and current
- [ ] Spelling and grammar checked
- [ ] Cross-references are bidirectional

---

## External Resources

### Kagenti Project
- [kagenti/kagenti](https://github.com/kagenti/kagenti) - Main repository
- [kagenti/kagenti-operator](https://github.com/kagenti/kagenti-operator) - Operator repository
- [Ladas/kagenti-demo-deployment](https://github.com/Ladas/kagenti-demo-deployment) - This repository

### Kubernetes Ecosystem
- [Kubernetes](https://kubernetes.io/docs/)
- [Argo CD](https://argo-cd.readthedocs.io/)
- [Tekton](https://tekton.dev/)
- [cert-manager](https://cert-manager.io/)
- [Istio](https://istio.io/latest/docs/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)

### Observability
- [OpenTelemetry](https://opentelemetry.io/docs/)
- [Grafana Tempo](https://grafana.com/docs/tempo/)
- [Arize Phoenix](https://docs.arize.com/phoenix/)
- [Grafana](https://grafana.com/docs/grafana/)
- [Prometheus](https://prometheus.io/docs/)
- [Kiali](https://kiali.io/docs/)

### Platform Services
- [Keycloak](https://www.keycloak.org/documentation)
- [Arize Phoenix](https://arize.com/docs/phoenix/)
- [PostgreSQL](https://www.postgresql.org/docs/)

---

## Support and Feedback

### Documentation Issues

Found errors or have suggestions?
- **GitHub Issues**: [kagenti-demo-deployment/issues](https://github.com/Ladas/kagenti-demo-deployment/issues)
- **Label**: Use `documentation` label

### Questions

- **Kagenti Discussions**: [kagenti/kagenti/discussions](https://github.com/kagenti/kagenti/discussions)
- **Operator Issues**: [kagenti/kagenti-operator/issues](https://github.com/kagenti/kagenti-operator/issues)

---

## License

This documentation is licensed under [Apache License 2.0](../LICENSE).

---

**Documentation Version**: 2.2
**Last Updated**: 2025-11-13
**Maintained By**: Kagenti Platform Team
**License**: Apache 2.0
