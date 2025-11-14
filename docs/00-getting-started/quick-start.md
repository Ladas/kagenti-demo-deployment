# Quick Start: Deploy Kagenti Platform Locally

**Version**: 2.0
**Last Updated**: 2025-11-10
**Status**: Production Ready
**Audience**: Developers, Platform Engineers

Deploy the complete Kagenti AI Agent Platform on your local machine in 15 minutes.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Verification](#verification)
- [Accessing Services](#accessing-services)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)
- [References](#references)

---

## Overview

**Purpose**: Get a fully functional Kagenti platform running locally for development and testing.

**What You Get**:
- ✅ Kubernetes cluster (Kind)
- ✅ GitOps with ArgoCD
- ✅ Service mesh (Istio)
- ✅ Distributed tracing (Tempo + Phoenix)
- ✅ SSO authentication (Keycloak)
- ✅ Observability (Grafana + Prometheus + Kiali)
- ✅ CI/CD (Tekton)
- ✅ Kagenti UI and sample agents

**Time Required**: 15-20 minutes

**Source**: Based on [Kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)

---

## Prerequisites

### Required Tools

| Tool | Minimum Version | Check Command | Install |
|------|----------------|---------------|---------|
| **Docker** | 20.10+ | `docker --version` | [Install Docker](https://docs.docker.com/get-docker/) |
| **kubectl** | 1.28+ | `kubectl version --client` | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) |
| **kind** | 0.20+ | `kind --version` | [Install Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **helm** | 3.12+ | `helm version` | [Install Helm](https://helm.sh/docs/intro/install/) |
| **argocd CLI** | 2.8+ | `argocd version --client` | [Install ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |

### System Requirements

- **CPU**: 4 cores minimum (8 cores recommended)
- **RAM**: 8 GB minimum (16 GB recommended)
- **Disk**: 20 GB free space
- **OS**: macOS, Linux, or Windows with WSL2

**Source**: [Kind System Requirements](https://kind.sigs.k8s.io/docs/user/quick-start/#requirements)

### Verify Prerequisites

```bash
# Check all tools installed
docker --version && kubectl version --client && kind --version && helm version && argocd version --client

# Check Docker running
docker ps

# Expected: Docker daemon is running
```

---

## Installation

### Step 1: Deploy Platform

```bash
# Clone repository
git clone https://github.com/Ladas/kagenti-demo-deployment.git
cd kagenti-demo-deployment

# Run deployment script
./scripts/deploy/deploy-kind.sh

# Expected output:
# ✅ Kind cluster created: kind-kagenti-demo
# ✅ ArgoCD installed
# ✅ All applications synced
# ✅ Platform deployed successfully
```

**What This Does**:
1. Creates Kind cluster with ingress support
2. Installs ArgoCD
3. Deploys all platform components via GitOps
4. Configures networking and certificates

**Source**: [scripts/deploy/deploy-kind.sh](../../scripts/deploy/deploy-kind.sh)

**Duration**: 10-15 minutes (depending on internet speed)

---

### Step 2: Wait for Platform Ready

```bash
# Monitor deployment
watch kubectl get pods -A

# Wait until all pods are Running or Completed
# Ctrl+C to exit watch

# Quick health check
kubectl get pods -A | grep -vE "Running|Completed"

# Expected: No output (all pods healthy)
```

**Source**: [Kubernetes Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

---

## Verification

### Check Platform Health

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Expected: All applications show "Healthy" and "Synced"

# Check critical services
kubectl get pods -n argocd,keycloak,observability,kagenti-system,istio-system

# Expected: All pods Running (1/1)
```

### Verify Components

| Component | Namespace | Command | Expected |
|-----------|-----------|---------|----------|
| **ArgoCD** | argocd | `kubectl get pods -n argocd` | 7/7 Running |
| **Keycloak** | keycloak | `kubectl get pods -n keycloak` | 2/2 Running |
| **Istio** | istio-system | `kubectl get pods -n istio-system` | 1/1 Running |
| **Grafana** | observability | `kubectl get pods -n observability` | 1/1 Running |
| **Tempo** | observability | `kubectl get pods -n observability -l app=tempo` | 1/1 Running |
| **Phoenix** | observability | `kubectl get pods -n observability -l app=phoenix` | 1/1 Running |
| **Kagenti UI** | kagenti-system | `kubectl get pods -n kagenti-system -l app=kagenti-ui` | 1/1 Running |

**Source**: [Kubernetes Get Pods](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#viewing-finding-resources)

---

## Accessing Services

### Method 1: Port Forwarding (Recommended for Dev)

#### ArgoCD

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access: https://localhost:8080
# Username: admin
# Password: (get with command below)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Source**: [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)

#### Grafana

```bash
kubectl port-forward svc/grafana -n observability 3000:80

# Access: http://localhost:3000
# Username: admin
# Password: admin
```

**Source**: [Grafana Configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)

#### Keycloak

```bash
kubectl port-forward svc/keycloak -n keycloak 8082:8080

# Access: http://localhost:8082
# Username: admin
# Password: admin
```

**Source**: [Keycloak Server Installation](https://www.keycloak.org/server/all-config)

#### Phoenix (LLM Observability)

```bash
kubectl port-forward svc/phoenix -n observability 6006:6006

# Access: http://localhost:6006
```

**Source**: [Phoenix Documentation](https://docs.arize.com/phoenix/)

#### Kiali (Service Mesh Dashboard)

```bash
kubectl port-forward svc/kiali -n kiali-system 20001:20001

# Access: http://localhost:20001
```

**Source**: [Kiali Quick Start](https://kiali.io/docs/installation/quick-start/)

---

## Troubleshooting

### Issue: Pods Not Starting

**Symptoms**: Pods stuck in Pending, CrashLoopBackOff, or ImagePullBackOff

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -A | grep -vE "Running|Completed"

# Describe problem pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>
```

**Common Causes**:
- Insufficient resources (increase Docker resources)
- Image pull failures (check Docker Hub rate limits)
- Configuration errors (check ArgoCD app status)

**Source**: [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)

---

### Issue: Port Forward Connection Refused

**Symptoms**: `error: unable to forward port because pod is not running`

**Solution**:
```bash
# Verify pod is running
kubectl get pods -n <namespace>

# Restart port-forward
pkill -f "port-forward"
kubectl port-forward svc/<service> -n <namespace> <local-port>:<remote-port>
```

---

### Issue: ArgoCD Applications Not Syncing

**Symptoms**: Applications stuck in "OutOfSync" or "Progressing"

**Solution**:
```bash
# Check application status
argocd app list

# Sync manually
argocd app sync <app-name>

# Force refresh
argocd app sync <app-name> --force
```

**Source**: [ArgoCD Troubleshooting](https://argo-cd.readthedocs.io/en/stable/user-guide/troubleshooting/)

---

## Next Steps

### For Development

1. **Explore Observability**:
   - View [Distributed Tracing Guide](../04-observability/distributed-tracing.md)
   - Check Grafana dashboards
   - Explore Phoenix LLM traces

2. **Configure Authentication**:
   - Read [Keycloak SSO Guide](../03-authentication/keycloak.md)
   - Create users in Keycloak
   - Configure OAuth2 for services

3. **Deploy Agents**:
   - Review [Agents Guide](../07-platform/agents.md) *(coming soon)*
   - Create custom AI agents
   - Test agent interactions

### For Production Readiness

1. **Review Planning Docs**:
   - [ArgoCD Cleanup Plan](../../TODO_ARGO_CLEANUP.md)
   - [ApplicationSets Migration](../../TODO_ARGO_NEXT.md)
   - [Security Roadmap](../../old_docs/PRODUCTION_SECURITY_ROADMAP.md)

2. **Harden Security**:
   - Rotate default passwords
   - Enable mTLS STRICT mode
   - Configure network policies
   - Set up secrets management

3. **Plan Migration**:
   - Review [OpenShift Migration Guide](../09-deployment/migration-guide.md) *(coming soon)*
   - Understand [OLM vs Kubernetes](../../old_docs/OLM_ARGOCD_COMPARISON.md)

---

## References

### Official Documentation

- **Kind**: [kind.sigs.k8s.io](https://kind.sigs.k8s.io/)
- **Kubernetes**: [kubernetes.io/docs](https://kubernetes.io/docs/)
- **ArgoCD**: [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/)
- **Istio**: [istio.io/docs](https://istio.io/latest/docs/)

### Internal Documentation

- **Main README**: [../README.md](../README.md)
- **Distributed Tracing**: [../04-observability/distributed-tracing.md](../04-observability/distributed-tracing.md)
- **Keycloak SSO**: [../03-authentication/keycloak.md](../03-authentication/keycloak.md)

### Repository

- **GitHub**: [Ladas/kagenti-demo-deployment](https://github.com/Ladas/kagenti-demo-deployment)
- **Issues**: [Report Issues](https://github.com/Ladas/kagenti-demo-deployment/issues)

---

**Last Updated**: 2025-11-10
**Document Version**: 2.0
**Maintained By**: Platform Engineering Team
**License**: Apache 2.0
