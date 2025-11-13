# TODO: Comprehensive Testing Strategy for Kagenti Platform

**Date Created:** 2025-11-10
**Status:** 🟡 In Progress
**Priority:** HIGH
**Owner:** Platform Team

---

## Executive Summary

This document provides a comprehensive testing strategy and action plan for the kagenti-demo-deployment platform. It consolidates research on Kubernetes testing best practices, framework evaluations, and defines a phased implementation roadmap.

### Current State

- ✅ **Integration test suite exists** (`tests/integration/`) with 4 test modules
- ✅ **App state validation created** (`tests/validation/test_app_state.py`)
- ✅ **Log/trace error scanning created** (`tests/validation/test_log_trace_errors.py`)
- ✅ **GitHub Actions workflow** for automated validation
- ✅ **Test documentation** (`tests/README.md`, `docs/INTEGRATION_TESTS.md`)
- ⚠️ **Some tests fail** due to known platform issues (tracked in ISSUES.md)
- 🔴 **No E2E workflow tests** for agent conversations or monitoring agents
- 🔴 **No performance/load tests**
- 🔴 **No chaos engineering tests**

### Priority Focus Areas

1. **Phase 1 (Current)**: Basic validation and health checks → 🟢 87% Complete
2. **Phase 2 (Next 2 weeks)**: Integration tests for all components → 🔴 35% Complete
3. **Phase 3 (Month 2)**: E2E workflows and monitoring agents → 🔴 Not Started
4. **Phase 4 (Month 3+)**: Performance, chaos, and security testing → 🔴 Not Started

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Testing Frameworks Evaluation](#testing-frameworks-evaluation)
3. [Best Practices Research Summary](#best-practices-research-summary)
4. [Kagenti Repo Test Patterns](#kagenti-repo-test-patterns)
5. [Test Categories](#test-categories)
6. [Action Items (Phased Roadmap)](#action-items-phased-roadmap)
7. [Known Issues and Test Failures](#known-issues-and-test-failures)
8. [CI/CD Integration](#cicd-integration)
9. [Dependencies](#dependencies)
10. [Monitoring Agents Testing Strategy](#monitoring-agents-testing-strategy)
11. [Future Work](#future-work)

---

## Current State Analysis

### Existing Test Infrastructure

#### Integration Tests (`tests/integration/`)

| Test Module | Purpose | Status | Coverage |
|-------------|---------|--------|----------|
| `test_infrastructure.py` | ArgoCD, Istio, cert-manager, Gateway API, Tekton | ✅ Implemented | ~70% |
| `test_platform.py` | Keycloak, Kagenti UI, operators, gateway | ✅ Implemented | ~60% |
| `test_observability.py` | Grafana, Tempo, Phoenix, Jaeger, OTEL | ✅ Implemented | ~50% |
| `test_agents.py` | Agent deployment, API endpoints, telemetry | ✅ Implemented | ~40% |

**Key Findings:**
- Session-scoped fixtures for K8s clients (good pattern)
- Manual wait loops with timeouts (could use tenacity)
- Mix of kubectl commands and Python K8s client (inconsistent)
- Good use of pytest markers (`@pytest.mark.critical`, `@pytest.mark.xfail`)
- HTML and JSON report generation configured

#### Validation Tests (`tests/validation/`)

| Test Module | Purpose | Status |
|-------------|---------|--------|
| `test_app_state.py` | ArgoCD application health validation | ✅ Implemented |
| `test_log_trace_errors.py` | Log and trace error/warning scanning | ✅ NEW |

**App State Validation Features:**
- Queries ALL ArgoCD applications
- Validates sync status, health status, pod status
- Generates rich console reports
- Supports `--exclude-app`, `--only-critical`, `--timeout` flags
- Standalone CLI mode for manual validation

**Log/Trace Error Scanning Features:**
- Scans pod logs in all platform namespaces for errors and warnings
- Queries Phoenix GraphQL API for error spans in traces
- Queries Tempo API for distributed trace errors
- Configurable ignore list for acceptable errors/warnings
- Target: Zero unexpected errors/warnings
- Generates comprehensive error summary reports

#### GitHub Actions

| Workflow | Purpose | Status |
|----------|---------|--------|
| `app-state-validation.yml` | App state validation on push/PR | ✅ NEW |

**Features:**
- Supports both Kind and existing cluster modes
- Syncs all ArgoCD apps in correct wave order
- Uploads test results as artifacts
- Comments on PRs with validation status

---

## Testing Frameworks Evaluation

### Framework Comparison Matrix

| Framework | Type | Language | Pros | Cons | Use Case | Recommendation |
|-----------|------|----------|------|------|----------|----------------|
| **pytest** | General testing | Python | Rich ecosystem, fixtures, parametrization, good for API testing | Not K8s-native, requires kubectl/client | Integration tests, API validation | ✅ **PRIMARY** |
| **kuttl** | K8s declarative | YAML | Simple YAML tests, ArgoCD-friendly, good for GitOps | **Unmaintained**, limited assertions | Legacy/simple tests | ⚠️ Deprecated |
| **chainsaw** | K8s declarative | YAML | Modern kuttl replacement, active development, rich assertions | YAML-based (less flexible than code) | Declarative resource tests | ✅ **SECONDARY** |
| **k6** | Load/performance | JavaScript | Excellent for load testing, Grafana integration, K8s operator | Not for functional testing | Performance/stress tests | ✅ Phase 4 |
| **Ginkgo/Gomega** | BDD testing | Go | K8s-native (same language), used by K8s itself, excellent for operators | Requires Go knowledge | Operator development | ⚠️ For operator teams |
| **Testcontainers** | Container testing | Python/Go | Great for local testing, spins up dependencies | Overhead for K8s, better for unit tests | Local dev environments | ✅ Phase 3 |

### Decision Records

#### DR-001: Use pytest as Primary Testing Framework

**Decision:** pytest will be the primary testing framework for integration and E2E tests.

**Rationale:**
- Platform team has Python expertise
- Existing tests already use pytest
- Rich ecosystem (pytest-html, pytest-json-report, pytest-xdist, pytest-timeout)
- Good Kubernetes client library support
- Easy to integrate with CI/CD
- Excellent for API testing (requests, httpx, gql)

**Trade-offs:**
- Not as K8s-native as Ginkgo
- Requires maintaining K8s client code

#### DR-002: Add Chainsaw for Declarative Resource Tests

**Decision:** Add Chainsaw for declarative YAML-based resource validation tests.

**Rationale:**
- Modern, actively maintained (unlike kuttl)
- Excellent for GitOps workflows (YAML in Git)
- Complements pytest for resource state validation
- Kyverno-style assertions are powerful

**Use Cases:**
- Validate ArgoCD application manifests
- Test resource mutations (e.g., Istio sidecar injection)
- Verify RBAC policies
- Test admission webhooks

**Trade-offs:**
- Another tool to maintain
- YAML tests less flexible than Python

#### DR-003: Use k6 for Performance Testing (Phase 4)

**Decision:** Adopt k6 for load and performance testing in Phase 4.

**Rationale:**
- Best-in-class for Kubernetes load testing
- Grafana integration for visualization
- K8s operator for distributed testing
- Active community

**Trade-offs:**
- JavaScript-based (different language)
- Only needed for performance testing

---

## Best Practices Research Summary

### Pytest Best Practices for K8s E2E Testing

#### 1. Fixture Scoping

**Best Practice:** Use session-scoped fixtures for K8s clients, function-scoped for test data.

```python
@pytest.fixture(scope="session")
def k8s_client():
    """Shared K8s client for entire test session."""
    config.load_kube_config()
    return client.CoreV1Api()

@pytest.fixture(scope="function")
def test_namespace(k8s_client):
    """Create isolated namespace for each test."""
    namespace = f"test-{uuid.uuid4().hex[:8]}"
    # Create namespace
    yield namespace
    # Cleanup
```

**Current State:** ✅ We use session-scoped clients (good)

#### 2. Wait/Polling Patterns

**Best Practice:** Use `tenacity` for retry logic with exponential backoff.

```python
from tenacity import retry, stop_after_delay, wait_exponential

@retry(stop=stop_after_delay(300), wait=wait_exponential(multiplier=1, min=2, max=10))
def wait_for_pod_ready(k8s_client, namespace, label_selector):
    pods = k8s_client.list_namespaced_pod(namespace, label_selector=label_selector)
    if not pods.items or not all(c.ready for c in pods.items[0].status.container_statuses):
        raise Exception("Pod not ready yet")
    return pods.items[0]
```

**Current State:** ⚠️ We use manual loops (should migrate to tenacity)

#### 3. Namespace Isolation

**Best Practice:** Each test gets its own namespace for isolation.

```python
@pytest.fixture
def isolated_namespace(k8s_client):
    ns_name = f"test-{uuid.uuid4().hex[:8]}"
    namespace = client.V1Namespace(metadata=client.V1ObjectMeta(name=ns_name))
    k8s_client.create_namespace(namespace)
    yield ns_name
    k8s_client.delete_namespace(ns_name)
```

**Current State:** 🔴 Tests run in shared namespaces (risk of interference)

#### 4. Resource Cleanup

**Best Practice:** Use fixtures with yield for guaranteed cleanup.

```python
@pytest.fixture
def test_deployment(k8s_apps_client, isolated_namespace):
    deployment = create_test_deployment(isolated_namespace)
    yield deployment
    # Cleanup happens even if test fails
    k8s_apps_client.delete_namespaced_deployment(
        deployment.metadata.name,
        isolated_namespace
    )
```

**Current State:** ⚠️ Some tests don't clean up (should improve)

#### 5. Parallel Test Execution

**Best Practice:** Use `pytest-xdist` for parallel execution.

```bash
# Run tests in parallel across 4 workers
pytest tests/ -n 4
```

**Current State:** ✅ pytest-xdist installed, not actively used yet

#### 6. Flaky Test Handling

**Best Practice:** Use `@pytest.mark.flaky` with retries, track flakiness.

```python
@pytest.mark.flaky(reruns=3, reruns_delay=2)
def test_network_dependent_feature():
    # Test that might fail due to network issues
    pass
```

**Current State:** ✅ We use `@pytest.mark.xfail` for known issues

#### 7. Test Data Management

**Best Practice:** Use YAML manifests from Git, apply with kubectl or K8s client.

```python
def apply_manifest(k8s_client, manifest_path, namespace):
    with open(manifest_path) as f:
        manifest = yaml.safe_load(f)
    # Apply using K8s client
```

**Current State:** ⚠️ Mix of approaches (should standardize)

#### 8. Mocking External Dependencies

**Best Practice:** Mock external services (e.g., external APIs) in integration tests.

```python
@pytest.fixture
def mock_external_api(monkeypatch):
    def mock_get(*args, **kwargs):
        return MockResponse({"status": "ok"})
    monkeypatch.setattr(requests, "get", mock_get)
```

**Current State:** 🔴 Not mocking external dependencies yet

---

## Kagenti Repo Test Patterns

### Research Findings from Main Kagenti Repo

Analyzed tests in `/Users/ladas/Projects/OCTO/research/kagenti/kagenti/ui/tests/`:

#### Test Files Found

1. **`conftest.py`**: Test fixtures and mocks
2. **`test_env_parser.py`**: Environment variable parsing
3. **`test_integration_resource_body.py`**: Integration with K8s resources
4. **`test_a2a_utils.py`**: Agent-to-agent communication utils

#### Key Patterns Observed

**Pattern 1: Mock Objects for UI Components**

```python
def make_log_container():
    class C:
        def markdown(self, *args, **kwargs):
            pass
        def warning(self, *args, **kwargs):
            pass
    return C()
```

**Lesson:** Create lightweight mocks for Streamlit/UI components.

**Pattern 2: Monkeypatch for External Dependencies**

```python
def test_construct_tool_resource_body_includes_valuefrom(monkeypatch):
    monkeypatch.setattr(build_utils, "get_secret_data", lambda *args: "gituser")
    monkeypatch.setattr(build_utils, "_get_keycloak_client_secret", lambda *args: "")
    # ... rest of test
```

**Lesson:** Use monkeypatch to avoid real K8s/Keycloak calls in unit tests.

**Pattern 3: Testing JSON Parsing with Edge Cases**

```python
def test_invalid_json_kept_as_string():
    content = "API_KEY='\"valueFrom\": {\"secretKeyRef\": {\"name\": \"foo\"}}'\n"
    res = build_utils.parse_env_file(content)
    assert "value" in res[0]
```

**Lesson:** Test edge cases (malformed JSON, invalid input).

**Pattern 4: Integration Tests with Real Resource Bodies**

```python
def test_construct_tool_resource_body_includes_valuefrom(monkeypatch):
    additional_env = [{"name": "SECRET_KEY", "valueFrom": {...}}]
    body = build_utils._construct_tool_resource_body(...)
    env_list = body.get("spec", {}).get("deployer", {}).get("env", [])
    assert any(e.get("name") == "SECRET_KEY" and "valueFrom" in e for e in env_list)
```

**Lesson:** Validate full resource body structure, not just top-level fields.

#### Testing Dependencies Used

From `kagenti/ui/pyproject.toml`:

```toml
[dependency-groups]
dev = [
    "pylint>=3.3.8",
    "pytest>=8.0",
    "pytest-asyncio>=0.22",
]

[tool.pytest.ini_options]
asyncio_default_fixture_loop_scope = "function"
asyncio_mode = "auto"
```

**Lessons:**
- pytest-asyncio for async tests
- Function-scoped event loop (modern best practice)
- Auto asyncio mode

---

## Test Categories

### Category 1: Infrastructure Validation

**Purpose:** Validate core K8s infrastructure is deployed and healthy.

**Tests:**
- ✅ ArgoCD server, controller, repo server healthy
- ✅ Istio control plane (istiod) healthy
- ✅ cert-manager pods running
- ✅ Gateway API CRDs installed
- ✅ Tekton pipelines ready

**Status:** 🟢 Complete (see `test_infrastructure.py`)

### Category 2: Platform Services

**Purpose:** Validate platform services (Keycloak, UI, operators).

**Tests:**
- ✅ Keycloak admin console accessible
- ✅ Kagenti UI pods running
- ⚠️ OAuth secret generated correctly
- ✅ Kagenti operator CRDs installed
- ⚠️ Platform operator running (blocked by image issue)

**Status:** 🟡 Partial (see ISSUES.md)

### Category 3: Observability Stack

**Purpose:** Validate observability components collect and display data.

**Tests:**
- ✅ Grafana accessible
- ⚠️ Tempo receiving traces
- ⚠️ Phoenix tracing UI showing data
- ⚠️ Jaeger deprecated (should remove or mark xfail)
- ✅ OTEL collector running

**Status:** 🟡 Partial (some components not working)

### Category 4: Agent Lifecycle

**Purpose:** Validate agent deployment, APIs, and telemetry.

**Tests:**
- ⚠️ Agent CRDs created
- 🔴 Agent builds succeed (Tekton pipelines)
- 🔴 Agent pods deployed and running
- 🔴 Agent API endpoints accessible
- 🔴 Agent telemetry sent to OTEL collector

**Status:** 🔴 Blocked (operator image issue)

### Category 5: Application State (NEW)

**Purpose:** Comprehensive ArgoCD application health validation.

**Tests:**
- ✅ All apps exist
- ✅ All apps synced
- ✅ All apps healthy
- ✅ All pods running (not CrashLoopBackOff)
- ✅ No error conditions

**Status:** 🟢 Complete (`test_app_state.py`)

### Category 6: E2E Workflows (TODO)

**Purpose:** End-to-end user workflows and monitoring agents.

**Tests:**
- 🔴 Create agent via UI
- 🔴 Agent conversation with tools (MCP)
- 🔴 Agent generates traces
- 🔴 Traces visible in Grafana
- 🔴 Monitoring agent detects anomalies
- 🔴 Monitoring agent sends alerts

**Status:** 🔴 Not Started (Phase 3)

### Category 7: Performance & Load (TODO)

**Purpose:** Validate platform handles load and scales appropriately.

**Tests:**
- 🔴 100 concurrent agent conversations
- 🔴 High trace volume ingestion
- 🔴 Grafana dashboard query performance
- 🔴 Database connection pooling

**Status:** 🔴 Not Started (Phase 4)

### Category 8: Chaos & Resilience (TODO)

**Purpose:** Validate platform resilience to failures.

**Tests:**
- 🔴 Pod deletion (auto-recovery)
- 🔴 Network partition
- 🔴 Disk pressure
- 🔴 OOM scenarios

**Status:** 🔴 Not Started (Phase 4)

---

## Action Items (Phased Roadmap)

### Phase 1: Basic Validation (Current - Week 1-2)

**Goal:** Ensure platform can be deployed and basic health checks pass.

| # | Task | Priority | Status | Owner | Deadline |
|---|------|----------|--------|-------|----------|
| 1.1 | ✅ Create app state validation test suite | HIGH | 🟢 Complete | Platform | Done |
| 1.2 | ✅ Add GitHub Actions workflow for validation | HIGH | 🟢 Complete | Platform | Done |
| 1.3 | ✅ Create log/trace error scanning test suite | HIGH | 🟢 Complete | Platform | Done |
| 1.4 | ✅ Create comprehensive test documentation | MEDIUM | 🟢 Complete | Platform | Done |
| 1.5 | ✅ Update CLAUDE.md with TDD workflow | MEDIUM | 🟢 Complete | Platform | Done |
| 1.6 | 🔴 Fix platform-operator image build issue | CRITICAL | 🟢 Complete | Ops Team | Done |
| 1.7 | 🔴 Fix kagenti-operator image build issue | CRITICAL | 🟢 Complete | Ops Team | Done |
| 1.8 | ✅ Configure PostgreSQL with Istio mTLS encryption | HIGH | 🟢 Complete | Platform | Done |
| 1.9 | ✅ Resolve Keycloak database secret generation | HIGH | 🟢 Complete | Platform | Done |
| 1.10 | 🔴 Verify all ArgoCD apps can sync successfully | HIGH | 🟡 In Progress | Platform | Week 2 |
| 1.11 | 🔴 Document known test failures in ISSUES.md | MEDIUM | 🟡 In Progress | Platform | Week 2 |
| 1.12 | 🔴 Add pytest-rerunfailures for flaky tests | MEDIUM | 🔴 Not Started | Platform | Week 3 |
| 1.13 | 🔴 Add best practices guide for ArgoCD PreSync hooks | MEDIUM | 🔴 Not Started | Platform | Week 3 |
| 1.14 | 🔴 Create POSIX shell script linter for Alpine images | LOW | 🔴 Not Started | Platform | Week 4 |
| 1.15 | 🔴 Add Quick Start deployment guide to CLAUDE.md | HIGH | 🔴 Not Started | Platform | Week 2 |

### Phase 2: Integration Tests (Week 3-6)

**Goal:** Comprehensive integration tests for all platform components.

| # | Task | Priority | Status | Owner | Deadline |
|---|------|----------|--------|-------|----------|
| 2.1 | 🔴 Migrate wait loops to tenacity retry logic | MEDIUM | 🔴 Not Started | Platform | Week 4 |
| 2.2 | 🔴 Add namespace isolation for test runs | MEDIUM | 🔴 Not Started | Platform | Week 4 |
| 2.3 | 🔴 Improve resource cleanup (fixtures with yield) | MEDIUM | 🔴 Not Started | Platform | Week 5 |
| 2.4 | 🔴 Add tests for Istio mTLS verification | HIGH | 🔴 Not Started | Security | Week 5 |
| 2.5 | 🔴 Add tests for cert-manager certificate issuance | MEDIUM | 🔴 Not Started | Platform | Week 5 |
| 2.6 | 🔴 Add tests for Tekton pipeline execution | HIGH | 🔴 Not Started | Platform | Week 6 |
| 2.7 | 🔴 Add tests for agent API endpoints | HIGH | 🔴 Not Started | Platform | Week 6 |
| 2.8 | 🔴 Enable pytest-xdist parallel execution | LOW | 🔴 Not Started | Platform | Week 6 |
| 2.9 | 🔴 Add Chainsaw for declarative resource tests | MEDIUM | 🔴 Not Started | Platform | Week 6 |

### Phase 3: E2E Workflows & Monitoring Agents (Week 7-12)

**Goal:** Test complete user workflows and monitoring agent use cases.

| # | Task | Priority | Status | Owner | Deadline |
|---|------|----------|--------|-------|----------|
| 3.1 | 🔴 Create E2E test: Agent creation via UI | HIGH | 🔴 Not Started | Platform | Week 8 |
| 3.2 | 🔴 Create E2E test: Agent conversation with MCP tools | HIGH | 🔴 Not Started | Platform | Week 8 |
| 3.3 | 🔴 Create E2E test: Trace generation and visualization | HIGH | 🔴 Not Started | Platform | Week 9 |
| 3.4 | 🔴 Create monitoring agent test suite | CRITICAL | 🔴 Not Started | Platform | Week 10 |
| 3.5 | 🔴 Test monitoring agent anomaly detection | HIGH | 🔴 Not Started | Platform | Week 11 |
| 3.6 | 🔴 Test monitoring agent alerting | HIGH | 🔴 Not Started | Platform | Week 11 |
| 3.7 | 🔴 Add Testcontainers for local dev testing | MEDIUM | 🔴 Not Started | Platform | Week 12 |
| 3.8 | 🔴 Document E2E test patterns | MEDIUM | 🔴 Not Started | Platform | Week 12 |

### Phase 4: Performance, Chaos & Security (Month 3+)

**Goal:** Validate platform production-readiness.

| # | Task | Priority | Status | Owner | Deadline |
|---|------|----------|--------|-------|----------|
| 4.1 | 🔴 Set up k6 for load testing | MEDIUM | 🔴 Not Started | Platform | Month 3 |
| 4.2 | 🔴 Create load test: 100 concurrent agents | MEDIUM | 🔴 Not Started | Platform | Month 3 |
| 4.3 | 🔴 Create stress test: Trace ingestion | MEDIUM | 🔴 Not Started | Platform | Month 3 |
| 4.4 | 🔴 Add chaos tests with Litmus or Chaos Mesh | LOW | 🔴 Not Started | SRE | Month 4 |
| 4.5 | 🔴 Test pod failure recovery | LOW | 🔴 Not Started | SRE | Month 4 |
| 4.6 | 🔴 Test network partition scenarios | LOW | 🔴 Not Started | SRE | Month 4 |
| 4.7 | 🔴 Security tests: RBAC validation | MEDIUM | 🔴 Not Started | Security | Month 4 |
| 4.8 | 🔴 Security tests: mTLS enforcement | HIGH | 🔴 Not Started | Security | Month 4 |

---

## Known Issues and Test Failures

### Critical Blockers

1. **kagenti-operator image not published** (see ISSUES.md Issue #1)
   - **Impact:** Cannot test agent CRDs, AgentBuild, agent deployments
   - **Workaround:** None
   - **Tests Affected:** All agent lifecycle tests
   - **Status:** 🔴 Blocked

2. **platform-operator image not published** (see ISSUES.md Issue #1)
   - **Impact:** Cannot test platform operator functionality
   - **Workaround:** None
   - **Tests Affected:** Platform operator tests
   - **Status:** 🔴 Blocked

### Known Test Failures (xfail)

Tests marked with `@pytest.mark.xfail` due to known issues:

1. **Jaeger UI accessibility** (`test_observability.py::test_jaeger_ui_accessible`)
   - **Reason:** Jaeger deprecated in favor of Tempo
   - **Action:** Remove Jaeger or mark as deprecated

2. **Phoenix tracing data** (`test_observability.py::test_phoenix_shows_traces`)
   - **Reason:** Phoenix not receiving traces from OTEL collector
   - **Action:** Debug OTEL exporter configuration

3. **Agent API endpoints** (`test_agents.py::test_agent_api_accessible`)
   - **Reason:** Blocked by operator image issue
   - **Action:** Wait for operator fix

### Flaky Tests

No known flaky tests yet. Will track using pytest-rerunfailures in Phase 1.

---

## CI/CD Integration

### Current CI/CD Setup

- ✅ GitHub Actions workflow: `app-state-validation.yml`
- ✅ Triggers: push to main/argocd-gitops-dev, PRs, manual dispatch
- ✅ Cluster modes: Kind (default) or existing cluster
- ✅ Test results uploaded as artifacts
- ✅ PR comments with validation status

### Future CI/CD Enhancements

| # | Enhancement | Priority | Status |
|---|-------------|----------|--------|
| 1 | Add integration test workflow | HIGH | 🔴 Not Started |
| 2 | Add E2E test workflow (nightly) | MEDIUM | 🔴 Not Started |
| 3 | Add performance test workflow (weekly) | LOW | 🔴 Not Started |
| 4 | Test result dashboards (e.g., Testkube) | LOW | 🔴 Not Started |
| 5 | Slack/Teams notifications on failures | MEDIUM | 🔴 Not Started |

### Integration with ArgoCD Sync Hooks

**Future:** Run validation tests as ArgoCD PreSync/PostSync hooks.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: validation-
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      containers:
      - name: validate
        image: python:3.11
        command: ["/bin/sh", "-c"]
        args:
          - |
            pip install pytest kubernetes rich tenacity
            pytest /tests/validation/test_app_state.py
      restartPolicy: Never
```

---

## Dependencies

### Testing Tool Dependencies

**Python Packages:**

```txt
# Core testing
pytest>=8.0.0
pytest-html>=4.1.0
pytest-json-report>=1.5.0
pytest-timeout>=2.2.0
pytest-xdist>=3.5.0  # Parallel execution
pytest-asyncio>=0.22.0  # Async tests
pytest-rerunfailures>=13.0  # Flaky test handling

# Kubernetes client
kubernetes>=28.1.0

# HTTP clients
requests>=2.31.0
httpx>=0.26.0

# GraphQL (Phoenix)
gql[all]>=3.5.0

# OpenTelemetry
opentelemetry-api>=1.21.0
opentelemetry-sdk>=1.21.0
opentelemetry-exporter-otlp>=1.21.0

# Utilities
tenacity>=8.2.3  # Retry logic
rich>=13.7.0  # Pretty output
pyyaml>=6.0.1
python-dateutil>=2.8.2
tabulate>=0.9.0
```

**System Dependencies:**

- kubectl >= 1.27
- argocd CLI >= 2.9
- kind >= 0.20 (for local testing)
- Docker (for Kind)

### Platform Dependencies (for tests to pass)

| Dependency | Required Version | Status | Notes |
|------------|------------------|--------|-------|
| ArgoCD | >= 2.9 | ✅ Deployed | Working |
| Istio | >= 1.20 | ✅ Deployed | mTLS working |
| cert-manager | >= 1.13 | ✅ Deployed | Working |
| Keycloak | >= 23 | ✅ Deployed | OAuth secret issue |
| Grafana | >= 10.2 | ✅ Deployed | Working |
| Tempo | >= 2.3 | ✅ Deployed | Trace ingestion issues |
| Phoenix | >= 1.0 | ✅ Deployed | Not showing traces |
| OTEL Collector | >= 0.91 | ✅ Deployed | Working |
| kagenti-operator | >= 0.2.0 | 🔴 Blocked | Image not published |
| platform-operator | >= 0.2.0 | 🔴 Blocked | Image not published |

---

## Monitoring Agents Testing Strategy

### Overview

The monitoring agents use case (see `TODO_monitoring_agents.md`) is a critical E2E workflow that requires comprehensive testing.

### Monitoring Agent Test Scenarios

#### Scenario 1: Anomaly Detection

**Objective:** Verify monitoring agent detects anomalies in traces.

**Test Steps:**
1. Deploy monitoring agent with anomaly detection config
2. Generate normal traffic (baseline)
3. Generate anomalous traffic (e.g., high latency, errors)
4. Verify monitoring agent:
   - Detects anomaly in traces
   - Generates alert event
   - Logs anomaly to console/storage

**Validation:**
- Monitoring agent logs contain anomaly detection event
- Alert sent to configured destination (Slack, webhook, etc.)
- Anomaly visible in Grafana dashboard

**Status:** 🔴 Not Started (Phase 3, Task 3.5)

#### Scenario 2: Pattern Recognition

**Objective:** Verify monitoring agent learns normal patterns.

**Test Steps:**
1. Deploy monitoring agent
2. Generate traffic for learning period (e.g., 1 hour)
3. Verify monitoring agent:
   - Builds baseline of normal behavior
   - Stores learned patterns
   - Updates thresholds dynamically

**Validation:**
- Agent state shows learned patterns
- Baseline metrics stored
- Dynamic thresholds configured

**Status:** 🔴 Not Started (Phase 3, Task 3.5)

#### Scenario 3: Multi-Service Correlation

**Objective:** Verify monitoring agent correlates issues across services.

**Test Steps:**
1. Deploy monitoring agent watching multiple services
2. Introduce issue in service A (e.g., slow database)
3. Verify issue propagates to service B (downstream)
4. Verify monitoring agent:
   - Detects issue in both services
   - Correlates issues via trace IDs
   - Identifies root cause (service A)

**Validation:**
- Agent identifies root cause
- Alert includes correlated services
- Grafana shows trace correlation

**Status:** 🔴 Not Started (Phase 3, Task 3.5)

#### Scenario 4: Alert Routing

**Objective:** Verify monitoring agent routes alerts correctly.

**Test Steps:**
1. Configure monitoring agent with alert routing rules
2. Generate different types of anomalies
3. Verify alerts routed to correct destinations

**Validation:**
- Critical alerts sent to Slack
- Warning alerts sent to email
- Info alerts logged only

**Status:** 🔴 Not Started (Phase 3, Task 3.6)

### Monitoring Agent Test Implementation

**Test File:** `tests/e2e/test_monitoring_agents.py`

```python
#!/usr/bin/env python3
"""
E2E tests for monitoring agents.

Tests:
- Anomaly detection
- Pattern recognition
- Multi-service correlation
- Alert routing
"""

import pytest
from kubernetes import client, config
import time

@pytest.fixture(scope="module")
def monitoring_agent_deployed(k8s_custom_client):
    """Deploy monitoring agent for tests."""
    # Deploy monitoring agent CR
    agent_manifest = {
        "apiVersion": "kagenti.ai/v1alpha1",
        "kind": "Agent",
        "metadata": {"name": "test-monitoring-agent"},
        "spec": {
            "type": "monitoring",
            "config": {
                "watchNamespaces": ["default"],
                "anomalyDetection": {"enabled": True},
                "alerting": {"enabled": True}
            }
        }
    }
    # Apply manifest...
    yield
    # Cleanup

@pytest.mark.e2e
def test_monitoring_agent_detects_anomaly(monitoring_agent_deployed, k8s_client):
    """Test monitoring agent detects anomalies in traces."""
    # 1. Generate normal traffic
    generate_normal_traffic()

    # 2. Generate anomalous traffic
    generate_anomalous_traffic()

    # 3. Wait for detection
    time.sleep(30)

    # 4. Verify anomaly detected
    logs = get_agent_logs(k8s_client, "test-monitoring-agent")
    assert "ANOMALY DETECTED" in logs

    # 5. Verify alert sent
    alerts = get_alerts()
    assert len(alerts) > 0
    assert alerts[0]["type"] == "anomaly"
```

**Status:** 🔴 Not Started (Phase 3)

---

## Future Work

### Advanced Testing Scenarios

1. **Multi-Cluster Testing**
   - Test ArgoCD application sets across multiple clusters
   - Validate federation scenarios

2. **Upgrade Testing**
   - Test rolling upgrades of platform components
   - Validate backward compatibility

3. **Disaster Recovery Testing**
   - Test backup and restore procedures
   - Validate data persistence

4. **Security Testing**
   - Penetration testing
   - RBAC validation
   - Secret scanning
   - Vulnerability scanning

5. **Compliance Testing**
   - PCI-DSS compliance
   - SOC2 compliance
   - GDPR compliance

### Integration with External Tools

1. **Testkube**
   - Kubernetes-native test orchestration
   - Test result dashboards
   - Scheduled test runs

2. **Argo Rollouts**
   - Canary deployments with automated validation
   - Progressive delivery

3. **Keptn**
   - Quality gates
   - SLO-based testing

4. **Chaos Engineering**
   - Litmus Chaos
   - Chaos Mesh
   - Gremlin

---

## Related Documentation

- **[INTEGRATION_TESTS.md](./docs/INTEGRATION_TESTS.md)**: Detailed integration test documentation
- **[TODO_ARGOCD_HEALTH_CHECKS.md](./TODO_ARGOCD_HEALTH_CHECKS.md)**: ArgoCD health check implementation
- **[ISSUES.md](./ISSUES.md)**: Known platform issues and test blockers
- **[CLAUDE.md](./CLAUDE.md)**: GitOps workflow and best practices
- **[TODO_monitoring_agents.md](./TODO_monitoring_agents.md)**: Monitoring agents use case

---

## Summary

### What We Built

1. ✅ **App state validation test suite** (`tests/validation/test_app_state.py`)
   - Comprehensive ArgoCD application health checks
   - Rich console reporting
   - Standalone CLI mode

2. ✅ **GitHub Actions workflow** (`.github/workflows/app-state-validation.yml`)
   - Automated validation on push/PR
   - Support for Kind and existing clusters
   - PR comments with results

3. ✅ **Testing framework evaluation**
   - Compared pytest, kuttl, chainsaw, k6, Ginkgo, Testcontainers
   - Decision: pytest (primary) + chainsaw (secondary) + k6 (performance)

4. ✅ **Best practices research**
   - Pytest fixture scoping
   - Wait/polling with tenacity
   - Namespace isolation
   - Flaky test handling

### Next Steps

**Immediate (Week 1-2):**
1. Fix operator image build issues (CRITICAL)
2. Resolve Keycloak OAuth secret generation
3. Verify all ArgoCD apps sync successfully

**Short-term (Week 3-6):**
1. Migrate to tenacity for retry logic
2. Add namespace isolation
3. Add Istio mTLS tests
4. Enable parallel test execution

**Medium-term (Week 7-12):**
1. Create E2E test suite
2. Implement monitoring agent tests
3. Add Testcontainers for local dev

**Long-term (Month 3+):**
1. Set up k6 for load testing
2. Add chaos engineering tests
3. Security and compliance testing

---

**Status Legend:**
- 🟢 Complete
- 🟡 In Progress
- 🔴 Not Started
- ⚠️ Blocked/Issues

**Last Updated:** 2025-11-11

---

## Recent Accomplishments (2025-11-11)

### PostgreSQL Istio mTLS Configuration ✅

**Task 1.8**: Successfully migrated PostgreSQL from application-level SSL to Istio service mesh mTLS.

**Problem Solved:**
- PostgreSQL SSL protocol conflicted with Istio Envoy proxy
- SSL upgrade handshake blocked by Istio sidecar
- Database connection failures (Connection reset errors)

**Solution Implemented:**
- Enabled Istio sidecar injection on PostgreSQL pods (`sidecar.istio.io/inject: "true"`)
- Removed PostgreSQL SSL configuration (initContainer, SSL args, volumes)
- Updated DestinationRule to use `ISTIO_MUTUAL` mode
- Fixed database credentials to use `keycloak-db-secret`
- Reinitialized PostgreSQL PVC with correct password

**Results:**
- ✅ PostgreSQL: 2/2 Running (with Istio sidecar)
- ✅ Keycloak: 2/2 Running (with Istio sidecar)
- ✅ Keycloak Application: Healthy status
- ✅ Database connection: Successful
- ✅ mTLS policies: STRICT mode enforced
- ✅ Architecture: Sidecar-to-sidecar mTLS (no plaintext on network)

**Files Modified:**
- `components/00-infrastructure/keycloak/postgres-statefulset.yaml`
- `components/00-infrastructure/keycloak/mtls-policy.yaml`

**Commits:**
- d8c4702: Switch PostgreSQL to Istio mTLS
- d83fcdb: Fix PostgreSQL credentials

**Impact on Testing:**
- Advances Phase 2 Task 2.4 (Istio mTLS verification)
- Validates encryption architecture documented in CLAUDE.md
- Provides foundation for future mTLS tests

---

### Keycloak Database Secret Generation Fix ✅

**Task 1.9**: Successfully fixed Keycloak database secret generation on fresh Kind deployment.

**Problems Identified:**

**Problem 1: RBAC Resources Missing**
- db-secret-generator Job failed with "serviceaccount not found" error
- RBAC resources (ServiceAccount, Role, RoleBinding) were in same file as PreSync hook Job
- ArgoCD treats all resources in hook files as temporary hooks
- RBAC resources were deleted before Job could use them

**Problem 2: Shell Compatibility**
- Job container failed immediately after starting with "Back-off restarting failed container"
- Script used `/bin/bash` but bitnami/kubectl image is Alpine-based (only has `/bin/sh`)
- Script used bash-specific `set -euo pipefail` (pipefail not supported in POSIX sh)

**Solutions Implemented:**

**Fix 1: Separate RBAC from Hook Job**
- Created new file: `db-secret-generator-rbac.yaml`
  - Contains ServiceAccount, Role, RoleBinding
  - Annotated with `argocd.argoproj.io/sync-wave: "-2"` (deploys before job at wave -1)
  - These are normal resources (not hooks), persist after deployment
- Updated `db-secret-generation-job.yaml`
  - Removed RBAC resources (now in separate file)
  - Kept only Job resource with PreSync hook annotation
- Updated `kustomization.yaml`
  - Added `db-secret-generator-rbac.yaml` to resources list
  - Ordered before job file to ensure wave -2 deploys first

**Fix 2: Shell Compatibility**
- Changed command from `/bin/bash` to `/bin/sh` (POSIX-compatible)
- Changed `set -euo pipefail` to `set -eu` (removed bash-only pipefail)
- Script now runs with Alpine's BusyBox ash shell

**Deployment Order:**
```
Wave -2: ServiceAccount, Role, RoleBinding (normal resources, persist)
Wave -1: Job (PreSync hook, runs before main sync, then deleted)
Wave 0+: Main Keycloak resources (CR, PostgreSQL, realms)
```

**Results:**
- ✅ db-secret-generator Job: Completed successfully
- ✅ keycloak-db-secret: Created with random credentials (2 data keys)
- ✅ PostgreSQL pod: 2/2 Running (app + Istio sidecar)
- ✅ Keycloak pod: 2/2 Running (app + Istio sidecar)
- ✅ Keycloak Application: Healthy status in ArgoCD
- ✅ Platform health: 6/6 core components operational

**Files Created:**
- `components/00-infrastructure/keycloak/db-secret-generator-rbac.yaml`

**Files Modified:**
- `components/00-infrastructure/keycloak/db-secret-generation-job.yaml`
- `components/00-infrastructure/keycloak/kustomization.yaml`

**Commits:**
- 862025d: Re-enable db-secret-generation-job for Keycloak
- 6b81ace: Fix db-secret-generator Job RBAC resources missing
- a1cf9aa: Fix db-secret-generator Job script shell compatibility

**Impact on Testing:**
- ✅ Completes Phase 1 Task 1.9 (Keycloak OAuth secret generation)
- ✅ Enables Phase 1 Task 1.10 (All ArgoCD apps can sync)
- Validates GitOps workflow (all fixes via Git, no manual kubectl)
- Provides pattern for other Jobs with ArgoCD hooks
- Demonstrates POSIX shell compatibility requirements for Alpine images

**Lessons Learned:**
1. **ArgoCD Hooks & RBAC**: PreSync hook resources are temporary. RBAC must be deployed separately with appropriate sync-waves.
2. **Alpine Linux Containers**: Many minimal container images use `/bin/sh` not `/bin/bash`. Always write POSIX-compatible shell scripts or explicitly use bash-based images.
3. **Fresh Deployment Testing**: Testing on fresh Kind clusters catches issues that might be hidden in existing clusters with manually-applied resources.

---
| 2025-11-12 16:26:57 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:26:57

⚠ No tests executed

---

| 2025-11-12 16:30:08 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:30:08

⚠ No tests executed

---

| 2025-11-12 16:39:26 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:39:26

⚠ No tests executed

---

| 2025-11-12 16:40:28 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:40:28

⚠ No tests executed

---

| 2025-11-12 16:42:49 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:42:49

⚠ No tests executed

---

| 2025-11-12 16:43:32 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:43:32

⚠ No tests executed

---

| 2025-11-12 16:46:32 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:46:32

⚠ No tests executed

---

| 2025-11-12 16:48:10 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:48:10

⚠ No tests executed

---

| 2025-11-12 16:49:23 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:49:23

⚠ No tests executed

---

| 2025-11-12 16:53:07 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:53:07

⚠ No tests executed

---

| 2025-11-12 16:53:46 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:53:46

⚠ No tests executed

---

| 2025-11-12 16:55:52 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 16:55:52

⚠ No tests executed

---

| 2025-11-12 17:24:44 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 17:24:44

⚠ No tests executed

---

| 2025-11-12 17:28:10 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 17:28:10

⚠ No tests executed

---

| 2025-11-12 17:44:28 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 17:44:28

⚠ No tests executed

---

| 2025-11-12 17:59:29 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 17:59:29

⚠ No tests executed

---

| 2025-11-12 18:15:18 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 18:15:18

⚠ No tests executed

---

| 2025-11-12 18:24:45 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 18:24:45

⚠ No tests executed

---

| 2025-11-12 18:28:42 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 18:28:42

⚠ No tests executed

---

| 2025-11-12 19:03:22 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 19:03:22

⚠ No tests executed

---

| 2025-11-12 19:27:04 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 19:27:04

⚠ No tests executed

---

| 2025-11-12 19:45:12 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 19:45:12

⚠ No tests executed

---

| 2025-11-12 19:46:14 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 19:46:14

⚠ No tests executed

---

| 2025-11-12 19:47:13 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 19:47:13

⚠ No tests executed

---

| 2025-11-12 19:49:24 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 19:49:24

⚠ No tests executed

---

| 2025-11-12 21:53:01 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 21:53:01

⚠ No tests executed

---

| 2025-11-12 22:19:40 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-12 22:19:40

⚠ No tests executed

---

| 2025-11-13 07:40:02 | 0 | 0 | 0 | 0 | ⚠ NO TESTS |

### Test Run: 2025-11-13 07:40:02

⚠ No tests executed

---

| 2025-11-13 07:45:34 | 158 | 83 | 54 | 21 | ✗ FAIL |

### Test Run: 2025-11-13 07:45:34

**Summary**: 158 tests (83 passed, 54 failed, 21 skipped)

| Test | Status | Duration |
|------|--------|----------|
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_infrastructure.py::TestCertManager::test_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 07:53:38 | 158 | 84 | 53 | 21 | ✗ FAIL |

### Test Run: 2025-11-13 07:53:38

**Summary**: 158 tests (84 passed, 53 failed, 21 skipped)

| Test | Status | Duration |
|------|--------|----------|
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_infrastructure.py::TestCertManager::test_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 08:17:14 | 158 | 84 | 53 | 21 | ✗ FAIL |

### Test Run: 2025-11-13 08:17:14

**Summary**: 158 tests (84 passed, 53 failed, 21 skipped)

| Test | Status | Duration |
|------|--------|----------|
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_infrastructure.py::TestCertManager::test_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 08:41:20 | 158 | 82 | 55 | 21 | ✗ FAIL |

### Test Run: 2025-11-13 08:41:20

**Summary**: 158 tests (82 passed, 55 failed, 21 skipped)

| Test | Status | Duration |
|------|--------|----------|
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_infrastructure.py::TestCertManager::test_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 08:50:48 | 158 | 84 | 53 | 21 | ✗ FAIL |

### Test Run: 2025-11-13 08:50:48

**Summary**: 158 tests (84 passed, 53 failed, 21 skipped)

| Test | Status | Duration |
|------|--------|----------|
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_infrastructure.py::TestCertManager::test_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 08:55:43 | 158 | 84 | 53 | 21 | ✗ FAIL |

### Test Run: 2025-11-13 08:55:43

**Summary**: 158 tests (84 passed, 53 failed, 21 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running FAILED [  0%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service FAILED [  1%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors FAILED [  2%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running FAILED [  3%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors FAILED [  4%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy PASSED [ 12%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy PASSED [ 14%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed FAILED [ 15%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy PASSED [ 17%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas FAILED [ 25%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible FAILED [ 41%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready FAILED [ 51%] | ✗ FAILED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds FAILED [ 57%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible FAILED [ 58%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy PASSED [ 76%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed SKIPPED [ 77%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists FAILED [ 78%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists PASSED [ 81%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists PASSED [ 82%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready FAILED [ 83%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform PASSED [ 85%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold PASSED [ 86%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist PASSED [ 87%] | ✓ PASSED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy FAILED [ 87%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy FAILED [ 88%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] FAILED [ 91%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] FAILED [ 94%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] PASSED [ 97%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] PASSED [ 98%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary PASSED [100%] | ✓ PASSED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_infrastructure.py::TestCertManager::test_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 11:20:14 | 158 | 73 | 62 | 23 | ✗ FAIL |

### Test Run: 2025-11-13 11:20:14

**Summary**: 158 tests (73 passed, 62 failed, 23 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running FAILED [  0%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service FAILED [  1%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors FAILED [  2%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running FAILED [  3%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors FAILED [  4%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy FAILED [ 10%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy FAILED [ 14%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed FAILED [ 15%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy FAILED [ 17%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy FAILED [ 18%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold FAILED [ 24%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas FAILED [ 25%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server FAILED [ 34%] | ✗ FAILED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible FAILED [ 41%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready FAILED [ 51%] | ✗ FAILED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy FAILED [ 56%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds FAILED [ 57%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible SKIPPED [ 58%] | ○ SKIPPED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy FAILED [ 59%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible SKIPPED [ 60%] | ○ SKIPPED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds SKIPPED [ 60%] | ○ SKIPPED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy FAILED [ 76%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists PASSED [ 78%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists PASSED [ 81%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists PASSED [ 82%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready FAILED [ 83%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform PASSED [ 85%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold PASSED [ 86%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist PASSED [ 87%] | ✓ PASSED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy FAILED [ 87%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy FAILED [ 88%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] FAILED [ 91%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] FAILED [ 94%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] FAILED [ 95%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] PASSED [ 96%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] FAILED [ 97%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] PASSED [ 98%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary PASSED [100%] | ✓ PASSED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy - ... | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_infrastructure.py::TestCertManager::test_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] | ✗ FAILED | - |


---

| 2025-11-13 12:02:50 | 158 | 90 | 48 | 20 | ✗ FAIL |

### Test Run: 2025-11-13 12:02:50

**Summary**: 158 tests (90 passed, 48 failed, 20 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running FAILED [  0%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service FAILED [  1%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors FAILED [  2%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running FAILED [  3%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors FAILED [  4%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy PASSED [ 12%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy PASSED [ 14%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready PASSED [ 16%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy PASSED [ 17%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold FAILED [ 24%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas FAILED [ 25%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible FAILED [ 41%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds FAILED [ 57%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible FAILED [ 58%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy PASSED [ 76%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists PASSED [ 78%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists PASSED [ 81%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists PASSED [ 82%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform PASSED [ 85%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold PASSED [ 86%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist PASSED [ 87%] | ✓ PASSED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy FAILED [ 87%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy FAILED [ 88%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] FAILED [ 91%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] FAILED [ 94%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] PASSED [ 96%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] PASSED [ 97%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] PASSED [ 98%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary PASSED [100%] | ✓ PASSED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 14:03:50 | 135 | 84 | 30 | 21 | ✗ FAIL |

### Test Run: 2025-11-13 14:03:50

**Summary**: 135 tests (84 passed, 30 failed, 21 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running PASSED [  0%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors PASSED [  2%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously PASSED [  6%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy PASSED [ 12%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy PASSED [ 14%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed FAILED [ 15%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready PASSED [ 16%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy PASSED [ 17%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas PASSED [ 25%] | ✓ PASSED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible PASSED [ 41%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds FAILED [ 57%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible FAILED [ 58%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy PASSED [ 76%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed FAILED [ 77%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists PASSED [ 78%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable ERROR [ 80%] | ✗ ERROR | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists FAILED [ 81%] | ✗ FAILED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists ERROR [ 82%] | ✗ ERROR | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured ERROR [ 83%] | ✗ ERROR | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready ERROR [ 83%] | ✗ ERROR | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform FAILED [ 85%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold FAILED [ 86%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist ERROR [ 87%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy ERROR [ 87%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy ERROR [ 88%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] ERROR [ 89%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] ERROR [ 89%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] ERROR [ 90%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] ERROR [ 90%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] ERROR [ 91%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] ERROR [ 92%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] ERROR [ 92%] | ✗ ERROR | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] ERROR [ 93%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] ERROR [ 93%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] ERROR [ 94%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] ERROR [ 95%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] ERROR [ 95%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] ERROR [ 96%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] ERROR [ 96%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] ERROR [ 97%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] ERROR [ 98%] | ✗ ERROR | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_tempo_traces SKIPPED [ 99%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary ERROR [100%] | ✗ ERROR | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| ERROR tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ ERROR | - |
| ERROR tests/integration/test_platform.py::TestExternalGateway::test_external_gateway_exists | ✗ ERROR | - |
| ERROR tests/integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured | ✗ ERROR | - |
| ERROR tests/integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ ERROR | - |
| ERROR tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] | ✗ ERROR | - |
| ERROR tests/validation/test_log_trace_errors.py::test_generate_error_warning_summary | ✗ ERROR | - |


---

| 2025-11-13 14:35:29 | 158 | 95 | 43 | 20 | ✗ FAIL |

### Test Run: 2025-11-13 14:35:29

**Summary**: 158 tests (95 passed, 43 failed, 20 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running PASSED [  0%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors PASSED [  2%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously PASSED [  6%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy PASSED [ 12%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy PASSED [ 14%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed FAILED [ 15%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready PASSED [ 16%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy PASSED [ 17%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas PASSED [ 25%] | ✓ PASSED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible PASSED [ 41%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds FAILED [ 57%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible FAILED [ 58%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy PASSED [ 76%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed FAILED [ 77%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists PASSED [ 78%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists PASSED [ 81%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists PASSED [ 82%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform FAILED [ 85%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold PASSED [ 86%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist PASSED [ 87%] | ✓ PASSED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy FAILED [ 87%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy FAILED [ 88%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] FAILED [ 91%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] FAILED [ 94%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] PASSED [ 97%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] PASSED [ 98%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary PASSED [100%] | ✓ PASSED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 14:51:19 | 158 | 98 | 40 | 20 | ✗ FAIL |

### Test Run: 2025-11-13 14:51:19

**Summary**: 158 tests (98 passed, 40 failed, 20 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running PASSED [  0%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors PASSED [  2%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously PASSED [  6%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy PASSED [ 12%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy PASSED [ 14%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready PASSED [ 16%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy PASSED [ 17%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas PASSED [ 25%] | ✓ PASSED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible PASSED [ 41%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds FAILED [ 57%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible FAILED [ 58%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy PASSED [ 76%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists PASSED [ 78%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists PASSED [ 81%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists PASSED [ 82%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform PASSED [ 85%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold PASSED [ 86%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist PASSED [ 87%] | ✓ PASSED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy FAILED [ 87%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy FAILED [ 88%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] FAILED [ 91%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] FAILED [ 94%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] PASSED [ 97%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] PASSED [ 98%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary PASSED [100%] | ✓ PASSED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 15:49:15 | 158 | 89 | 49 | 20 | ✗ FAIL |

### Test Run: 2025-11-13 15:49:15

**Summary**: 158 tests (89 passed, 49 failed, 20 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running FAILED [  0%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service FAILED [  1%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors FAILED [  2%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running FAILED [  3%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors FAILED [  4%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy PASSED [ 12%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy PASSED [ 14%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready PASSED [ 16%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy PASSED [ 17%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy PASSED [ 18%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas FAILED [ 25%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible FAILED [ 41%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds FAILED [ 57%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible FAILED [ 58%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds PASSED [ 60%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy PASSED [ 76%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed FAILED [ 77%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists PASSED [ 78%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists PASSED [ 81%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists PASSED [ 82%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform PASSED [ 85%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold PASSED [ 86%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist PASSED [ 87%] | ✓ PASSED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy FAILED [ 87%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy FAILED [ 88%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] FAILED [ 91%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] FAILED [ 94%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] PASSED [ 97%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] PASSED [ 98%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary PASSED [100%] | ✓ PASSED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously | ✗ FAILED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_api_responds | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |


---

| 2025-11-13 16:19:42 | 158 | 77 | 57 | 24 | ✗ FAIL |

### Test Run: 2025-11-13 16:19:42

**Summary**: 158 tests (77 passed, 57 failed, 24 skipped)

| Test | Status | Duration |
|------|--------|----------|
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_pod_running PASSED [  0%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_crds_registered PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_webhook_service PASSED [  1%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_logs_no_errors PASSED [  2%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestKagentiOperatorE2E::test_kagenti_operator_can_list_agents PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_pod_running PASSED [  3%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_crds_registered PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_logs_no_errors PASSED [  4%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestPlatformOperatorE2E::test_platform_operator_can_list_components PASSED [  5%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_both_operators_running_simultaneously PASSED [  6%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist FAILED [  6%] | ✗ FAILED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_images_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_operator_deployment.py::TestOperatorLifecycle::test_operator_command_path_correct PASSED [  7%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_argocd_healthy PASSED [  8%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_cert_manager_healthy PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestInfrastructure::test_tekton_pipelines_installed PASSED [  9%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_istiod_healthy PASSED [ 10%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy FAILED [ 10%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy FAILED [ 11%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy FAILED [ 12%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed FAILED [ 13%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy FAILED [ 14%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed FAILED [ 15%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_external_gateway_exists PASSED [ 15%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformServices::test_tls_certificates_ready PASSED [ 16%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy FAILED [ 16%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy FAILED [ 17%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy FAILED [ 18%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy FAILED [ 18%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestAgents::test_agent_services_exist PASSED [ 21%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestAgents::test_research_agent_a2a_endpoint SKIPPED [ 22%] | ○ SKIPPED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist FAILED [ 22%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced FAILED [ 23%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_no_crashloop_pods PASSED [ 24%] | ✓ PASSED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold FAILED [ 24%] | ✗ FAILED | - |
| e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas FAILED [ 25%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_research_agent_simple_question SKIPPED [ 25%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check FAILED [ 26%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible FAILED [ 27%] | ✗ FAILED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_simple_factual_question SKIPPED [ 27%] | ○ SKIPPED | - |
| integration/test_agent_conversation.py::TestAgentConversationManual::test_multi_turn_conversation SKIPPED [ 28%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy FAILED [ 28%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy FAILED [ 29%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy FAILED [ 30%] | ✗ FAILED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_services_exist PASSED [ 30%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentDeployment::test_agent_deployments_exist PASSED [ 31%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_research_agent_chat_endpoint SKIPPED [ 31%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentConversationAPI::test_agent_health_endpoint SKIPPED [ 32%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentTelemetry::test_agent_trace_in_phoenix SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_prometheus_mcp_server_deployment_ready SKIPPED [ 33%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server FAILED [ 34%] | ✗ FAILED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_deployment_namespace_exists PASSED [ 34%] | ✓ PASSED | - |
| integration/test_agents.py::TestMonitoringAgents::test_correl8r_service_accessible SKIPPED [ 35%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_github_mcp_server_has_credentials SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestMonitoringAgents::test_monitoring_agent_workflow SKIPPED [ 36%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentCRDLifecycle::test_create_agent_cr SKIPPED [ 37%] | ○ SKIPPED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agent_crd_installed PASSED [ 37%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentbuild_crd_installed PASSED [ 38%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_agentcard_crd_installed PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agents PASSED [ 39%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentbuilds PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_can_list_agentcards PASSED [ 40%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_webhook_accessible PASSED [ 41%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentOperatorInfrastructure::test_kagenti_operator_rbac_configured PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_team1_namespace_exists PASSED [ 42%] | ✓ PASSED | - |
| integration/test_agents.py::TestAgentHealth::test_no_crashloop_agent_pods PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_server_healthy PASSED [ 43%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_applicationset_controller_healthy PASSED [ 44%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_argocd_repo_server_healthy PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_all_argocd_applications_exist PASSED [ 45%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestArgoCD::test_critical_applications_synced PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istiod_healthy PASSED [ 46%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_ingress_gateway_healthy SKIPPED [ 47%] | ○ SKIPPED | - |
| integration/test_infrastructure.py::TestIstio::test_istio_base_crds_installed PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestIstio::test_mtls_policy_exists PASSED [ 48%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_healthy PASSED [ 49%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_webhook_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_cert_manager_cainjector_healthy PASSED [ 50%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestCertManager::test_certificates_ready PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_gateway_api_crds_installed PASSED [ 51%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_external_gateway_exists PASSED [ 52%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestGatewayAPI::test_httproutes_configured PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_controller_healthy PASSED [ 53%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_pipelines_webhook_healthy PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestTekton::test_tekton_crds_installed PASSED [ 54%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_no_crashloop_pods_in_infrastructure PASSED [ 55%] | ✓ PASSED | - |
| integration/test_infrastructure.py::TestInfrastructureHealth::test_infrastructure_pod_health_threshold PASSED [ 56%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_healthy FAILED [ 56%] | ✗ FAILED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_exists PASSED [ 57%] | ✓ PASSED | - |
| integration/test_observability.py::TestKiali::test_kiali_api_responds SKIPPED [ 57%] | ○ SKIPPED | - |
| integration/test_observability.py::TestKiali::test_kiali_service_graph_accessible SKIPPED [ 58%] | ○ SKIPPED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_healthy FAILED [ 59%] | ✗ FAILED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_service_exists PASSED [ 59%] | ✓ PASSED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_web_ui_accessible SKIPPED [ 60%] | ○ SKIPPED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_graphql_api_responds SKIPPED [ 60%] | ○ SKIPPED | - |
| integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running FAILED [ 61%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_healthy FAILED [ 62%] | ✗ FAILED | - |
| integration/test_observability.py::TestTempo::test_tempo_service_exists PASSED [ 62%] | ✓ PASSED | - |
| integration/test_observability.py::TestTempo::test_tempo_ready_endpoint FAILED [ 63%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_healthy PASSED [ 63%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_service_exists PASSED [ 64%] | ✓ PASSED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists FAILED [ 65%] | ✗ FAILED | - |
| integration/test_observability.py::TestOTELCollector::test_otel_collector_health_endpoint PASSED [ 65%] | ✓ PASSED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_healthy FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_service_exists FAILED [ 66%] | ✗ FAILED | - |
| integration/test_observability.py::TestJaeger::test_jaeger_ui_accessible SKIPPED [ 67%] | ○ SKIPPED | - |
| integration/test_observability.py::TestGrafana::test_grafana_service_exists PASSED [ 68%] | ✓ PASSED | - |
| integration/test_observability.py::TestGrafana::test_grafana_datasources_configured SKIPPED [ 69%] | ○ SKIPPED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix FAILED [ 69%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo FAILED [ 70%] | ✗ FAILED | - |
| integration/test_observability.py::TestObservabilityHealth::test_no_crashloop_pods_in_observability PASSED [ 71%] | ✓ PASSED | - |
| integration/test_observability.py::TestObservabilityHealth::test_observability_pod_health_threshold PASSED [ 71%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_healthy PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_service_exists PASSED [ 72%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_postgres_healthy PASSED [ 73%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_realm_imports_completed SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_admin_api_accessible SKIPPED [ 74%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_https_gateway_access PASSED [ 75%] | ✓ PASSED | - |
| integration/test_platform.py::TestKeycloak::test_keycloak_kagenti_realm_accessible SKIPPED [ 75%] | ○ SKIPPED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy FAILED [ 76%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_service_exists PASSED [ 77%] | ✓ PASSED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed FAILED [ 77%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists FAILED [ 78%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiUI::test_kagenti_ui_responds SKIPPED [ 78%] | ○ SKIPPED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy FAILED [ 79%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable FAILED [ 80%] | ✗ FAILED | - |
| integration/test_platform.py::TestKagentiOperator::test_kagenti_operator_deployment_exists PASSED [ 81%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_external_gateway_exists PASSED [ 82%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_gateway_listeners_configured PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestExternalGateway::test_tls_certificates_ready PASSED [ 83%] | ✓ PASSED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists FAILED [ 84%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_no_crashloop_pods_in_platform PASSED [ 85%] | ✓ PASSED | - |
| integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold FAILED [ 86%] | ✗ FAILED | - |
| integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints FAILED [ 86%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_exist PASSED [ 87%] | ✓ PASSED | - |
| validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy FAILED [ 87%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy FAILED [ 88%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] FAILED [ 89%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] FAILED [ 90%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] FAILED [ 91%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] FAILED [ 92%] | ✗ FAILED | - |
| validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] FAILED [ 93%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] FAILED [ 94%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] FAILED [ 95%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[gateway-system] PASSED [ 95%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[kagenti-system] PASSED [ 96%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] FAILED [ 96%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] FAILED [ 97%] | ✗ FAILED | - |
| validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[gateway-system] PASSED [ 98%] | ✓ PASSED | - |
| validation/test_log_trace_errors.py::test_no_errors_in_phoenix_traces SKIPPED [ 98%] | ○ SKIPPED | - |
| validation/test_log_trace_errors.py::test_generate_error_warning_summary PASSED [100%] | ✓ PASSED | - |
| FAILED tests/e2e/test_operator_deployment.py::TestOperatorIntegration::test_shared_configmaps_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_keycloak_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestServiceMesh::test_kiali_healthy - ... | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestOperators::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformServices::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_tempo_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_otel_collector_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestObservability::test_phoenix_healthy | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_all_applications_exist | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestArgoCD::test_critical_applications_synced | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_cluster_pod_health_threshold | ✗ FAILED | - |
| FAILED tests/e2e/test_platform_e2e.py::TestPlatformHealth::test_all_deployments_have_replicas | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_health_check | ✗ FAILED | - |
| FAILED tests/integration/test_agent_conversation.py::TestAgentConversation::test_agent_card_accessible | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_research_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_code_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestAgentDeployment::test_orchestrator_agent_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_agents.py::TestMonitoringAgents::test_phoenix_ready_for_trace_mcp_server | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestKiali::test_kiali_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestPhoenix::test_phoenix_postgres_backend_running | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestTempo::test_tempo_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestTempo::test_tempo_ready_endpoint | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestOTELCollector::test_otel_collector_configmap_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestJaeger::test_jaeger_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_phoenix | ✗ FAILED | - |
| FAILED tests/integration/test_observability.py::TestObservabilityDataFlow::test_otel_collector_exports_to_tempo | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_config_completed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestKagentiUI::test_kagenti_ui_oauth_secret_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_operator_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_installed | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformOperator::test_platform_crds_queryable | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_healthy | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestContainerRegistry::test_container_registry_service_exists | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_platform_pod_health_threshold | ✗ FAILED | - |
| FAILED tests/integration/test_platform.py::TestPlatformHealth::test_all_platform_services_have_endpoints | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_all_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_apps_healthy | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istio-base] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[keycloak-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[kagenti-platform-operator] | ✗ FAILED | - |
| FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[cert-manager] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[kagenti-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_errors_in_pod_logs[istio-system] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[observability] | ✗ FAILED | - |
| FAILED tests/validation/test_log_trace_errors.py::test_no_warnings_in_pod_logs[istio-system] | ✗ FAILED | - |


---

