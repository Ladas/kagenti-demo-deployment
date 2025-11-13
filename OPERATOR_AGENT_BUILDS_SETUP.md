# Operator-Based Agent Builds Setup Guide

**Date**: 2025-11-11
**Status**: ✅ Infrastructure Ready - GitHub Setup Required

## What Was Done

I've set up the complete infrastructure for **operator-based agent builds** using kagenti-operator + Tekton CI/CD pipelines. This replaces the manual Docker build workflow with a production-ready automated build system.

### Changes Made

#### 1. Fixed kagenti-operator CRD Deployment

**Problem**: Agent CRDs (`Agent`, `AgentBuild`, `AgentCard`) were not being deployed despite operator running.

**Root Cause**: The CRD resources were commented out in the operator's kustomization.yaml.

**Fix**: Uncommented CRD resources in `/Users/ladas/Projects/OCTO/research/ladas-kagenti-operator/kagenti-operator/config/default/kustomization.yaml`:

```yaml
resources:
- ../crd  # ← Uncommented this line
- ../rbac
- ../manager
```

**Commit**: `6aae270` in `Ladas/kagenti-operator` repo
**Result**: All 3 Agent CRDs now installed and available in cluster

#### 2. Created AgentBuild CR Manifests

Created production-ready AgentBuild CRs for all three agents:

```
components/03-applications/agents/agent-builds/
├── kustomization.yaml
├── README.md (comprehensive documentation)
├── research-agent-build.yaml
├── code-agent-build.yaml
└── orchestrator-agent-build.yaml
```

These CRs trigger Tekton pipelines to:
1. Clone agent source from GitHub
2. Build Docker images using Kaniko
3. Push to internal container registry
4. Update AgentBuild status

#### 3. Created Setup and Trigger Scripts

**`scripts/dev/setup-agent-source-repo.sh`**:
- Interactive script to create GitHub repository
- Configures Git remote
- Commits and pushes agent source code
- Creates required secrets

**`scripts/dev/trigger-agent-builds.sh`**:
- Validates prerequisites (operator, Tekton, registry, CRDs)
- Applies AgentBuild CRs
- Monitors build progress
- Shows next steps

#### 4. Deprecated Legacy Build Script

Updated `scripts/kind/04-load-agent-images.sh` with deprecation notice:
- Still available for quick local development
- Clearly marked as LEGACY
- Redirects users to new operator-based workflow

### Infrastructure Status

✅ **kagenti-operator**: Running (1/1 pods)
✅ **Tekton Pipelines**: Deployed and ready
✅ **Container Registry**: Running and accessible
✅ **Agent CRDs**: Installed (agents, agentbuilds, agentcards)

## What You Need to Do

### Step 1: Push Agent Source to GitHub

Agent source code currently exists only locally at:
```
/Users/ladas/Projects/OCTO/research/agent-examples-local
```

You need to push this to GitHub so Tekton can access it.

**Option A: Use the setup script (Recommended)**

```bash
cd /Users/ladas/Projects/OCTO/research/kagenti-demo-deployment
./scripts/dev/setup-agent-source-repo.sh
```

The script will:
1. Check if `Ladas/agent-examples` repo exists on GitHub
2. Offer to create it if missing (requires `gh` CLI)
3. Configure Git remote
4. Commit and push agent source code

**Option B: Manual GitHub setup**

```bash
# 1. Create GitHub repository
gh repo create Ladas/agent-examples --public \
  --description "Agent source code for Kagenti platform"

# 2. Navigate to agent source
cd /Users/ladas/Projects/OCTO/research/agent-examples-local

# 3. Configure Git
git init
git remote add origin https://github.com/Ladas/agent-examples.git

# 4. Commit and push
git add .
git commit -m "Initial commit: A2A agent source code

- research-agent: Web research and information gathering
- code-agent: Code generation and analysis
- orchestrator-agent: Multi-agent workflow coordination

🤖 Prepared for kagenti-operator + Tekton CI/CD builds"

git push -u origin main
```

### Step 2: Create GitHub Token Secret

Tekton needs a GitHub Personal Access Token (PAT) to clone the repository.

```bash
# 1. Create GitHub PAT (if you don't have one):
# https://github.com/settings/tokens/new
# - Scopes required: repo (Full control of private repositories)
# - Expiration: Set based on your security policy

# 2. Create Kubernetes secret
kubectl create secret generic github-token-secret \
  --from-literal=username=Ladas \
  --from-literal=token=<YOUR_GITHUB_PAT> \
  -n team1

# 3. Verify secret created
kubectl get secret github-token-secret -n team1
```

### Step 3: Trigger Agent Builds

Once GitHub repo and secret are set up:

```bash
cd /Users/ladas/Projects/OCTO/research/kagenti-demo-deployment
./scripts/dev/trigger-agent-builds.sh
```

This will:
1. Validate all prerequisites
2. Apply AgentBuild CRs
3. Monitor build progress
4. Show Tekton PipelineRuns

### Step 4: Monitor Builds

```bash
# Watch AgentBuild status
kubectl get agentbuild -n team1 -w

# Check Tekton PipelineRuns
kubectl get pipelineruns -n kagenti-system

# View build logs (replace <pipelinerun-name>)
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=<pipelinerun-name> -f

# Check operator logs
kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager -f
```

### Step 5: Deploy Built Images

Once builds complete successfully:

```bash
# Sync agents application to deploy built images
argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web

# Verify pods running with new images
kubectl get pods -n team1

# Check agent health
kubectl get pods -n team1 -l app=research-agent
```

## Expected Build Flow

```
1. Apply AgentBuild CR
   ↓
2. kagenti-operator detects CR
   ↓
3. Operator creates Tekton PipelineRun
   ↓
4. Pipeline clones source from GitHub
   ↓
5. Kaniko builds Docker image
   ↓
6. Image pushed to internal registry
   ↓
7. AgentBuild status updated
   ↓
8. Images available for deployment
```

## Built Image Tags

After successful builds, images will be available at:

```
registry.container-registry.svc.cluster.local:5000/research-agent:v0.0.15
registry.container-registry.svc.cluster.local:5000/code-agent:v0.0.15
registry.container-registry.svc.cluster.local:5000/orchestrator-agent:v0.0.15
```

## Verify Images in Registry

```bash
# Port-forward to registry
kubectl port-forward -n container-registry svc/registry 5000:5000 &

# List all images
curl http://localhost:5000/v2/_catalog

# List tags for research-agent
curl http://localhost:5000/v2/research-agent/tags/list
```

## Troubleshooting

### AgentBuild stuck in Pending

```bash
# Check operator logs
kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager -f

# Check AgentBuild events
kubectl describe agentbuild research-agent-build -n team1
```

### Git clone fails in pipeline

```bash
# Verify secret exists and is correct
kubectl get secret github-token-secret -n team1 -o yaml

# Recreate secret with correct token
kubectl delete secret github-token-secret -n team1
kubectl create secret generic github-token-secret \
  --from-literal=username=Ladas \
  --from-literal=token=<VALID_GITHUB_PAT> \
  -n team1
```

### Image push fails

```bash
# Check registry is running
kubectl get pods -n container-registry

# Test registry connectivity from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://registry.container-registry.svc.cluster.local:5000/v2/_catalog
```

## Comparison: Operator vs Manual Builds

| Aspect | Operator + Tekton | Manual Docker (LEGACY) |
|--------|-------------------|------------------------|
| **Speed** | Slower (5-10 min) | Faster (2-5 min) |
| **Source** | Must be in Git | Local directory OK |
| **Setup** | Complex (repo + secret + CRDs) | Simple (local Docker) |
| **CI/CD** | Production-ready pipeline | Dev/test only |
| **Reproducibility** | High (Git SHA + pipeline) | Low (local changes) |
| **Observability** | Full traces + logs in platform | Limited |
| **Automation** | Can trigger on Git webhooks | Manual only |
| **Best for** | Production, team collaboration | Quick local iteration |

## Documentation

- **Comprehensive Guide**: [`components/03-applications/agents/agent-builds/README.md`](components/03-applications/agents/agent-builds/README.md)
- **Setup Script**: [`scripts/dev/setup-agent-source-repo.sh`](scripts/dev/setup-agent-source-repo.sh)
- **Trigger Script**: [`scripts/dev/trigger-agent-builds.sh`](scripts/dev/trigger-agent-builds.sh)
- **Legacy Build Script**: [`scripts/kind/04-load-agent-images.sh`](scripts/kind/04-load-agent-images.sh) (deprecated)
- **GitOps Workflow**: [`CLAUDE.md`](CLAUDE.md)
- **Agent Deployment**: [`components/03-applications/agents/README.md`](components/03-applications/agents/README.md)

## Next Steps After Setup

Once agent builds are working:

1. **Update CLAUDE.md** with operator-based workflow as primary method
2. **Add to Quick Start** in CLAUDE.md (replace manual build step)
3. **Create CI/CD automation** (optional - trigger builds on Git push)
4. **Set up webhooks** (optional - auto-trigger on code changes)

## Summary

**Infrastructure Ready**: ✅
**Requires User Action**: GitHub setup + secret creation
**Time to Complete**: ~10 minutes
**Complexity**: Moderate (one-time setup)
**Benefits**: Production-ready CI/CD pipeline for agent builds

Once you complete the GitHub setup (Steps 1-2), you'll have a fully automated, reproducible, production-like build system for agent images that integrates seamlessly with the Kagenti platform's observability and GitOps workflow.
