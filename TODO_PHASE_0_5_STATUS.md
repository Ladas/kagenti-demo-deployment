# Phase 0.5 Status: Basic Agent E2E Testing Setup

**Created**: 2025-11-18
**Priority**: CRITICAL - Blocks Phase 1 (Monitoring Agents)

## 📋 Overview

Phase 0.5 establishes a working agent deployment pipeline before building monitoring agents. This ensures the platform can reliably import, build, and deploy agents using the kagenti-ui pattern (AgentBuild CRDs + Tekton pipelines).

**See**: [TODO_monitoring_agents.md Phase 0.5](./TODO_monitoring_agents.md#phase-05-basic-agent-e2e-testing-setup-priority) for complete task breakdown.

---

## ✅ Completed Tasks

### 1. Research kagenti-ui Import API/Workflow ✅

**Status**: Complete
**Commit**: N/A (research findings documented below)

**Key Findings**:
- Kagenti-UI does **not** have a REST API for agent import
- Import pattern uses **AgentBuild CRDs** created via Kubernetes API
- Platform operator watches AgentBuild CRDs and triggers Tekton pipelines
- No authentication needed - uses kubectl with proper RBAC

**AgentBuild CRD Structure Discovered**:
```yaml
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentBuild
metadata:
  name: weather-agent-build
  namespace: team1
spec:
  mode: dev  # Pipeline template: dev, dev-local, dev-external, preprod, prod
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
```

### 2. Create Agent Import Script ✅

**Status**: Complete
**Commit**: `a178947` - :sparkles: Add agent import script via AgentBuild CRDs
**File**: `scripts/import-agents-via-ui.sh`

**Script Features**:
- Creates AgentBuild CRDs to trigger Tekton pipelines
- Monitors build progress (10-minute timeout)
- Verifies image in registry and agent deployment
- Comprehensive logging with color-coded output
- Configurable via environment variables

**Usage**:
```bash
./scripts/import-agents-via-ui.sh \
  <repo-url> \
  <context-path> \
  <agent-name> \
  [namespace]
```

**Example - Import Weather Agent**:
```bash
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"
```

**Environment Variables**:
- `BUILD_MODE`: dev, dev-local, dev-external, preprod, prod (default: dev)
- `IMAGE_TAG`: Image tag (default: latest)
- `REGISTRY`: Container registry (default: localhost:5000)

### 3. Remove Static Agents ArgoCD Application ✅

**Status**: Complete
**Commit**: `3bfdee9` - :fire: Remove static agents ArgoCD application - agents will be imported dynamically

**Changes**:
1. Removed `agents.yaml` reference from `argocd/applications/base/kustomization.yaml`
2. Moved `agents.yaml` → `argocd/applications/examples/agents.yaml.example` (preserved for reference)
3. Added comment explaining dynamic agent import workflow

**Rationale**:
- Agents are application-level concerns, not platform infrastructure
- Decouples agent lifecycle from platform lifecycle
- Enables developers to import agents from any repository without modifying GitOps manifests

---

## ❌ Blocker: Webhook Certificate Issue

### Problem

**Error**:
```
Error from server (InternalError): failed calling webhook "magentbuild.kb.io":
Post "https://kagenti-operator-webhook-service.kagenti-system.svc:443/mutate-agent-kagenti-dev-v1alpha1-agentbuild?timeout=10s":
tls: failed to verify certificate: x509: certificate is not valid for any names,
but wanted to match kagenti-operator-webhook-service.kagenti-system.svc
```

**Impact**: Cannot create AgentBuild CRDs, **blocking all agent imports**.

**Root Cause**: kagenti-operator webhook certificates are not being properly generated/validated after platform redeployment.

### Attempted Fixes

1. **Restart operator pod** ❌
   ```bash
   kubectl delete pod -n kagenti-system <kagenti-operator-pod>
   ```
   - Result: Certificate issue persisted

2. **Delete and recreate webhook configuration** ❌
   ```bash
   kubectl delete mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration
   kubectl rollout restart deployment/kagenti-operator-controller-manager -n kagenti-system
   ```
   - Result: Webhook recreated but certificate still invalid

### Possible Solutions

**Option 1: Fix Operator Deployment** (Recommended)
- Investigate kagenti-operator Helm chart or deployment manifests
- Check cert-manager integration for webhook certificate generation
- Ensure proper DNS names in certificate SANs (SubjectAlternativeNames)
- **File**: Likely in `operators/overlays/local/kagenti-operator/`

**Option 2: Temporary Workaround**
- Disable webhook validation temporarily for development
- **NOT RECOMMENDED** for production

**Option 3: Manual Certificate Fix**
- Manually generate and inject webhook certificates
- **NOT RECOMMENDED** - should be automated

### Next Steps for Fixing

1. Check kagenti-operator deployment for cert-manager annotations
2. Verify cert-manager is generating webhook certificates
3. Check certificate status: `kubectl get certificate -A`
4. Review operator logs for certificate generation errors
5. Compare with working webhook configurations (e.g., tekton, istio)

---

## ⏳ Pending Tasks

### 4. Document Webhook Certificate Issue ⏳

**Status**: In Progress
**This File**: Documents the issue comprehensively

**Next Step**: Add section to CLAUDE.md troubleshooting

### 5. Update quick-redeploy.sh 🔲

**Status**: Not Started
**File**: `scripts/quick-redeploy.sh`

**Required Changes**:
```bash
# After platform deployment completes (after monitoring or agent import step)
echo "🤖 Importing example agents..."

# Wait for kagenti-ui to be ready
kubectl wait --for=condition=Ready pod -l app=kagenti-ui -n kagenti-system --timeout=300s

# Import weather-agent
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"

# Import research-agent (if exists)
# ./scripts/import-agents-via-ui.sh \
#   "https://github.com/redhat-et/agent-examples-local.git" \
#   "research-agent" \
#   "research-agent" \
#   "team1"
```

**Blocked By**: Webhook certificate issue must be fixed first

### 6. Create E2E Tests 🔲

**Status**: Not Started
**File**: `tests/e2e/test_agent_import.py`

**Test Cases Needed**:
```python
def test_weather_agent_deployed():
    """Verify weather-agent is deployed and healthy"""
    # Check deployment exists
    # Check pod is Running
    # Check pod has 2/2 containers (app + istio sidecar)

def test_weather_agent_queryable():
    """Verify weather-agent responds to queries"""
    # Call weather-agent A2A endpoint
    # Verify agent.json response
    # Verify agent accepts chat requests

def test_research_agent_deployed():
    """Verify research-agent is deployed and healthy"""

def test_research_agent_queryable():
    """Verify research-agent can search and respond"""

def test_agent_mcp_tool_integration():
    """Verify agents can use their MCP tools"""
    # Weather agent should be able to call weather API
    # Research agent should be able to search
```

**Add to CI Workflow**:
- File: `.github/workflows/app-state-validation.yml`
- Step: "Run Agent Import Tests" (after app state validation)
- Condition: Only if platform is healthy

**Blocked By**: Webhook certificate issue must be fixed first

### 7. Create Documentation 🔲

**Status**: Not Started

**Files to Create/Update**:

1. **docs/AGENT_IMPORT.md** (New)
   - How agent import works
   - AgentBuild CRD structure
   - How to import agents
   - Tekton pipeline flow
   - Troubleshooting import failures
   - Example: Import weather-agent step-by-step

2. **CLAUDE.md Updates** (Existing)
   - Add "Agent Import" section after "Observability & Troubleshooting Guide"
   - Link to docs/AGENT_IMPORT.md
   - Add quick reference for import script usage
   - Add troubleshooting section for agent import issues

**Not Blocked**: Can be done in parallel with webhook fix

---

## 🎯 Success Criteria

Phase 0.5 is **COMPLETE** when:

1. ✅ **Webhook certificates working** - AgentBuild CRDs can be created
2. ✅ **Weather-agent imports successfully** - Via import script, builds in Tekton, deploys to cluster
3. ✅ **Weather-agent health check passes** - Pod running, istio sidecar injected, agent.json endpoint accessible
4. ✅ **Weather-agent e2e test passes** - Can respond to agent queries
5. ✅ **Research-agent imports successfully** (optional second agent)
6. ✅ **E2E tests pass in CI** - Agent import tests integrated into CI workflow
7. ✅ **Documentation complete** - CLAUDE.md updated, AGENT_IMPORT.md created

**BLOCKER**: Only #1 (webhook certificates) is currently blocking progress.

---

## 📝 Commits Summary

| Commit | Description |
|--------|-------------|
| `563436e` | :memo: Refocus monitoring agents TODO on basic agent e2e testing first |
| `a178947` | :sparkles: Add agent import script via AgentBuild CRDs |
| `3bfdee9` | :fire: Remove static agents ArgoCD application - agents will be imported dynamically |

---

## 🔗 Related Documents

- [TODO_monitoring_agents.md](./TODO_monitoring_agents.md) - Phase 0.5 detailed tasks
- [CLAUDE.md](./CLAUDE.md) - GitOps workflow and platform practices
- [scripts/import-agents-via-ui.sh](./scripts/import-agents-via-ui.sh) - Agent import script

---

## 🚀 Next Actions

**Immediate (Blocker Resolution)**:
1. ⚠️ **Fix webhook certificate issue** - See "Blocker" section above
2. Test import script after webhook fix
3. Iterate on script if needed

**After Webhook Fix**:
1. Update quick-redeploy.sh to call import script
2. Create e2e tests for agent import
3. Run full redeploy and verify agents import successfully
4. Create documentation
5. Test in CI

**Once Phase 0.5 Complete**:
- **Proceed to Phase 1** of TODO_monitoring_agents.md
- Begin building monitoring agents (metrics, trace, log analyzers)
- Implement MCP servers for observability stack
