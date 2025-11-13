# Agent Deployment

This directory contains Kubernetes manifests for deploying A2A (Agent-to-Agent) agents to the Kagenti platform.

## Agents

- **research-agent**: Specialized in web research and information gathering
- **code-agent**: Specialized in code generation and analysis
- **orchestrator-agent**: Orchestrates multi-agent workflows and coordination

## Local Development (Recommended)

For **local Kind development**, use the automated build/load script:

```bash
# Build images from source + load into Kind cluster
cd /path/to/kagenti-demo-deployment
./scripts/kind/04-load-agent-images.sh build

# OR load pre-built images (skip build)
./scripts/kind/04-load-agent-images.sh load
```

**What it does**:
1. Builds Docker images from `agent-examples-local/a2a/*-agent/`
2. Tags images as `localhost:5000/*-agent:v0.0.15`
3. Loads images into Kind cluster nodes

**Sync agents via ArgoCD**:
```bash
argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web
```

**Verify deployment**:
```bash
kubectl get pods -n team1
kubectl get svc -n team1
```

## Production Builds (Advanced)

For **production deployments**, use kagenti-operator + Tekton CI/CD pipeline:

1. **Create AgentBuild CR**:
   ```yaml
   apiVersion: agent.kagenti.dev/v1alpha1
   kind: AgentBuild
   metadata:
     name: research-agent-build
     namespace: team1
   spec:
     source:
       sourceRepository: "github.com/your-org/agents.git"
       sourceRevision: "main"
       sourceSubfolder: "a2a/research-agent"
       sourceCredentials:
         name: github-token-secret

     buildOutput:
       image: "research-agent"
       imageTag: "v0.0.15"
       imageRegistry: "registry.container-registry.svc.cluster.local:5000"

     pipeline:
       namespace: kagenti-system
   ```

2. **Apply the CR**:
   ```bash
   kubectl apply -f agentbuild.yaml
   ```

3. **Monitor the build**:
   ```bash
   kubectl get agentbuild research-agent-build -n team1 -w
   kubectl get pipelineruns -n kagenti-system
   ```

See [CLAUDE.md - Agent Builds via Operator](../../../CLAUDE.md#-agent-builds-via-operator) for full documentation.

## Image Override

Agent images are overridden via `kustomization.yaml`:

```yaml
images:
  - name: localhost:5000/research-agent
    newTag: v0.0.15
  - name: localhost:5000/code-agent
    newTag: v0.0.15
  - name: localhost:5000/orchestrator-agent
    newTag: v0.0.15
```

**To update versions**:
1. Build new images: `VERSION=v0.0.16 ./scripts/kind/04-load-agent-images.sh build`
2. Update `kustomization.yaml` with new tag
3. Commit and push to Git
4. Sync via ArgoCD: `argocd app sync agents`

## Testing

Run agent integration tests:

```bash
# Infrastructure tests (CRDs, API access, operator)
pytest tests/integration/test_agents.py::TestAgentOperatorInfrastructure -v

# Deployment tests (pod health, connectivity)
pytest tests/integration/test_agents.py::TestAgentDeployment -v

# Full test suite
pytest tests/integration/test_agents.py -v
```

## Troubleshooting

### ImagePullBackOff

**Symptom**: Pods show `ImagePullBackOff` status

**Cause**: Images not loaded into Kind cluster

**Fix**:
```bash
./scripts/kind/04-load-agent-images.sh load
argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web
```

### Agents Not Responding

**Symptom**: Agent pods running but not accessible

**Cause**: Missing Istio sidecar or service misconfiguration

**Fix**:
```bash
# Check sidecar injection (should show 2/2 containers)
kubectl get pods -n team1

# Check service
kubectl get svc -n team1

# Check agent card
kubectl exec -n team1 deploy/research-agent -- curl localhost:8080/.well-known/agent-card.json
```

### Build Failures

**Symptom**: Docker build fails with missing dependencies

**Cause**: Agent source code missing required files

**Fix**:
```bash
# Verify agent source directory
ls -la $AGENT_SOURCE_DIR/a2a/research-agent/

# Required files:
#   - Dockerfile
#   - agent.py
#   - requirements.txt
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kagenti Platform                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐  │
│  │ Research Agent │  │   Code Agent   │  │ Orchestrator │  │
│  │                │  │                │  │    Agent     │  │
│  │  Port: 8080    │  │  Port: 8080    │  │ Port: 8080   │  │
│  │  Protocol: A2A │  │  Protocol: A2A │  │Protocol: A2A │  │
│  └────────┬───────┘  └────────┬───────┘  └──────┬───────┘  │
│           │                   │                  │          │
│           └───────────────────┴──────────────────┘          │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │ Istio Service Mesh│                    │
│                    │   (mTLS, mTLS)    │                    │
│                    └─────────┬─────────┘                    │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │  OTEL Collector   │                    │
│                    │   (Traces, Logs)  │                    │
│                    └───────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

## Related Documentation

- **[CLAUDE.md](../../../CLAUDE.md)** - GitOps workflow and agent build process
- **[AGENT_TEST_SUMMARY.md](../../../AGENT_TEST_SUMMARY.md)** - Agent testing achievements
- **[tests/integration/test_agents.py](../../../tests/integration/test_agents.py)** - Agent integration tests
- **[docs/CI_CD_TESTING.md](../../../docs/CI_CD_TESTING.md)** - CI/CD testing strategy
