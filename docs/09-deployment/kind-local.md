# Kind Local Deployment: Development Environment Setup

**Version**: 1.0
**Last Updated**: 2025-11-13
**Status**: Production Ready
**Audience**: Developers, Platform Engineers

Complete guide to deploying the Kagenti AI Agent Platform on Kind (Kubernetes in Docker) for local development, testing, and experimentation.

---

## Table of Contents

- [Overview](#overview)
- [What is Kind?](#what-is-kind)
- [Prerequisites](#prerequisites)
- [Quick Deployment](#quick-deployment)
- [Manual Deployment](#manual-deployment)
- [Cluster Configuration](#cluster-configuration)
- [Development Workflows](#development-workflows)
- [Accessing Services](#accessing-services)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Alternatives](#alternatives)
- [Next Steps](#next-steps)
- [References](#references)

---

## Overview

**Purpose**: Deploy the complete Kagenti platform on a local Kind cluster for development, testing, and learning.

**What You Get**:
- ✅ Multi-component Kubernetes cluster (control-plane + optional workers)
- ✅ GitOps deployment via ArgoCD
- ✅ Service mesh with Istio ambient mode
- ✅ Full observability stack (Grafana, Prometheus, Tempo, Phoenix)
- ✅ Authentication with Keycloak SSO
- ✅ AI agents with A2A protocol
- ✅ Load balancer support via MetalLB
- ✅ Local development workflow (build, load, deploy)

**Deployment Time**: 15-20 minutes (automated) or 30-45 minutes (manual)

**Key Principle**: **Kind creates production-like Kubernetes clusters using Docker containers as nodes**, enabling fast, reproducible local development without the overhead of virtual machines.

**Source**: Based on [Kind Documentation](https://kind.sigs.k8s.io/docs/user/quick-start/), [Kagenti Quick Start](../00-getting-started/quick-start.md)

---

## What is Kind?

### Concept

**Kind** (Kubernetes in Docker) creates Kubernetes clusters using Docker containers as nodes.

**Why Kind?**:
- ✅ **Fast**: Cluster creation in seconds
- ✅ **Isolated**: Runs entirely in Docker, no system pollution
- ✅ **Reproducible**: Identical clusters every time
- ✅ **Multi-node**: Supports control-plane + worker nodes
- ✅ **Production-like**: Real Kubernetes, not a simplified version
- ✅ **Cleanup**: Delete cluster and all resources instantly

**How It Works**:
```
Docker Host
└── kind-control-plane (Docker container)
    └── Kubernetes cluster (kubelet, API server, etcd, etc.)
        └── Pods (Istio, ArgoCD, Grafana, etc.)
```

**Source**: [Kind Architecture](https://kind.sigs.k8s.io/docs/design/principles/)

---

### Kind vs Other Local Kubernetes

| Aspect | Kind | Minikube | k3d | Docker Desktop |
|--------|------|----------|-----|----------------|
| **Technology** | Docker containers | VM or Docker | Docker (k3s) | VM with k8s |
| **Startup Time** | <30s | 1-2min | <30s | 1-2min |
| **Multi-node** | ✅ Yes | ⚠️ Limited | ✅ Yes | ❌ Single node |
| **Resource Usage** | Low | Medium-High | Low | Medium |
| **Production Parity** | High | Medium | Medium | Medium |
| **LoadBalancer** | Via MetalLB | Built-in | Via k3s | Built-in |

**Recommendation**: **Use Kind** for Kagenti development (multi-node support, fast, production-like)

**Source**: [Kubernetes Local Development Tools](https://kubernetes.io/docs/tasks/tools/)

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| **Docker** | 20.10+ | Container runtime | [docker.com/get-docker](https://docs.docker.com/get-docker/) |
| **kubectl** | 1.28+ | Kubernetes CLI | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| **kind** | 0.20+ | Kind CLI | [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **helm** | 3.12+ | Package manager | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| **argocd** | 2.8+ | GitOps CLI | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| **jq** | 1.6+ | JSON processor | `brew install jq` (macOS) |

**Source**: [Quick Start Prerequisites](../00-getting-started/quick-start.md#prerequisites)

---

### System Requirements

**Minimum**:
- **CPU**: 4 cores
- **RAM**: 8 GB
- **Disk**: 20 GB free space
- **OS**: macOS, Linux, Windows (WSL2)

**Recommended** (for full platform):
- **CPU**: 8 cores
- **RAM**: 16 GB
- **Disk**: 40 GB free space

**Docker Resource Allocation** (macOS/Windows):
```bash
# Check Docker resources
docker info | grep -E "CPUs|Total Memory"

# Expected (minimum):
# CPUs: 4
# Total Memory: 8 GiB

# Recommended:
# CPUs: 8
# Total Memory: 16 GiB
```

**Configure Docker Resources** (Docker Desktop):
1. Open Docker Desktop → Preferences → Resources
2. Set CPUs to 8, Memory to 16 GB
3. Click "Apply & Restart"

**Source**: [Kind Requirements](https://kind.sigs.k8s.io/docs/user/quick-start/#requirements)

---

### Installation (macOS)

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install all required tools
brew install docker kubectl kind helm jq

# Install ArgoCD CLI
brew install argocd

# Verify installations
docker --version          # Docker version 20.10.x
kubectl version --client  # Client Version: v1.28.x
kind --version            # kind v0.20.x
helm version              # version.BuildInfo{Version:"v3.12.x"}
argocd version --client   # argocd: v2.8.x
jq --version             # jq-1.6
```

**Source**: [Homebrew](https://brew.sh/), [Kind Installation](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)

---

## Quick Deployment

### One-Command Deployment

For quick setup, use the automated deployment script:

```bash
# Clone repository
git clone https://github.com/Ladas/kagenti-demo-deployment.git
cd kagenti-demo-deployment

# Run automated deployment
./scripts/deploy/deploy-kind.sh
```

**What This Does** (7 steps):
1. ✅ Checks prerequisites (Docker, kubectl, kind, helm, jq)
2. ✅ Creates Kind cluster with port mappings
3. ✅ Installs Gateway API CRDs
4. ✅ Installs Istio service mesh (ambient mode)
5. ✅ Creates Istio Gateway (external-gateway)
6. ✅ Deploys all components via Kustomize
7. ✅ Validates deployment

**Duration**: 15-20 minutes

**Expected Output**:
```
🚀 Kagenti Demo Deployment - Kind Cluster
==========================================

Repository: /path/to/kagenti-demo-deployment
Cluster Name: kagenti-demo

✓ docker: /usr/local/bin/docker
✓ kubectl: /usr/local/bin/kubectl
✓ kind: /usr/local/bin/kind
✓ helm: /usr/local/bin/helm
✓ jq: /usr/local/bin/jq

▶ Step 2/7: Creating Kind cluster...
✓ Kind cluster created

▶ Step 3/7: Installing Gateway API CRDs...
✓ Gateway API CRDs installed

▶ Step 4/7: Installing Istio...
✓ Istio installed and ready

▶ Step 5/7: Creating Istio Gateway...
✓ Gateway listener ready

▶ Step 6/7: Deploying platform components...
✓ All components deployed

▶ Step 7/7: Validating deployment...
✓ Deployment validation complete

✨ Deployment successful!
```

**Source**: [scripts/deploy/deploy-kind.sh](../../scripts/deploy/deploy-kind.sh)

---

## Manual Deployment

For learning and troubleshooting, deploy step-by-step:

### Step 1: Create Kind Cluster

```bash
# Navigate to repo
cd /path/to/kagenti-demo-deployment

# Run cluster creation script
./scripts/kind/01-create-cluster.sh
```

**What This Does**:
1. Creates Kind cluster named `kagenti-demo`
2. Configures port mappings (8080 HTTP, 9443 HTTPS)
3. Installs MetalLB for LoadBalancer support
4. Configures MetalLB IP pool (172.18.200-250)

**Expected Output**:
```
🚀 Creating Kind cluster: kagenti-demo

📦 Creating Kind cluster with Istio port mappings...
Creating cluster "kagenti-demo" ...
✓ Ensuring node image (kindest/node:v1.27.3) 🖼
✓ Preparing nodes 📦
✓ Writing configuration 📜
✓ Starting control-plane 🕹️
✓ Installing CNI 🔌
✓ Installing StorageClass 💾
Set kubectl context to "kind-kagenti-demo"
✅ Kind cluster created

⏳ Waiting for cluster to be ready...
node/kagenti-demo-control-plane condition met
✅ Cluster is ready

🔧 Installing MetalLB for LoadBalancer support...
namespace/metallb-system created
✅ MetalLB installed and configured

✨ Cluster creation complete!
```

**Verify Cluster**:
```bash
# Check cluster exists
kind get clusters
# Expected: kagenti-demo

# Check nodes
kubectl get nodes
# Expected:
# NAME                         STATUS   ROLES           AGE   VERSION
# kagenti-demo-control-plane   Ready    control-plane   1m    v1.27.3

# Check MetalLB
kubectl get pods -n metallb-system
# Expected:
# NAME                          READY   STATUS    RESTARTS   AGE
# controller-xxx                1/1     Running   0          30s
# speaker-yyy                   1/1     Running   0          30s
```

**Source**: [scripts/kind/01-create-cluster.sh](../../scripts/kind/01-create-cluster.sh)

---

### Step 2: Install ArgoCD

```bash
# Run ArgoCD installation script
./scripts/kind/02-install-argocd.sh
```

**What This Does**:
1. Creates `argocd` namespace
2. Installs ArgoCD via official manifests
3. Patches ArgoCD server for insecure mode (local dev)
4. Waits for ArgoCD to be ready
5. Retrieves admin password

**Expected Output**:
```
🚀 Installing ArgoCD

📦 Creating argocd namespace...
namespace/argocd created

📥 Installing ArgoCD...
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io created
...
deployment.apps/argocd-server created
✅ ArgoCD installed

⏳ Waiting for ArgoCD to be ready...
pod/argocd-server-xxx condition met
pod/argocd-application-controller-xxx condition met
✅ ArgoCD is ready

🔑 ArgoCD admin password: AbCdEfGh1234

✨ ArgoCD installation complete!

Access ArgoCD:
  kubectl port-forward svc/argocd-server -n argocd 8080:443
  Open: https://localhost:8080
  Username: admin
  Password: AbCdEfGh1234
```

**Verify ArgoCD**:
```bash
# Check pods
kubectl get pods -n argocd
# Expected: All pods Running (argocd-server, argocd-repo-server, etc.)

# Login via CLI
argocd login localhost:8080 --insecure --username admin --password <password>

# Expected:
# 'admin:login' logged in successfully
```

**Source**: [scripts/kind/02-install-argocd.sh](../../scripts/kind/02-install-argocd.sh), [ArgoCD Guide](../01-infrastructure/argocd.md)

---

### Step 3: Bootstrap Applications

```bash
# Run bootstrap script
./scripts/kind/03-bootstrap-apps.sh
```

**What This Does**:
1. Applies root ArgoCD Application (`kagenti-apps`)
2. ArgoCD discovers and syncs all child applications
3. Applications deploy in sync wave order (0 → 25)

**Expected Output**:
```
🚀 Bootstrapping Kagenti Applications via ArgoCD

📦 Applying root application...
application.argoproj.io/kagenti-apps created
✅ Root application applied

⏳ Waiting for applications to sync...
Syncing wave 0 (infrastructure)...
Syncing wave 5 (platform)...
Syncing wave 10 (operators)...
Syncing wave 15 (platform-services)...
Syncing wave 20 (observability)...
Syncing wave 25 (agents)...
✅ All applications synced

✨ Bootstrap complete!
```

**Monitor Application Sync**:
```bash
# Watch applications sync
argocd app list --port-forward --port-forward-namespace argocd --grpc-web

# Expected:
# NAME              SYNC STATUS  HEALTH STATUS
# kagenti-apps      Synced       Healthy
# gateway-api       Synced       Healthy
# cert-manager      Synced       Healthy
# istio-base        Synced       Healthy
# istiod            Synced       Healthy
# keycloak          Synced       Healthy
# grafana           Synced       Healthy
# ...
```

**Source**: [scripts/kind/03-bootstrap-apps.sh](../../scripts/kind/03-bootstrap-apps.sh)

---

### Step 4: Deploy Agents (Optional)

For AI agent development:

```bash
# Build and load agent images
./scripts/kind/04-load-agent-images.sh build

# Sync agents via ArgoCD
argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web
```

**What This Does**:
1. Builds agent images from source (`../agent-examples-local`)
2. Tags as `localhost:5000/*-agent:v0.0.15`
3. Loads into Kind cluster
4. Syncs agent deployments via ArgoCD

**Expected Output**:
```
🚀 Building and loading agent images into Kind

Building research-agent...
[+] Building 45.2s (12/12) FINISHED
Built: localhost:5000/research-agent:v0.0.15

Building code-agent...
[+] Building 43.8s (12/12) FINISHED
Built: localhost:5000/code-agent:v0.0.15

Building orchestrator-agent...
[+] Building 47.1s (12/12) FINISHED
Built: localhost:5000/orchestrator-agent:v0.0.15

Loading images into Kind cluster...
✅ All images loaded

Sync agents via ArgoCD:
  argocd app sync agents --port-forward --grpc-web
```

**Verify Agents**:
```bash
# Check agent pods
kubectl get pods -n team1
# Expected:
# NAME                                  READY   STATUS    RESTARTS   AGE
# research-agent-xxx                    2/2     Running   0          2m
# code-agent-yyy                        2/2     Running   0          2m
# orchestrator-agent-zzz                2/2     Running   0          2m
```

**Source**: [scripts/kind/04-load-agent-images.sh](../../scripts/kind/04-load-agent-images.sh), [AI Agents Guide](../07-platform/agents.md)

---

## Cluster Configuration

### Kind Cluster Config

**File**: `kind-config.yaml` (used by scripts)

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      # HTTP - Maps host:8080 to container:30080 (Istio Gateway HTTP)
      - containerPort: 30080
        hostPort: 8080
        protocol: TCP
      # HTTPS - Maps host:9443 to container:30443 (Istio Gateway HTTPS)
      - containerPort: 30443
        hostPort: 9443
        protocol: TCP
```

**Port Mappings**:
- **8080**: HTTP traffic → Istio Gateway HTTP listener
- **9443**: HTTPS traffic → Istio Gateway HTTPS listener

**Why Port Mappings**: Allows accessing services via `localhost:8080` and `localhost:9443` from host machine.

**Source**: [Kind Configuration](https://kind.sigs.k8s.io/docs/user/configuration/)

---

### MetalLB Configuration

**MetalLB** provides LoadBalancer support for services in Kind.

**IP Address Pool**:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.200-172.18.250  # 50 IP addresses for LoadBalancer services
```

**L2 Advertisement**:
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - kind-pool
```

**How It Works**:
1. Service requests `type: LoadBalancer`
2. MetalLB assigns IP from pool (172.18.200-250)
3. L2Advertisement advertises IP on Docker network
4. Service accessible via assigned IP

**Example**:
```bash
# Check LoadBalancer service
kubectl get svc -n observability grafana
# NAME      TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)
# grafana   LoadBalancer   10.96.123.45   172.18.201     80:30123/TCP

# Access via LoadBalancer IP
curl http://172.18.201
```

**Source**: [MetalLB Documentation](https://metallb.universe.tf/), [Kind LoadBalancer](https://kind.sigs.k8s.io/docs/user/loadbalancer/)

---

## Development Workflows

### Workflow 1: Update Agent Code

**Scenario**: Modify agent code and redeploy

```bash
# 1. Edit agent source code
cd ../agent-examples-local/a2a/research-agent
vi agent.py  # Make changes

# 2. Rebuild and load image
cd /path/to/kagenti-demo-deployment
VERSION=v0.0.16 ./scripts/kind/04-load-agent-images.sh build

# 3. Update version in kustomization
vi components/03-applications/agents/kustomization.yaml
# Change: newTag: v0.0.16

# 4. Commit and sync
git add components/03-applications/agents/kustomization.yaml
git commit -m "Update research-agent to v0.0.16"
argocd app sync agents --port-forward --grpc-web

# 5. Verify deployment
kubectl get pods -n team1
kubectl logs -n team1 deploy/research-agent -c agent
```

**Source**: [AI Agents Development](../07-platform/agents.md#local-development-kind)

---

### Workflow 2: Test Configuration Changes

**Scenario**: Test Grafana datasource configuration

```bash
# 1. Edit datasource config
vi components/02-observability/grafana/datasources.yaml
# Make changes

# 2. Apply via Kustomize (test locally)
kubectl apply -k components/02-observability/grafana/overlays/kind-local

# 3. If working, commit to Git
git add components/02-observability/grafana/datasources.yaml
git commit -m "Update Grafana datasources"

# 4. Sync via ArgoCD
argocd app sync grafana --port-forward --grpc-web

# 5. Verify
kubectl port-forward -n observability svc/grafana 3000:80
# Open: http://localhost:3000
```

**Source**: [Grafana Configuration](../04-observability/grafana.md#datasource-configuration)

---

### Workflow 3: Debug Pod Issues

**Scenario**: Pod crash looping, need to debug

```bash
# 1. Check pod status
kubectl get pods -n team1 research-agent-xxx
# STATUS: CrashLoopBackOff

# 2. Check logs
kubectl logs -n team1 research-agent-xxx -c agent --previous
# (Shows logs from crashed container)

# 3. Describe pod for events
kubectl describe pod -n team1 research-agent-xxx
# Check Events section for errors

# 4. Check image loaded
kind get image-archive localhost:5000/research-agent:v0.0.15 --name kagenti-demo
# If fails: Image not loaded into Kind

# 5. Reload image
./scripts/kind/04-load-agent-images.sh load

# 6. Restart pod
kubectl rollout restart deploy/research-agent -n team1
```

**Source**: [Troubleshooting Guide](../10-operations/troubleshooting.md#pods-in-crashloopbackoff)

---

## Accessing Services

### Port-Forward Method

Access services via `kubectl port-forward`:

**Grafana**:
```bash
kubectl port-forward -n observability svc/grafana 3000:80
# Open: http://localhost:3000
# Default login: admin / <check secret>
```

**ArgoCD**:
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open: https://localhost:8080 (accept self-signed cert)
# Login: admin / <password from install>
```

**Kiali**:
```bash
kubectl port-forward -n observability svc/kiali 20001:20001
# Open: http://localhost:20001
```

**Phoenix**:
```bash
kubectl port-forward -n observability svc/phoenix 6006:6006
# Open: http://localhost:6006
```

**Tempo**:
```bash
kubectl port-forward -n observability svc/tempo 3200:3200
# Query UI: http://localhost:3200
```

**Source**: [Accessing Services](../00-getting-started/quick-start.md#accessing-services)

---

### LoadBalancer Method

For services with `type: LoadBalancer`, access via MetalLB IP:

```bash
# Get LoadBalancer IP
kubectl get svc -n observability grafana
# EXTERNAL-IP: 172.18.201

# Access directly
curl http://172.18.201
```

**Note**: LoadBalancer IPs (172.18.x.x) are only accessible from host machine, not from outside network.

---

### Ingress Method (Future)

**Not yet implemented** - requires HTTPRoute configuration with Gateway API.

**Planned**:
```bash
# Access via localhost:8080 with host header routing
curl -H "Host: grafana.localtest.me" http://localhost:8080
```

---

## Troubleshooting

### Issue: Cluster Creation Fails

**Symptoms**: `kind create cluster` fails

**Diagnosis**:
```bash
# Check Docker running
docker ps
# If error: Cannot connect to Docker daemon

# Check Docker resources
docker info | grep -E "CPUs|Total Memory"
# If < 4 CPUs or < 8 GB: Insufficient resources
```

**Fix**:
```bash
# Start Docker
open -a Docker  # macOS

# Increase Docker resources (Docker Desktop)
# Settings → Resources → CPUs: 8, Memory: 16 GB
```

**Source**: [Kind Troubleshooting](https://kind.sigs.k8s.io/docs/user/quick-start/#troubleshooting)

---

### Issue: Pods Pending (Insufficient Resources)

**Symptoms**: Pods stuck in `Pending` state

**Diagnosis**:
```bash
# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check pod events
kubectl describe pod -n team1 research-agent-xxx
# Error: Insufficient cpu
```

**Fix**:
```bash
# Option 1: Increase Docker resources
# Docker Desktop → Resources → Memory: 16 GB

# Option 2: Reduce pod resource requests
kubectl patch deploy research-agent -n team1 -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "agent",
          "resources": {
            "requests": {
              "cpu": "50m",
              "memory": "128Mi"
            }
          }
        }]
      }
    }
  }
}'
```

**Source**: [Troubleshooting - Pods Pending](../10-operations/troubleshooting.md#issue-pods-stuck-in-pending)

---

### Issue: ArgoCD Apps OutOfSync

**Symptoms**: ArgoCD shows applications as `OutOfSync`

**Diagnosis**:
```bash
# Check app status
argocd app get infrastructure --port-forward --grpc-web

# Check diff
argocd app diff infrastructure --port-forward --grpc-web
```

**Fix**:
```bash
# Sync application
argocd app sync infrastructure --port-forward --grpc-web

# Sync all applications
argocd app sync -l argocd.argoproj.io/instance=kagenti-apps --port-forward --grpc-web
```

**Source**: [ArgoCD Troubleshooting](../01-infrastructure/argocd.md#troubleshooting)

---

### Issue: Cannot Access Services

**Symptoms**: `kubectl port-forward` fails or service not accessible

**Diagnosis**:
```bash
# Check service exists
kubectl get svc -n observability grafana
# If "not found": Service not created

# Check pods running
kubectl get pods -n observability -l app=grafana
# If no pods or CrashLoopBackOff: Pod issue
```

**Fix**:
```bash
# If service missing, sync application
argocd app sync grafana --port-forward --grpc-web

# If pod failing, check logs
kubectl logs -n observability deploy/grafana
```

---

## Best Practices

### 1. Use Separate Kind Clusters for Different Projects

**✅ Good**: One cluster per project
```bash
# Create project-specific cluster
kind create cluster --name project-a
kind create cluster --name project-b

# Switch contexts
kubectl config use-context kind-project-a
```

**❌ Avoid**: Mixing multiple projects in one cluster
```bash
# All projects in one cluster (namespace collision risk)
kind create cluster --name all-projects
```

**Why**: Isolated clusters prevent resource conflicts and make cleanup easier.

---

### 2. Clean Up Regularly

**✅ Good**: Delete unused clusters
```bash
# List clusters
kind get clusters

# Delete old cluster
kind delete cluster --name old-project

# Docker cleanup
docker system prune -a
```

**❌ Avoid**: Accumulating old clusters
```bash
# Multiple abandoned clusters consuming resources
kind get clusters
# Output: project-1, project-2, old-test, demo, ...
```

**Why**: Free up disk space and Docker resources.

---

### 3. Version Agent Images

**✅ Good**: Use semantic versioning
```yaml
images:
  - name: localhost:5000/research-agent
    newTag: v0.0.15  # Explicit version
```

**❌ Avoid**: Latest tag
```yaml
images:
  - name: localhost:5000/research-agent
    newTag: latest  # Ambiguous
```

**Why**: Explicit versions enable reproducible builds and easy rollbacks.

---

### 4. Use Scripts for Repetitive Tasks

**✅ Good**: Automate common workflows
```bash
# Create helper script
cat > rebuild-agents.sh <<'EOF'
#!/bin/bash
VERSION=${1:-v0.0.15}
./scripts/kind/04-load-agent-images.sh build
argocd app sync agents --port-forward --grpc-web
EOF
chmod +x rebuild-agents.sh

# Use script
./rebuild-agents.sh v0.0.16
```

**❌ Avoid**: Manual repetitive commands
```bash
# Typing same commands repeatedly
./scripts/kind/04-load-agent-images.sh build
argocd app sync agents ...
```

---

## Alternatives

### Alternative 1: Minikube

**Process**:
- Install Minikube
- Start cluster: `minikube start`
- Deploy via kubectl/helm

**Pros**:
- ✅ Built-in addons (dashboard, metrics-server)
- ✅ Built-in LoadBalancer (`minikube tunnel`)
- ✅ Mature and stable

**Cons**:
- ❌ Slower startup (VM-based by default)
- ❌ Limited multi-node support
- ❌ Heavier resource usage

**When to Use**: Need addons, prefer GUI dashboard, single-node sufficient

**Source**: [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)

---

### Alternative 2: k3d

**Process**:
- Install k3d
- Create cluster: `k3d cluster create`
- Deploy via kubectl

**Pros**:
- ✅ Very fast startup (k3s-based)
- ✅ Built-in LoadBalancer
- ✅ Low resource usage
- ✅ Multi-node support

**Cons**:
- ❌ k3s-specific (not full Kubernetes)
- ❌ Some compatibility differences
- ❌ Less production-like

**When to Use**: Need fastest startup, minimal resources, k3s compatibility acceptable

**Source**: [k3d Documentation](https://k3d.io/)

---

### Alternative 3: Docker Desktop Kubernetes

**Process**:
- Enable Kubernetes in Docker Desktop settings
- Deploy via kubectl

**Pros**:
- ✅ No additional tools
- ✅ GUI management
- ✅ Built-in LoadBalancer

**Cons**:
- ❌ Single-node only
- ❌ Tied to Docker Desktop
- ❌ Slower than Kind
- ❌ Resource-heavy

**When to Use**: Already using Docker Desktop, need simplicity, single-node acceptable

**Source**: [Docker Desktop Kubernetes](https://docs.docker.com/desktop/kubernetes/)

---

## Next Steps

### For Development

1. **Explore ArgoCD**:
   ```bash
   kubectl port-forward -n argocd svc/argocd-server 8080:443
   # Open: https://localhost:8080
   # Explore applications, sync status, diffs
   ```

2. **Build Custom Agent**:
   ```bash
   # Create new agent in agent-examples-local
   # Build and load into Kind
   # Deploy via ArgoCD
   ```

3. **Customize Grafana Dashboards**:
   ```bash
   kubectl port-forward -n observability svc/grafana 3000:80
   # Open: http://localhost:3000
   # Create custom dashboards
   ```

### For Production

1. **Migrate to OpenShift**:
   - Review [OpenShift Migration Guide](./migration-guide.md) *(coming soon)*
   - Understand OLM vs Helm differences

2. **Harden Security**:
   - Enable Network Policies
   - Configure Sealed Secrets
   - Review [Security Roadmap](../08-security/security-roadmap.md)

3. **Set Up CI/CD**:
   - Configure Tekton Pipelines
   - Review [Tekton Guide](../05-ci-cd/tekton.md)

### Learn More

- [Quick Start Guide](../00-getting-started/quick-start.md)
- [Architecture Overview](../00-getting-started/architecture-overview.md)
- [ArgoCD GitOps](../01-infrastructure/argocd.md)
- [AI Agents Deployment](../07-platform/agents.md)

---

## References

### Official Documentation

- **Kind**: [kind.sigs.k8s.io](https://kind.sigs.k8s.io/)
- **Kubernetes**: [kubernetes.io/docs](https://kubernetes.io/docs/)
- **MetalLB**: [metallb.universe.tf](https://metallb.universe.tf/)
- **ArgoCD**: [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/)

### Community Resources

- **Kind Quick Start**: [kind.sigs.k8s.io/docs/user/quick-start](https://kind.sigs.k8s.io/docs/user/quick-start/)
- **Kind Configuration**: [kind.sigs.k8s.io/docs/user/configuration](https://kind.sigs.k8s.io/docs/user/configuration/)
- **Kind Ingress**: [kind.sigs.k8s.io/docs/user/ingress](https://kind.sigs.k8s.io/docs/user/ingress/)
- **Kind LoadBalancer**: [kind.sigs.k8s.io/docs/user/loadbalancer](https://kind.sigs.k8s.io/docs/user/loadbalancer/)

### Internal Documentation

- **Main README**: [../../README.md](../../README.md)
- **Quick Start**: [../00-getting-started/quick-start.md](../00-getting-started/quick-start.md)
- **Architecture**: [../00-getting-started/architecture-overview.md](../00-getting-started/architecture-overview.md)

### Scripts

- **Cleanup**: [scripts/kind/00-cleanup.sh](../../scripts/kind/00-cleanup.sh)
- **Create Cluster**: [scripts/kind/01-create-cluster.sh](../../scripts/kind/01-create-cluster.sh)
- **Install ArgoCD**: [scripts/kind/02-install-argocd.sh](../../scripts/kind/02-install-argocd.sh)
- **Bootstrap Apps**: [scripts/kind/03-bootstrap-apps.sh](../../scripts/kind/03-bootstrap-apps.sh)
- **Load Agents**: [scripts/kind/04-load-agent-images.sh](../../scripts/kind/04-load-agent-images.sh)

---

**Last Updated**: 2025-11-13
**Document Version**: 1.0
**Maintained By**: Platform Engineering Team
**License**: Apache 2.0
