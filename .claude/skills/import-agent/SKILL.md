---
name: import-agent
description: Import agents into the Kagenti platform - create AgentBuild CRD, monitor build progress, and troubleshoot agent deployments
---

# Import Agent Skill

## When to Use

- Importing a new agent into the platform
- Agent build failing
- Agent pod not starting
- Monitoring agent build progress

## Quick Start

```bash
# Import an agent
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
```

## How It Works

```
Developer → AgentBuild CRD → Platform Operator → Tekton Pipeline → Agent Deployment
```

1. AgentBuild CRD defines source and build config
2. Platform Operator watches CRDs, triggers Tekton
3. Tekton Pipeline clones source, builds image, pushes to registry
4. Agent Deployment operator creates Deployment/Service

## Monitor Build Progress

```bash
# Check build status
kubectl get agentbuild <name> -n <namespace>

# Watch build progress
kubectl get agentbuild <name> -n <namespace> -w

# Check build logs
PIPELINE_RUN=$(kubectl get agentbuild <name> -n <namespace> \
  -o jsonpath='{.status.pipelineRun}')
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=$PIPELINE_RUN --tail=100

# Verify agent deployment
kubectl get pods -n <namespace> -l app=<agent-name>
kubectl logs -n <namespace> -l app=<agent-name> --tail=100
```

## Build Phases

| Phase | Description |
|-------|-------------|
| Pending | Waiting for pipeline |
| Building | Tekton pipeline running |
| Succeeded | Build completed, image pushed |
| Failed | Build failed (check logs) |

## Troubleshooting

### Build Stuck in Pending

```bash
# Check operator logs
kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager --tail=100
kubectl logs -n kagenti-platform-operator deployment/platform-operator --tail=100
```

### Build Failed

```bash
# Get failure message
kubectl get agentbuild <name> -n <namespace> -o jsonpath='{.status.message}'

# Check pipeline logs
PIPELINE_RUN=$(kubectl get agentbuild <name> -n <namespace> \
  -o jsonpath='{.status.pipelineRun}')
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=$PIPELINE_RUN --tail=200
```

### Agent Pod Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | grep <agent-name>

# Check previous logs (for CrashLoopBackOff)
kubectl logs <pod-name> -n <namespace> --previous
```

## Known Issues

**Webhook certificate validation error**:
- See [ISSUE_WEBHOOK_CERTIFICATE.md](../../../ISSUE_WEBHOOK_CERTIFICATE.md)
- Error blocks AgentBuild creation

## Related Documentation

- [docs/AGENT_IMPORT.md](../../../docs/AGENT_IMPORT.md) - Full documentation
- [ISSUE_WEBHOOK_CERTIFICATE.md](../../../ISSUE_WEBHOOK_CERTIFICATE.md) - Known webhook issue

## Related Skills

- **troubleshoot-pods**: Pod troubleshooting
- **check-logs**: Query agent logs

🤖 Generated with [Claude Code](https://claude.com/claude-code)
