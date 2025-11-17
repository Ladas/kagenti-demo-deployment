# Agent Builds via kagenti-operator + Tekton

This directory contains `AgentBuild` Custom Resources (CRs) that trigger operator-managed Tekton pipeline builds for agent images.

## Overview

The **operator-based build workflow** provides:
- ✅ Production-like CI/CD using Tekton Pipelines
- ✅ Automated builds triggered by AgentBuild CRs
- ✅ Source code pulled from Git repositories
- ✅ Images pushed to internal container registry
- ✅ Integrated with platform observability (traces, logs)
- ✅ No local Docker required

## Prerequisites

### 1. Infrastructure Components Deployed

Ensure the following are running (via ArgoCD):

```bash
# Check kagenti-operator
kubectl get deployment kagenti-operator-controller-manager -n kagenti-system

# Check Tekton
kubectl get deployment tekton-pipelines-controller -n tekton-pipelines

# Check container registry
kubectl get deployment registry -n container-registry
```

### 2. Agent CRDs Installed

Verify Agent CRDs are available:

```bash
kubectl get crd | grep agent.kagenti.dev
# Should show:
#   agentbuilds.agent.kagenti.dev
#   agentcards.agent.kagenti.dev
#   agents.agent.kagenti.dev
```

### 3. Agent Source Code in GitHub

Agent source code must be in a GitHub repository accessible by Tekton.

#### Setup GitHub Repository

**Option A: Use the setup script (Recommended)**

```bash
cd /path/to/kagenti-demo-deployment
./scripts/dev/setup-agent-source-repo.sh
```

The script will:
1. Check if `agent-examples` repo exists
2. Offer to create it if missing
3. Configure Git remote
4. Commit and push agent source code

**Option B: Manual setup**

```bash
# 1. Create GitHub repository
gh repo create Ladas/agent-examples --public --description "Agent source code for Kagenti platform"

# 2. Navigate to agent source directory
cd /Users/ladas/Projects/OCTO/research/agent-examples-local

# 3. Initialize Git and add remote
git init
git remote add origin https://github.com/Ladas/agent-examples.git

# 4. Commit and push
git add .
git commit -m "Initial commit: A2A agent source code"
git push -u origin main
```

### 4. GitHub Access Secret

Create a Kubernetes secret with GitHub credentials for Tekton to access the repository:

```bash
# Create GitHub Personal Access Token (PAT) with repo scope
# https://github.com/settings/tokens/new

# Create secret in team1 namespace
kubectl create secret generic github-token-secret \
  --from-literal=username=Ladas \
  --from-literal=token=<YOUR_GITHUB_PAT> \
  -n team1

# Verify secret
kubectl get secret github-token-secret -n team1
```

## Usage

### Apply AgentBuild CRs

```bash
# Apply all agent builds
kubectl apply -k components/03-applications/agents/agent-builds/

# Or apply individually
kubectl apply -f components/03-applications/agents/agent-builds/research-agent-build.yaml
```

### Monitor Builds

```bash
# Watch AgentBuild status
kubectl get agentbuild -n team1 -w

# Check Tekton PipelineRuns
kubectl get pipelineruns -n kagenti-system

# View build logs
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=<pipelinerun-name> -f

# Check operator logs
kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager -f
```

### Expected Build Flow

1. **AgentBuild CR applied** → kagenti-operator detects new CR
2. **Tekton PipelineRun created** → Pipeline pulls source from GitHub
3. **Image built** → Kaniko builds Docker image from source
4. **Image pushed** → Image pushed to internal registry
5. **AgentBuild status updated** → CR shows build completion status

### Build Artifacts

Built images are tagged and pushed to the internal registry:

```
registry.container-registry.svc.cluster.local:5000/research-agent:v0.0.15
registry.container-registry.svc.cluster.local:5000/code-agent:v0.0.15
registry.container-registry.svc.cluster.local:5000/orchestrator-agent:v0.0.15
```

### Verify Built Images

```bash
# Check images in registry
kubectl exec -n container-registry deployment/registry -- \
  ls -la /var/lib/registry/docker/registry/v2/repositories/

# Or use registry API
kubectl port-forward -n container-registry svc/registry 5000:5000
curl http://localhost:5001/v2/_catalog
curl http://localhost:5001/v2/research-agent/tags/list
```

## AgentBuild CR Structure

```yaml
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentBuild
metadata:
  name: research-agent-build
  namespace: team1
spec:
  source:
    sourceRepository: "github.com/Ladas/agent-examples.git"
    sourceRevision: "main"
    sourceSubfolder: "a2a/research-agent"
    sourceCredentials:
      name: github-token-secret

  pipeline:
    namespace: kagenti-system
    parameters:
    - name: SOURCE_REPO_SECRET
      value: github-token-secret

  buildOutput:
    image: "research-agent"
    imageTag: "v0.0.15"
    imageRegistry: "registry.container-registry.svc.cluster.local:5000"

  cleanupAfterBuild: true
  mode: dev
```

## Troubleshooting

### AgentBuild stuck in Pending

**Symptom**: `kubectl get agentbuild` shows Status: Pending

**Cause**: PipelineRun not created

**Fix**:
```bash
# Check operator logs
kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager -f

# Check AgentBuild events
kubectl describe agentbuild <name> -n team1
```

### PipelineRun fails with "git clone failed"

**Symptom**: Pipeline fails at git-clone step

**Cause**: GitHub credentials missing or incorrect

**Fix**:
```bash
# Verify secret exists
kubectl get secret github-token-secret -n team1

# Recreate secret with correct token
kubectl delete secret github-token-secret -n team1
kubectl create secret generic github-token-secret \
  --from-literal=username=Ladas \
  --from-literal=token=<VALID_GITHUB_PAT> \
  -n team1

# Retry build (delete and recreate AgentBuild CR)
kubectl delete agentbuild research-agent-build -n team1
kubectl apply -f components/03-applications/agents/agent-builds/research-agent-build.yaml
```

### Image push fails

**Symptom**: Pipeline fails at image push step

**Cause**: Container registry not accessible

**Fix**:
```bash
# Check registry is running
kubectl get pods -n container-registry

# Check registry service
kubectl get svc -n container-registry

# Test registry access from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://registry.container-registry.svc.cluster.local:5000/v2/_catalog
```

## Comparison: Operator-based vs Manual Builds

| Aspect | Operator + Tekton | Manual Docker Build |
|--------|-------------------|---------------------|
| **Speed** | Slower (5-10 min) | Faster (2-5 min) |
| **Source** | Must be in Git | Local directory OK |
| **Setup** | Complex (repo + secret) | Simple (local Docker) |
| **CI/CD** | Production-ready pipeline | Dev/test only |
| **Reproducibility** | High (Git SHA + pipeline) | Low (local changes) |
| **Observability** | Integrated (traces, logs) | Limited |
| **Best for** | Production, automated builds | Local development |

## Related Documentation

- **[CLAUDE.md](../../../../CLAUDE.md)** - GitOps workflow overview
- **[scripts/dev/setup-agent-source-repo.sh](../../../../scripts/dev/setup-agent-source-repo.sh)** - GitHub repo setup script
- **[scripts/kind/04-load-agent-images.sh](../../../../scripts/kind/04-load-agent-images.sh)** - Legacy manual build script (deprecated)
- **[kagenti-operator samples](https://github.com/Ladas/kagenti-operator/tree/fix/add-kagenti-operator-image-build/kagenti-operator/config/samples)** - More AgentBuild examples
