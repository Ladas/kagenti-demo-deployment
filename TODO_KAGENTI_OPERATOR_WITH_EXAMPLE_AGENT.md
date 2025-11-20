# Kagenti Operator Deployment & Weather Agent E2E Testing

**Goal**: Deploy the new unified `kagenti-operator` (replaces platform-operator) and successfully build/deploy the weather agent with MCP tool, connecting to Ollama, and passing E2E tests.

**Context**:
- [Issue #78](https://github.com/kagenti/kagenti-operator/issues/78) - kagenti-operator now replaces platform-operator
- kagenti-operator manages both Component CRDs (agents/tools) AND AgentBuild CRDs
- This is the path forward for full kagenti-ui integration

---

## Phase 1: Research & Understanding

### 1.1 Understand kagenti-operator Architecture

- [ ] **Read Issue #78 details**
  - What functionality moved from platform-operator to kagenti-operator?
  - Are there breaking changes in CRD schemas?
  - What's the migration path?

- [ ] **Compare CRD schemas**
  ```bash
  # Check what CRDs kagenti-operator provides
  kubectl get crd -l app.kubernetes.io/name=kagenti-operator

  # Compare Component CRD schema
  kubectl get crd components.kagenti.operator.dev -o yaml > /tmp/component-crd.yaml

  # Compare AgentBuild CRD schema
  kubectl get crd agentbuilds.agent.kagenti.dev -o yaml > /tmp/agentbuild-crd.yaml
  ```

- [ ] **Check kagenti-operator samples**
  - Location: `/Users/ladas/Projects/OCTO/research/kagenti-operator/kagenti-operator/config/samples/`
  - Review: `weather-agent.yaml` - Full Component CR example
  - Review: `components-example.yaml` - Component patterns
  - Review: `agent.yaml` - Agent-specific config

- [ ] **Understand operator functionality**
  - Does it handle Tekton pipeline creation?
  - Does it create deployments from Component CRs?
  - Does it integrate with kagenti-ui?
  - What ConfigMaps does it need (Tekton steps, environments, etc.)?

### 1.2 Verify Current Deployment State

- [ ] **Check what's currently deployed**
  ```bash
  # Check operators
  kubectl get deployment -n kagenti-system | grep operator

  # Check CRDs
  kubectl get crd | grep -E "(component|agentbuild|platform)"

  # Check if we have both operators running
  kubectl get pods -n kagenti-system -l app.kubernetes.io/name=kagenti-operator
  kubectl get pods -n kagenti-system -l app.kubernetes.io/name=platform-operator
  ```

- [ ] **Review our current kustomization**
  - File: `operators/overlays/local/kagenti-operator/kustomization.yaml`
  - File: `operators/overlays/local/platform-operator/kustomization.yaml`
  - Check: Are we deploying both? Should we remove platform-operator?

### 1.3 Identify Required ConfigMaps

- [ ] **Tekton pipeline steps** (already in `operators/overlays/local/platform-operator/tekton-steps.yaml`)
  - `github-clone-step`
  - `check-subfolder-step`
  - `kaniko-docker-build-step-local`
  - **Decision**: Do these need to move to kagenti-operator namespace or are they shared?

- [ ] **Global environments** (check if needed)
  ```bash
  kubectl get configmap -n kagenti-system global-environments
  ```

- [ ] **Pipeline templates** (check if needed)
  ```bash
  kubectl get configmap -n kagenti-system | grep pipeline-template
  ```

---

## Phase 2: Deploy kagenti-operator Only

### 2.1 Remove platform-operator

- [ ] **Update ArgoCD applications**
  - File: `argocd/applications/kind-local/platform-operator.yaml`
  - Action: Delete or add annotation to skip sync

- [ ] **Update kustomization**
  - File: `argocd/applications/kind-local/kustomization.yaml`
  - Action: Comment out platform-operator reference

- [ ] **Commit and sync**
  ```bash
  git add argocd/applications/kind-local/
  git commit -m ":fire: Remove platform-operator (replaced by kagenti-operator)"
  git push

  # Sync ArgoCD
  argocd app sync kagenti-platform-kind --port-forward --port-forward-namespace argocd --grpc-web
  ```

- [ ] **Verify removal**
  ```bash
  kubectl get deployment -n kagenti-system | grep platform-operator
  # Should return nothing
  ```

### 2.2 Ensure kagenti-operator has Required Resources

- [ ] **Move Tekton step ConfigMaps to kagenti-operator**
  - Current location: `operators/overlays/local/platform-operator/tekton-steps.yaml`
  - New location: `operators/overlays/local/kagenti-operator/tekton-steps.yaml`
  - Update: `operators/overlays/local/kagenti-operator/kustomization.yaml` to include `tekton-steps.yaml`

- [ ] **Check if global-environments ConfigMap is needed**
  - Review kagenti-operator samples
  - If needed, create in kagenti-operator overlay

- [ ] **Verify kagenti-operator deployment**
  ```bash
  kubectl get deployment kagenti-controller-manager -n kagenti-system
  kubectl logs -n kagenti-system deployment/kagenti-controller-manager --tail=50
  ```

### 2.3 Test Component CRD Creation

- [ ] **Create a minimal Component CR**
  ```yaml
  # /tmp/test-component.yaml
  apiVersion: kagenti.operator.dev/v1alpha1
  kind: Component
  metadata:
    name: test-component
    namespace: team1
  spec:
    description: "Test component to verify operator works"
    suspend: false
  ```

- [ ] **Apply and check**
  ```bash
  kubectl apply -f /tmp/test-component.yaml
  kubectl get component test-component -n team1 -o yaml
  kubectl describe component test-component -n team1
  ```

- [ ] **Check operator logs for errors**
  ```bash
  kubectl logs -n kagenti-system deployment/kagenti-controller-manager --tail=100 | grep -i error
  ```

- [ ] **Clean up test**
  ```bash
  kubectl delete component test-component -n team1
  ```

---

## Phase 3: Deploy Weather Agent via Component CR

### 3.1 Create Weather MCP Tool Component

- [ ] **Base Component CR on upstream example**
  - Reference: `/Users/ladas/Projects/OCTO/research/kagenti/kagenti/examples/components/weather_mcp.yaml`
  - Create: `components/03-applications/agents/weather-mcp-tool-component.yaml`

- [ ] **Component spec for weather-mcp-tool**
  ```yaml
  apiVersion: kagenti.operator.dev/v1alpha1
  kind: Component
  metadata:
    name: weather-mcp-tool
    namespace: team1
    labels:
      kagenti.io/type: tool
      kagenti.io/protocol: mcp
  spec:
    description: "Weather MCP tool providing weather data"

    # Build configuration
    agent:
      build:
        mode: dev-local
        pipeline:
          namespace: kagenti-system
          parameters:
            - name: SOURCE_REPO_SECRET
              value: github-token-secret
            - name: repo-url
              value: github.com/redhat-et/agent-examples
            - name: revision
              value: main
            - name: subfolder-path
              value: mcp/weather_api  # TODO: verify correct path
            - name: image
              value: localhost:5000/weather-mcp-tool:v0.0.1
          steps:
            - configMap: github-clone-step
              enabled: true
              name: github-clone
            - configMap: check-subfolder-step
              enabled: true
              name: folder-verification
            - configMap: kaniko-docker-build-step-local
              enabled: true
              name: kaniko-build

    # Deployment configuration
    deployer:
      deployAfterBuild: true
      name: weather-mcp-tool
      namespace: team1
      env:
        - name: PORT
          value: "8001"
        - name: HOST
          value: "0.0.0.0"
      kubernetes:
        imageSpec:
          image: weather-mcp-tool
          imageTag: v0.0.1
          imageRegistry: localhost:5000
          imagePullPolicy: IfNotPresent
        containerPorts:
          - containerPort: 8001
            name: http
            protocol: TCP
        servicePorts:
          - name: http
            port: 8001
            protocol: TCP
            targetPort: 8001
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi

    suspend: false
  ```

- [ ] **Verify correct source paths in agent-examples repo**
  ```bash
  # Check agent-examples structure
  ls -la /Users/ladas/Projects/OCTO/research/agent-examples/mcp/
  ls -la /Users/ladas/Projects/OCTO/research/agent-examples/a2a/weather_service/
  ```

### 3.2 Create Weather Agent Component

- [ ] **Base Component CR on upstream example**
  - Reference: `/Users/ladas/Projects/OCTO/research/kagenti/kagenti/examples/components/weather_agent.yaml`
  - Create: `components/03-applications/agents/weather-service-component.yaml`

- [ ] **Component spec for weather-service**
  ```yaml
  apiVersion: kagenti.operator.dev/v1alpha1
  kind: Component
  metadata:
    name: weather-service
    namespace: team1
    labels:
      kagenti.io/type: agent
      kagenti.io/protocol: a2a
      kagenti.io/framework: LangGraph
  spec:
    description: "Weather agent using LangGraph and MCP tools"

    # Build configuration
    agent:
      build:
        mode: dev-local
        pipeline:
          namespace: kagenti-system
          parameters:
            - name: SOURCE_REPO_SECRET
              value: github-token-secret
            - name: repo-url
              value: github.com/redhat-et/agent-examples
            - name: revision
              value: main
            - name: subfolder-path
              value: a2a/weather_service
            - name: image
              value: localhost:5000/weather-service:v0.0.1
          steps:
            - configMap: github-clone-step
              enabled: true
              name: github-clone
            - configMap: check-subfolder-step
              enabled: true
              name: folder-verification
            - configMap: kaniko-docker-build-step-local
              enabled: true
              name: kaniko-build

    # Deployment configuration
    deployer:
      deployAfterBuild: true
      name: weather-service
      namespace: team1
      env:
        # Server config
        - name: PORT
          value: "8000"
        - name: HOST
          value: "0.0.0.0"
        - name: UV_CACHE_DIR
          value: "/app/.cache/uv"

        # LLM config (Ollama)
        - name: LLM_API_BASE
          value: "http://ollama.kagenti-system.svc.cluster.local:11434/v1"
        - name: LLM_MODEL
          value: "qwen2.5:7b"
        - name: LLM_API_KEY
          value: "not-needed"

        # MCP tool
        - name: MCP_URL
          value: "http://weather-mcp-tool.team1.svc.cluster.local:8001/mcp"
        - name: MCP_TRANSPORT
          value: "streamable_http"

        # Observability
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.observability.svc.cluster.local:4317"
        - name: OTEL_SERVICE_NAME
          value: "weather-service"
        - name: PHOENIX_PROJECT_NAME
          value: "team1-agents"

      kubernetes:
        imageSpec:
          image: weather-service
          imageTag: v0.0.1
          imageRegistry: localhost:5000
          imagePullPolicy: IfNotPresent
        containerPorts:
          - containerPort: 8000
            name: a2a
            protocol: TCP
        servicePorts:
          - name: a2a
            port: 8000
            protocol: TCP
            targetPort: 8000
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        volumeMounts:
          - mountPath: /app/.cache
            name: cache
        volumes:
          - name: cache
            emptyDir: {}

    suspend: false
  ```

### 3.3 Deploy Components via GitOps

- [ ] **Remove old static agent manifests**
  - Delete: `components/03-applications/agents/weather-service.yaml`
  - Delete: `components/03-applications/agents/weather-mcp-tool.yaml`
  - Delete: `components/03-applications/agents/agent-builds/*` (replaced by Component CRs)

- [ ] **Update kustomization**
  - File: `components/03-applications/agents/kustomization.yaml`
  - Add: `weather-mcp-tool-component.yaml`
  - Add: `weather-service-component.yaml`
  - Remove: Old static manifests

- [ ] **Commit and push**
  ```bash
  git add components/03-applications/agents/
  git add operators/overlays/local/kagenti-operator/
  git commit -m ":rocket: Migrate to Component CRDs with kagenti-operator"
  git push
  ```

- [ ] **Sync ArgoCD**
  ```bash
  argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web
  ```

### 3.4 Monitor Component Build & Deployment

- [ ] **Watch Component status**
  ```bash
  # Watch weather-mcp-tool
  kubectl get component weather-mcp-tool -n team1 -w

  # Watch weather-service
  kubectl get component weather-service -n team1 -w
  ```

- [ ] **Check build progress**
  ```bash
  # Check if PipelineRuns are created
  kubectl get pipelinerun -n kagenti-system --sort-by=.metadata.creationTimestamp

  # Watch specific PipelineRun
  kubectl get pipelinerun <name> -n kagenti-system -w

  # Check logs
  kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=<name> --tail=100 -f
  ```

- [ ] **Verify deployments created**
  ```bash
  # Check deployments
  kubectl get deployment -n team1

  # Check pods
  kubectl get pods -n team1

  # Check services
  kubectl get svc -n team1
  ```

- [ ] **Troubleshoot if needed**
  ```bash
  # Check Component status
  kubectl describe component weather-service -n team1

  # Check operator logs
  kubectl logs -n kagenti-system deployment/kagenti-controller-manager --tail=200 | grep weather

  # Check pod logs
  kubectl logs -n team1 -l app=weather-service --tail=100
  ```

---

## Phase 4: E2E Testing

### 4.1 Infrastructure Tests

- [ ] **Test Ollama connectivity**
  ```bash
  pytest tests/e2e/test_weather_agent_e2e.py::TestWeatherAgentInfrastructure::test_ollama_service_healthy -v
  pytest tests/e2e/test_weather_agent_e2e.py::TestWeatherAgentInfrastructure::test_ollama_has_qwen_model -v
  ```

- [ ] **Test MCP tool deployment**
  ```bash
  pytest tests/e2e/test_weather_agent_e2e.py::TestWeatherAgentInfrastructure::test_weather_tool_deployed -v
  ```

- [ ] **Test agent deployment**
  ```bash
  pytest tests/e2e/test_weather_agent_e2e.py::TestWeatherAgentInfrastructure::test_weather_agent_deployed -v
  ```

### 4.2 Functional Tests

- [ ] **Test MCP tool endpoint**
  ```bash
  pytest tests/e2e/test_weather_agent_e2e.py::TestWeatherAgentFunctionality::test_weather_tool_health -v
  ```

- [ ] **Test agent A2A endpoint**
  ```bash
  pytest tests/e2e/test_weather_agent_e2e.py::TestWeatherAgentFunctionality::test_weather_agent_health -v
  ```

- [ ] **Test end-to-end weather query**
  ```bash
  pytest tests/e2e/test_weather_agent_e2e.py::TestWeatherAgentFunctionality::test_weather_query_san_francisco -v
  ```

### 4.3 Full Test Suite

- [ ] **Run all weather agent tests**
  ```bash
  pytest tests/e2e/test_weather_agent_e2e.py -v
  ```

- [ ] **Verify in CI**
  ```bash
  # Push changes and check CI
  git push

  # Monitor CI run
  gh run list --repo redhat-et/kagenti-demo-deployment --branch <branch> --limit 1
  gh run watch <run-id> --repo redhat-et/kagenti-demo-deployment
  ```

---

## Phase 5: kagenti-operator vs platform-operator Analysis

### 5.1 Feature Comparison

- [ ] **Document what kagenti-operator provides**
  - Component CRD reconciliation
  - AgentBuild CRD reconciliation (if applicable)
  - Tekton pipeline creation
  - Deployment creation from Component spec
  - Service creation from Component spec
  - UI integration capabilities

- [ ] **Document what platform-operator provided**
  - What CRDs did it manage?
  - What functionality is now in kagenti-operator?
  - Are there any features NOT migrated yet?

- [ ] **Identify gaps (if any)**
  - Missing functionality
  - Breaking changes
  - Migration issues

### 5.2 UI Integration

- [ ] **Check kagenti-ui compatibility**
  - Does kagenti-ui use Component CRDs?
  - Does it use AgentBuild CRDs?
  - Are there API changes needed?

- [ ] **Test UI agent import**
  - Access: https://kagenti.localtest.me:9443
  - Try importing an agent via UI
  - Verify Component CR is created
  - Verify build and deployment succeed

- [ ] **Document UI workflow**
  - What CRDs does UI create?
  - How does it trigger builds?
  - How does it configure deployments?

### 5.3 Decision: Remove platform-operator Permanently?

- [ ] **Verify kagenti-operator is sufficient**
  - All CRDs work
  - Tekton integration works
  - Deployments work
  - UI integration works

- [ ] **If YES - Clean up**
  - Remove: `argocd/applications/kind-local/platform-operator.yaml`
  - Remove: `argocd/applications/base/platform-operator.yaml`
  - Remove: `operators/overlays/local/platform-operator/`
  - Update: Documentation to reflect kagenti-operator only
  - Commit: "Remove platform-operator (fully replaced by kagenti-operator)"

- [ ] **If NO - Document gaps**
  - What functionality is missing?
  - Is it roadmapped in kagenti-operator?
  - Do we need to keep platform-operator for now?

---

## Phase 6: Documentation & Script Updates

### 6.1 Update Import Script

- [ ] **Update `scripts/import-agents-via-kagenti.sh`**
  - Change from AgentBuild CRD to Component CRD
  - Match pattern from upstream weather_agent.yaml
  - Support all required environment variables
  - Handle Ollama/OpenAI API selection

- [ ] **Test import script**
  ```bash
  ./scripts/import-agents-via-kagenti.sh \
    "https://github.com/redhat-et/agent-examples.git" \
    "a2a/weather_service" \
    "weather-test-agent" \
    "team1"
  ```

### 6.2 Update Documentation

- [ ] **Update CLAUDE.md**
  - Document Component CRD pattern
  - Remove references to platform-operator
  - Update agent import workflow

- [ ] **Update TODO_monitoring_agents.md**
  - Phase 0.5 completed
  - Component CRD pattern documented
  - Agent deployment working

- [ ] **Create migration guide**
  - File: `docs/MIGRATION_KAGENTI_OPERATOR.md`
  - Document: AgentBuild → Component migration
  - Document: platform-operator → kagenti-operator migration
  - Include: Breaking changes and compatibility notes

### 6.3 Update CI/CD

- [ ] **Update `.github/workflows/app-state-validation.yml`**
  - Ensure it tests Component CRD creation
  - Ensure it validates agent deployment via kagenti-operator
  - Add weather agent E2E tests to CI

- [ ] **Verify CI passes**
  ```bash
  gh run list --repo redhat-et/kagenti-demo-deployment --workflow "ArgoCD Application State Validation" --limit 5
  ```

---

## Success Criteria

### Must Have ✅

- [ ] kagenti-operator deployed successfully (no platform-operator)
- [ ] Tekton step ConfigMaps available in kagenti-system
- [ ] Component CRD for weather-mcp-tool created and reconciled
- [ ] Component CRD for weather-service created and reconciled
- [ ] Tekton builds complete successfully for both components
- [ ] Deployments created automatically by kagenti-operator
- [ ] Pods running and healthy (weather-mcp-tool + weather-service)
- [ ] E2E tests pass: Infrastructure + Functional + Weather query
- [ ] CI passes with weather agent deployment

### Nice to Have 🎯

- [ ] kagenti-ui integration tested and working
- [ ] Import script uses Component CRDs
- [ ] Documentation updated and comprehensive
- [ ] Migration guide for others following this pattern

---

## Current Status

**Last Updated**: 2025-11-20

**Status**: Phase 1 - Research & Understanding

**Next Action**: Read Issue #78 and understand kagenti-operator architecture

**Blockers**: None

**Notes**:
- Discovered from upstream CI that Component CRD is the preferred pattern
- kagenti-operator is the unified operator replacing platform-operator
- Need to migrate from AgentBuild-only pattern to full Component CRD pattern
