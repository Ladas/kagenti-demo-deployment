# Prerequisites: System Requirements and Tool Installation

**Version**: 1.0
**Last Updated**: 2025-11-13
**Status**: Production Ready
**Audience**: Platform Engineers, Developers, DevOps Engineers

Complete guide to prerequisites for deploying and managing the Kagenti AI Agent Platform, including required tools, system requirements, installation instructions, and verification procedures.

---

## Table of Contents

- [Overview](#overview)
- [System Requirements](#system-requirements)
- [Required Tools](#required-tools)
- [Installation by Platform](#installation-by-platform)
- [Verification](#verification)
- [Optional Tools](#optional-tools)
- [Network Requirements](#network-requirements)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)
- [References](#references)

---

## Overview

**Purpose**: Ensure your system meets all requirements for deploying the Kagenti platform locally (Kind) or in production (OpenShift).

**What You Need**:
- ✅ Compatible operating system (macOS, Linux, Windows WSL2)
- ✅ Sufficient system resources (CPU, RAM, disk)
- ✅ Required CLI tools (Docker, kubectl, Kind, Helm, etc.)
- ✅ Network connectivity for downloading images and manifests

**Deployment Targets**:
- **Local Development**: Kind (Kubernetes in Docker)
- **Production**: OpenShift 4.12+

**Source**: Based on [Kind Requirements](https://kind.sigs.k8s.io/docs/user/quick-start/#requirements), [Kubernetes Docs](https://kubernetes.io/docs/tasks/tools/), [ArgoCD Installation](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

---

## System Requirements

### Minimum Requirements (Kind Local)

**For local Kind deployment**:

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU** | 4 cores | 8 cores | More cores = faster builds and better multi-agent performance |
| **RAM** | 8 GB | 16 GB | Platform requires ~6 GB, additional RAM for agents |
| **Disk** | 20 GB free | 40 GB free | Images, logs, and data |
| **OS** | macOS 11+, Linux, Windows 10+ | Latest stable | WSL2 required for Windows |

**Why These Requirements**:
- **4 CPU cores**: Kubernetes control plane (1 core) + platform components (2 cores) + agents (1+ cores)
- **8 GB RAM**: Kubernetes (2 GB) + ArgoCD (1 GB) + Istio (1 GB) + Observability (2 GB) + Agents (2+ GB)
- **20 GB disk**: Docker images (10 GB) + Kubernetes data (5 GB) + logs/tmp (5 GB)

**Source**: [Kind Resource Requirements](https://kind.sigs.k8s.io/docs/user/quick-start/#requirements)

---

### Docker Resource Configuration

**macOS/Windows Users**: Docker Desktop runs in a VM, must allocate resources explicitly.

**Check Current Allocation**:
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

**Configure Docker Desktop Resources**:

1. Open Docker Desktop
2. Navigate to **Settings → Resources**
3. Set:
   - **CPUs**: 8
   - **Memory**: 16 GB
   - **Swap**: 2 GB
   - **Disk image size**: 60 GB (or max available)
4. Click **Apply & Restart**

**Linux Users**: No configuration needed (Docker uses host resources directly)

**Source**: [Docker Desktop Resource Limits](https://docs.docker.com/desktop/settings/mac/#resources)

---

### Production Requirements (OpenShift)

**For OpenShift deployment**:

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **OpenShift Version** | 4.12 | 4.14+ | Platform tested on 4.12-4.14 |
| **Worker Nodes** | 3 nodes | 5+ nodes | For HA and resource distribution |
| **Node Resources** | 8 CPU / 16 GB RAM per node | 16 CPU / 32 GB RAM per node | Depends on agent workload |
| **Storage** | 100 GB per node | 200 GB+ per node | For PVCs (PostgreSQL, Grafana) |
| **Storage Class** | RWO dynamic provisioning | RWX for shared volumes | |

**Source**: [OpenShift Requirements](https://docs.openshift.com/container-platform/latest/installing/index.html)

---

## Required Tools

### Core Tools (All Deployments)

| Tool | Version | Purpose | Install Link |
|------|---------|---------|--------------|
| **Docker** | 20.10+ | Container runtime | [docker.com/get-docker](https://docs.docker.com/get-docker/) |
| **kubectl** | 1.28+ | Kubernetes CLI | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| **helm** | 3.12+ | Kubernetes package manager | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| **jq** | 1.6+ | JSON processor (for scripts) | Platform-specific (see below) |

**Source**: [Kubernetes Tools](https://kubernetes.io/docs/tasks/tools/)

---

### Local Development Tools (Kind)

| Tool | Version | Purpose | Install Link |
|------|---------|---------|--------------|
| **kind** | 0.20+ | Local Kubernetes clusters | [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **argocd** | 2.9+ | GitOps CLI | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |

**Source**: [Kind Installation](https://kind.sigs.k8s.io/docs/user/quick-start/#installation), [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

---

### Production Tools (OpenShift)

| Tool | Version | Purpose | Install Link |
|------|---------|---------|--------------|
| **oc** | 4.12+ | OpenShift CLI | [mirror.openshift.com/pub/openshift-v4/clients/ocp/](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) |
| **argocd** | 2.9+ | GitOps CLI | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| **kubeseal** | 0.24+ | Sealed Secrets (optional) | [github.com/bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets/releases) |

**Note**: `oc` includes `kubectl` functionality.

**Source**: [OpenShift CLI Tools](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)

---

## Installation by Platform

### macOS

**Using Homebrew** (recommended):

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install all required tools
brew install docker kubectl kind helm jq argocd

# Verify installations
docker --version          # Docker version 20.10.x or higher
kubectl version --client  # Client Version: v1.28.x
kind --version            # kind v0.20.x
helm version              # version.BuildInfo{Version:"v3.12.x"}
argocd version --client   # argocd: v2.9.x
jq --version             # jq-1.6
```

**Docker Desktop**:
- Download from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
- Install and start Docker Desktop
- Configure resources (see [Docker Resource Configuration](#docker-resource-configuration))

**Source**: [Homebrew](https://brew.sh/), [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)

---

### Linux

**Ubuntu/Debian**:

```bash
# Update package index
sudo apt-get update

# Install Docker
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER  # Add user to docker group
newgrp docker  # Refresh group membership

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/argocd

# Install jq
sudo apt-get install -y jq

# Verify
docker --version
kubectl version --client
kind --version
helm version
argocd version --client
jq --version
```

**RHEL/CentOS/Fedora**:

```bash
# Install Docker (Podman alternative on RHEL)
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/argocd

# Install jq
sudo dnf install -y jq
```

**Source**: [Docker Linux Install](https://docs.docker.com/engine/install/), [kubectl Install](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)

---

### Windows (WSL2)

**Prerequisites**: Windows 10/11 with WSL2 enabled

**Enable WSL2**:
```powershell
# Run in PowerShell as Administrator
wsl --install
wsl --set-default-version 2
```

**Install Ubuntu on WSL2**:
```powershell
wsl --install -d Ubuntu-22.04
```

**Install Tools in WSL2 Ubuntu**:
```bash
# Open Ubuntu terminal, then follow Linux (Ubuntu/Debian) instructions above
```

**Docker Desktop for Windows**:
- Download from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
- Enable WSL2 backend in Docker Desktop settings
- Configure resources

**Source**: [WSL2 Installation](https://docs.microsoft.com/en-us/windows/wsl/install), [Docker Desktop WSL2](https://docs.docker.com/desktop/windows/wsl/)

---

## Verification

### Verify All Tools Installed

Run this verification script:

```bash
#!/bin/bash

echo "🔍 Verifying Prerequisites..."
echo

# Check Docker
if command -v docker &> /dev/null; then
    echo "✅ Docker: $(docker --version)"
else
    echo "❌ Docker: NOT FOUND"
fi

# Check kubectl
if command -v kubectl &> /dev/null; then
    echo "✅ kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    echo "❌ kubectl: NOT FOUND"
fi

# Check kind
if command -v kind &> /dev/null; then
    echo "✅ Kind: $(kind --version)"
else
    echo "❌ Kind: NOT FOUND"
fi

# Check helm
if command -v helm &> /dev/null; then
    echo "✅ Helm: $(helm version --short)"
else
    echo "❌ Helm: NOT FOUND"
fi

# Check argocd
if command -v argocd &> /dev/null; then
    echo "✅ ArgoCD: $(argocd version --client --short 2>/dev/null | head -1)"
else
    echo "❌ ArgoCD: NOT FOUND"
fi

# Check jq
if command -v jq &> /dev/null; then
    echo "✅ jq: $(jq --version)"
else
    echo "❌ jq: NOT FOUND"
fi

echo
echo "🐳 Docker Status:"
if docker info &> /dev/null; then
    echo "✅ Docker daemon running"
    docker info | grep -E "CPUs|Total Memory"
else
    echo "❌ Docker daemon not running"
    echo "   Start Docker Desktop or run: sudo systemctl start docker"
fi
```

**Save as** `verify-prereqs.sh`, make executable, and run:
```bash
chmod +x verify-prereqs.sh
./verify-prereqs.sh
```

**Expected Output**:
```
🔍 Verifying Prerequisites...

✅ Docker: Docker version 20.10.24
✅ kubectl: Client Version: v1.28.3
✅ Kind: kind v0.20.0 go1.20.4 linux/amd64
✅ Helm: version.BuildInfo{Version:"v3.12.3"}
✅ ArgoCD: argocd: v2.9.3+6eba5be
✅ jq: jq-1.6

🐳 Docker Status:
✅ Docker daemon running
 CPUs: 8
 Total Memory: 15.63GiB
```

---

### Verify System Resources

```bash
# Check available disk space
df -h /

# Check CPU cores
nproc  # Linux
sysctl -n hw.ncpu  # macOS

# Check RAM
free -h  # Linux
sysctl hw.memsize | awk '{print $2/1024/1024/1024 " GB"}'  # macOS

# Check Docker resources (macOS/Windows)
docker info | grep -E "CPUs|Total Memory"
```

**Minimum Check**:
- Disk: At least 20 GB free on `/`
- CPU: At least 4 cores
- RAM: At least 8 GB total

---

## Optional Tools

### Development Tools

| Tool | Purpose | Install |
|------|---------|---------|
| **git** | Version control (for GitOps) | `brew install git` (macOS), `apt install git` (Linux) |
| **curl** | HTTP client (for testing) | Usually pre-installed |
| **istioctl** | Istio CLI (advanced debugging) | [istio.io/latest/docs/ops/diagnostic-tools/istioctl/](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/) |
| **k9s** | Terminal UI for Kubernetes | [k9scli.io/topics/install/](https://k9scli.io/topics/install/) |
| **stern** | Multi-pod log tailing | `brew install stern` (macOS), [github.com/stern/stern](https://github.com/stern/stern) |

**Source**: [Istio CLI](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/), [k9s](https://k9scli.io/)

---

### Code Editors

**Recommended for YAML/Markdown editing**:
- **VS Code** with extensions:
  - Kubernetes (Microsoft)
  - YAML (Red Hat)
  - GitLens
  - Markdown All in One
- **IntelliJ IDEA** with Kubernetes plugin
- **Vim/Neovim** with coc-yaml, coc-kubernetes

**Source**: [VS Code Kubernetes](https://code.visualstudio.com/docs/azure/kubernetes)

---

## Network Requirements

### Required Access

**For Local Development (Kind)**:
- ✅ Internet connectivity for:
  - Downloading container images (Docker Hub, GitHub Container Registry, Quay.io)
  - Installing Helm charts
  - Accessing Git repositories
  - Pulling Kubernetes manifests

**Firewall Rules** (if applicable):
- Allow outbound HTTPS (443) to:
  - `docker.io` (Docker Hub)
  - `github.com` (GitHub)
  - `ghcr.io` (GitHub Container Registry)
  - `quay.io` (Quay.io registry)
  - `registry.k8s.io` (Kubernetes registry)

**Corporate Proxy**: If behind corporate proxy, configure Docker proxy settings:
```bash
# Create Docker daemon config (Linux)
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

**Source**: [Docker Proxy Configuration](https://docs.docker.com/config/daemon/systemd/#httphttps-proxy)

---

### Bandwidth Requirements

**Initial Deployment**:
- **Container Images**: ~5-8 GB download
- **Time**: 15-30 minutes on 50 Mbps connection

**Recommended**: 50 Mbps+ download speed for reasonable deployment time

---

## Troubleshooting

### Issue: Docker Not Running

**Symptoms**: `Cannot connect to the Docker daemon`

**Diagnosis**:
```bash
docker info
# Error: Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Fix**:

**macOS/Windows**:
```bash
# Open Docker Desktop application
open -a Docker  # macOS
```

**Linux**:
```bash
# Start Docker daemon
sudo systemctl start docker

# Enable Docker to start on boot
sudo systemctl enable docker

# Check status
sudo systemctl status docker
```

---

### Issue: Insufficient Docker Resources

**Symptoms**: Pods stuck in `Pending` or `CrashLoopBackOff`

**Diagnosis**:
```bash
# Check Docker resources
docker info | grep -E "CPUs|Total Memory"

# If shows:
# CPUs: 2
# Total Memory: 4 GiB
# ❌ INSUFFICIENT
```

**Fix**:
1. Open Docker Desktop → Settings → Resources
2. Increase:
   - CPUs to 8
   - Memory to 16 GB
3. Apply & Restart

---

### Issue: kubectl Not Found

**Symptoms**: `kubectl: command not found`

**Fix**:

**Check PATH**:
```bash
echo $PATH
# Ensure /usr/local/bin is in PATH
```

**Add to PATH** (if needed):
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="/usr/local/bin:$PATH"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

**Reinstall kubectl**:
```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

---

### Issue: Permission Denied (Docker)

**Symptoms**: `permission denied while trying to connect to the Docker daemon socket`

**Fix** (Linux):
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Refresh group membership
newgrp docker

# Or logout and login again

# Verify
docker ps
```

**Source**: [Docker Post-Installation](https://docs.docker.com/engine/install/linux-postinstall/)

---

## Next Steps

### After Installing Prerequisites

1. **Verify All Tools**:
   ```bash
   ./verify-prereqs.sh
   ```

2. **Deploy Platform**:
   - [Quick Start Guide](./quick-start.md) - Fast automated deployment
   - [Kind Deployment Guide](../09-deployment/kind-local.md) - Detailed manual steps

3. **Learn Platform Architecture**:
   - [Architecture Overview](./architecture-overview.md)

4. **Deploy AI Agents**:
   - [AI Agents Guide](../07-platform/agents.md)

### For Production

1. **Prepare OpenShift Cluster**:
   - [OpenShift Deployment](../09-deployment/openshift-prod.md) *(coming soon)*

2. **Review Security**:
   - [Security Roadmap](../08-security/security-roadmap.md)
   - [Secrets Management](../08-security/secrets-management.md)

3. **Set Up GitOps**:
   - [GitOps Workflows](../05-ci-cd/gitops-workflows.md)

---

## References

### Official Documentation

- **Docker**: [docs.docker.com](https://docs.docker.com/)
- **Kubernetes**: [kubernetes.io/docs](https://kubernetes.io/docs/)
- **Kind**: [kind.sigs.k8s.io](https://kind.sigs.k8s.io/)
- **Helm**: [helm.sh/docs](https://helm.sh/docs/)
- **ArgoCD**: [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/)

### Installation Guides

- **Docker Install**: [docs.docker.com/get-docker](https://docs.docker.com/get-docker/)
- **kubectl Install**: [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/)
- **Kind Install**: [kind.sigs.k8s.io/docs/user/quick-start](https://kind.sigs.k8s.io/docs/user/quick-start/)
- **Helm Install**: [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/)
- **ArgoCD CLI**: [argo-cd.readthedocs.io/en/stable/cli_installation](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

### Platform-Specific

- **Homebrew** (macOS): [brew.sh](https://brew.sh/)
- **WSL2** (Windows): [docs.microsoft.com/en-us/windows/wsl/install](https://docs.microsoft.com/en-us/windows/wsl/install)

### Internal Documentation

- **Main README**: [../../README.md](../../README.md)
- **Quick Start**: [./quick-start.md](./quick-start.md)
- **Architecture**: [./architecture-overview.md](./architecture-overview.md)
- **Kind Deployment**: [../09-deployment/kind-local.md](../09-deployment/kind-local.md)

---

**Last Updated**: 2025-11-13
**Document Version**: 1.0
**Maintained By**: Platform Engineering Team
**License**: Apache 2.0
