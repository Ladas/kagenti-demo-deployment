# Agent Import Guide

**Last Updated**: 2025-11-18

This guide explains how to import and deploy agents in the Kagenti platform using the dynamic AgentBuild CRD pattern.

---

## Overview

Agents in the Kagenti platform are **dynamically imported** after platform deployment, NOT deployed statically via ArgoCD. This approach:

- ✅ Decouples agent lifecycle from platform lifecycle
- ✅ Enables developers to import agents from any repository
- ✅ Leverages Tekton pipelines for automated builds
- ✅ Maintains GitOps principles (AgentBuild CRDs can be in Git)
- ✅ Supports agent development without modifying platform manifests

---

## How Agent Import Works

### Architecture

```
Developer → AgentBuild CRD → Platform Operator → Tekton Pipeline → Agent Deployment
            (kubectl apply)    (watches CRDs)     (builds image)    (deploys to cluster)
```

### Components

1. **AgentBuild CRD**: Kubernetes Custom Resource that defines agent source and build configuration
2. **Platform Operator**: Watches AgentBuild CRDs and triggers Tekton pipelines
3. **Tekton Pipeline**: Clones source, builds Docker image, pushes to registry
4. **Agent Deployment**: Operator creates Deployment/Service for the agent

### AgentBuild CRD Structure

```yaml
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentBuild
metadata:
  name: weather-agent-build
  namespace: team1
  labels:
    app: weather-agent
    kagenti.io/type: agent
spec:
  mode: dev  # Pipeline template: dev, dev-local, dev-external, preprod, prod

  # Source repository configuration
  pipeline:
    namespace: kagenti-system  # Where Tekton pipelines run
    parameters:
      - name: SOURCE_URL
        value: "https://github.com/redhat-et/agent-examples.git"
      - name: SOURCE_REVISION
        value: "main"
      - name: SOURCE_CONTEXT_DIR
        value: "a2a/weather_service"

  # Build output configuration
  buildOutput:
    image: "weather-agent"
    imageTag: "latest"
    imageRegistry: "localhost:5000"  # Local registry in Kind cluster

  # Cleanup after successful build
  cleanupAfterBuild: true

  # Labels applied to the agent
  labels:
    kagenti.io/agent-name: "weather-agent"
    kagenti.io/imported-via: "script"
```

---

## Importing Agents

### Method 1: Using the Import Script (Recommended)

The `import-agents-via-ui.sh` script automates the import process:

```bash
# Basic usage
./scripts/import-agents-via-ui.sh \
  <repo-url> \
  <context-path> \
  <agent-name> \
  [namespace]

# Example: Import weather-agent
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"

# Example: Import research-agent from local fork
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples-local.git" \
  "research-agent" \
  "research-agent" \
  "team1"
```

**What the script does**:
1. Creates namespace if needed
2. Creates AgentBuild CRD
3. Monitors build progress (10-minute timeout)
4. Verifies image in registry
5. Checks agent deployment health
6. Provides next steps and debugging commands

**Environment Variables**:
```bash
# Optional configuration
BUILD_MODE=dev             # Pipeline mode (default: dev)
IMAGE_TAG=v1.0.0           # Image tag (default: latest)
REGISTRY=localhost:5000    # Registry URL (default: localhost:5000)

# Example with custom config
BUILD_MODE=preprod IMAGE_TAG=v1.0.0 ./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"
```

### Method 2: Manual AgentBuild CRD Creation

For more control, create the AgentBuild CRD manually:

```bash
# 1. Create AgentBuild manifest
cat <<EOF > agent-builds/weather-agent-build.yaml
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentBuild
metadata:
  name: weather-agent-build
  namespace: team1
spec:
  mode: dev
  pipeline:
    namespace: kagenti-system
    parameters:
      - name: SOURCE_URL
        value: "https://github.com/redhat-et/agent-examples.git"
      - name: SOURCE_REVISION
        value: "main"
      - name: SOURCE_CONTEXT_DIR
        value: "a2a/weather_service"
  buildOutput:
    image: "weather-agent"
    imageTag: "latest"
    imageRegistry: "localhost:5000"
  cleanupAfterBuild: true
EOF

# 2. Apply to cluster
kubectl apply -f agent-builds/weather-agent-build.yaml

# 3. Monitor build status
kubectl get agentbuild weather-agent-build -n team1 -w

# 4. Check build logs (if needed)
PIPELINE_RUN=$(kubectl get agentbuild weather-agent-build -n team1 \
  -o jsonpath='{.status.pipelineRun}')
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=$PIPELINE_RUN --tail=100

# 5. Verify agent deployment
kubectl get pods -n team1 -l app=weather-agent
```

---

## Build Modes

The `mode` field selects which Tekton pipeline template to use:

| Mode | Description | Use Case |
|------|-------------|----------|
| `dev` | Development build with minimal checks | Local development, quick iterations |
| `dev-local` | Development build from local source | Testing local changes |
| `dev-external` | Development build from external registry | Using pre-built base images |
| `preprod` | Pre-production build with validation | Staging environment testing |
| `prod` | Production build with full checks | Production deployments |

**Example: Production build**:
```yaml
spec:
  mode: prod
  buildOutput:
    imageTag: "v1.0.0"  # Semantic versioning for production
```

---

## Monitoring Builds

### Check Build Status

```bash
# List all AgentBuilds
kubectl get agentbuilds -A

# Check specific build status
kubectl get agentbuild <name> -n <namespace>

# Watch build progress
kubectl get agentbuild <name> -n <namespace> -w

# Detailed status
kubectl describe agentbuild <name> -n <namespace>
```

### Build Phases

| Phase | Description |
|-------|-------------|
| `Pending` | AgentBuild created, waiting for pipeline |
| `Building` | Tekton pipeline running |
| `Succeeded` | Build completed successfully, image pushed |
| `Failed` | Build failed (check logs) |

### Check Build Logs

```bash
# Get PipelineRun name
PIPELINE_RUN=$(kubectl get agentbuild <name> -n <namespace> \
  -o jsonpath='{.status.pipelineRun}')

# View all build logs
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=$PIPELINE_RUN --tail=200

# View specific task logs
kubectl logs -n kagenti-system $PIPELINE_RUN-<task-name>-pod
```

---

## Verifying Agent Deployment

### Check Agent Pods

```bash
# List agent pods
kubectl get pods -n <namespace> -l app=<agent-name>

# Check pod details
kubectl describe pod <pod-name> -n <namespace>

# View agent logs
kubectl logs -n <namespace> -l app=<agent-name> --tail=100 -f
```

### Check Agent Health

```bash
# Check deployment
kubectl get deployment <agent-name> -n <namespace>

# Check service
kubectl get service <agent-name> -n <namespace>

# Test agent endpoint (if agent has HTTP API)
kubectl run test-agent -n <namespace> \
  --image=curlimages/curl:latest \
  --restart=Never --rm -it \
  --command -- curl -s http://<agent-name>.<namespace>.svc:8000/.well-known/agent.json
```

### Check Agent in Registry

```bash
# List images in local registry (Kind cluster)
docker exec kagenti-demo-control-plane crictl images | grep <agent-name>

# Query registry API (if using remote registry)
curl http://localhost:5000/v2/<agent-name>/tags/list
```

---

## Troubleshooting

### Issue: AgentBuild Stuck in Pending

**Symptom**: AgentBuild phase stays "Pending" for >5 minutes

**Diagnosis**:
```bash
# Check operator logs
kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager --tail=100

# Check platform operator logs
kubectl logs -n kagenti-platform-operator deployment/platform-operator --tail=100

# Check if CRD is registered
kubectl get crd agentbuilds.agent.kagenti.dev
```

**Common Causes**:
- Platform operator not running
- AgentBuild CRD not installed
- RBAC permissions missing

### Issue: Build Failed

**Symptom**: AgentBuild phase is "Failed"

**Diagnosis**:
```bash
# Get failure message
kubectl get agentbuild <name> -n <namespace> -o jsonpath='{.status.message}'

# Check pipeline logs
PIPELINE_RUN=$(kubectl get agentbuild <name> -n <namespace> \
  -o jsonpath='{.status.pipelineRun}')
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=$PIPELINE_RUN --tail=200

# Check Tekton pipeline events
kubectl get events -n kagenti-system --sort-by='.lastTimestamp' | grep $PIPELINE_RUN
```

**Common Causes**:
- Source repository not accessible (404, auth failure)
- Invalid SOURCE_CONTEXT_DIR path
- Build errors in Dockerfile
- Registry push failure (permissions, network)

### Issue: Agent Pod Not Starting

**Symptom**: Build succeeded but agent pod is ImagePullBackOff or CrashLoopBackOff

**Diagnosis**:
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | grep <agent-name>

# Check if image exists in Kind
docker exec kagenti-demo-control-plane crictl images | grep <agent-name>
```

**ImagePullBackOff Solutions**:
```bash
# Verify image was pushed
kubectl get agentbuild <name> -n <namespace> -o yaml | grep imageTag

# Load image into Kind manually (if needed)
docker pull <registry>/<agent-name>:<tag>
kind load docker-image <registry>/<agent-name>:<tag> --name kagenti-demo
```

**CrashLoopBackOff Solutions**:
```bash
# Check previous container logs
kubectl logs <pod-name> -n <namespace> --previous

# Check for missing environment variables
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Environment:"

# Check for missing secrets/configmaps
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Volumes:"
```

### Issue: Webhook Certificate Validation Error

**Symptom**:
```
Error from server (InternalError): failed calling webhook "magentbuild.kb.io":
tls: failed to verify certificate: x509: certificate is not valid for any names
```

**Status**: Known platform bug - see [ISSUE_WEBHOOK_CERTIFICATE.md](../ISSUE_WEBHOOK_CERTIFICATE.md)

**Workaround**: Full platform redeployment may resolve the issue:
```bash
./scripts/quick-redeploy.sh
```

**Tracking**: Reported to kagenti-operator team

---

## Agent Requirements

For an agent to be successfully imported, the source repository must contain:

### Required Files

1. **Dockerfile**: Defines how to build the agent image
   ```dockerfile
   FROM python:3.11-slim
   WORKDIR /app
   COPY requirements.txt .
   RUN pip install --no-cache-dir -r requirements.txt
   COPY . .
   CMD ["python", "agent.py"]
   ```

2. **agent.json** (A2A agent card): Describes agent capabilities
   ```json
   {
     "name": "weather-agent",
     "version": "1.0.0",
     "description": "Provides weather information",
     "capabilities": ["weather-query", "forecast"],
     "endpoints": {
       "chat": "/agent"
     }
   }
   ```

3. **Agent code**: Main application code (e.g., `agent.py`, `main.go`)

### Optional Files

- **requirements.txt** or **package.json**: Dependencies
- **README.md**: Agent documentation
- **tests/**: Agent tests
- **.dockerignore**: Files to exclude from build

### Directory Structure Example

```
agent-examples/
└── a2a/
    └── weather_service/
        ├── Dockerfile
        ├── agent.json
        ├── agent.py
        ├── requirements.txt
        ├── tools/
        │   └── weather_api.py
        └── README.md
```

---

## Integration with quick-redeploy.sh

**PLANNED** (blocked by webhook issue): The agent import script will be integrated into `quick-redeploy.sh`:

```bash
# After platform deployment completes
echo "🤖 Importing example agents..."

# Wait for kagenti-ui to be ready
kubectl wait --for=condition=Ready pod -l app=kagenti-ui -n kagenti-system --timeout=300s

# Import weather-agent
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"

# Import research-agent
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples-local.git" \
  "research-agent" \
  "research-agent" \
  "team1"
```

**Status**: Implementation blocked by [webhook certificate issue](../ISSUE_WEBHOOK_CERTIFICATE.md)

---

## Best Practices

### Namespace Organization

```bash
# Development agents
team1, team2, team3

# Platform agents (monitoring, observability)
monitoring-agents

# Production agents
production-agents
```

### Image Tagging

```bash
# Development: Use 'latest' or feature branch names
imageTag: "latest"
imageTag: "feature-weather-api"

# Staging: Use semantic versioning with pre-release
imageTag: "v1.0.0-rc1"
imageTag: "v1.0.0-beta"

# Production: Use semantic versioning
imageTag: "v1.0.0"
imageTag: "v1.0.1"
```

### Build Cleanup

```yaml
spec:
  cleanupAfterBuild: true  # Recommended for most cases
```

**When to use `false`**:
- Debugging build failures (preserve pipeline artifacts)
- Auditing requirements (keep full build history)

---

## Advanced Topics

### Custom Pipeline Parameters

```yaml
spec:
  pipeline:
    parameters:
      - name: SOURCE_URL
        value: "https://github.com/redhat-et/agent-examples.git"
      - name: SOURCE_REVISION
        value: "feature/new-tool"  # Custom branch
      - name: SOURCE_CONTEXT_DIR
        value: "a2a/weather_service"
      - name: BUILD_ARGS
        value: "--build-arg VERSION=1.0.0"  # Docker build args
```

### Using Private Repositories

```yaml
spec:
  pipeline:
    parameters:
      - name: SOURCE_REPO_SECRET
        value: "github-token-secret"  # k8s secret with Git credentials
```

**Create secret**:
```bash
kubectl create secret generic github-token-secret \
  -n <namespace> \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-token>
```

### Multi-Agent Import

```bash
# Import multiple agents in sequence
for agent in weather-agent research-agent search-agent; do
  ./scripts/import-agents-via-ui.sh \
    "https://github.com/redhat-et/agent-examples.git" \
    "agents/${agent}" \
    "${agent}" \
    "team1"
done
```

---

## Related Documentation

- [TODO_PHASE_0_5_STATUS.md](../TODO_PHASE_0_5_STATUS.md) - Phase 0.5 progress tracking
- [ISSUE_WEBHOOK_CERTIFICATE.md](../ISSUE_WEBHOOK_CERTIFICATE.md) - Known blocker
- [TODO_monitoring_agents.md](../TODO_monitoring_agents.md) - Monitoring agents implementation plan
- [CLAUDE.md](../CLAUDE.md) - GitOps workflow and platform practices

---

## FAQ

### Q: Can I deploy agents via ArgoCD?

**A**: Agents are intentionally NOT deployed via ArgoCD to decouple agent lifecycle from platform lifecycle. However, you CAN commit AgentBuild CRDs to Git and sync them via ArgoCD if desired.

### Q: How do I update an existing agent?

**A**: Update the agent source code in Git, then trigger a rebuild:
```bash
# Option 1: Delete and recreate AgentBuild
kubectl delete agentbuild <name> -n <namespace>
./scripts/import-agents-via-ui.sh <repo> <path> <name> <namespace>

# Option 2: Update AgentBuild imageTag and force rebuild
kubectl patch agentbuild <name> -n <namespace> \
  --type merge -p '{"spec":{"buildOutput":{"imageTag":"v1.0.1"}}}'
```

### Q: Can I import agents from private repositories?

**A**: Yes, create a Kubernetes secret with Git credentials and reference it in the AgentBuild `SOURCE_REPO_SECRET` parameter (see Advanced Topics above).

### Q: How long does a build take?

**A**: Typical build time: 2-5 minutes
- Git clone: 10-30s
- Docker build: 1-3 minutes
- Registry push: 30s-1 minute
- Deployment: 30s-1 minute

### Q: Can I import agents from local directories?

**A**: Not directly. Use `mode: dev-local` and commit to a Git repository first, or use `kind load docker-image` to manually load a pre-built image.

---

**Questions or issues?** See [ISSUE_WEBHOOK_CERTIFICATE.md](../ISSUE_WEBHOOK_CERTIFICATE.md) for known blockers or create a new issue in the repository.
