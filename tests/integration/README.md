# Integration Tests for Kagenti Platform

Comprehensive integration test suite for the kagenti-demo-deployment stack.

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Run all tests
./run_tests.sh

# Run fast smoke tests only (critical tests)
./run_tests.sh --fast

# Run specific category
./run_tests.sh --category infrastructure

# Generate HTML report
./run_tests.sh --html
```

## Test Categories

### 1. Infrastructure Tests (`test_infrastructure.py`)

Tests core Kubernetes infrastructure and GitOps:
- ArgoCD (applications, sync status, health)
- Istio service mesh (istiod, mTLS policies)
- cert-manager (certificates, webhooks)
- Gateway API (gateways, HTTPRoutes)
- Tekton Pipelines (controller, CRDs)

**Run:**
```bash
pytest test_infrastructure.py -v
# or
./run_tests.sh --category infrastructure
```

---

### 2. Observability Tests (`test_observability.py`)

Tests observability stack and data flow:
- Kiali (service graph, API)
- Phoenix (LLM traces, GraphQL API)
- Tempo (trace aggregation)
- Grafana (dashboards, datasources)
- OTLP Collector (trace export pipeline)
- Jaeger (legacy trace compatibility)

**Run:**
```bash
pytest test_observability.py -v
# or
./run_tests.sh --category observability
```

---

### 3. Platform Tests (`test_platform.py`)

Tests platform services and authentication:
- Keycloak (realms, OAuth2, authentication)
- Kagenti UI (deployment, OAuth flow)
- Platform Operator (CRDs, controller)
- Kagenti Operator (agent lifecycle)
- External Gateway (TLS, routing)
- Container Registry (image storage)

**Run:**
```bash
pytest test_platform.py -v
# or
./run_tests.sh --category platform
```

---

### 4. Agent Tests (`test_agents.py`)

Tests agent deployment, API, and telemetry:
- Agent deployments (pods, services)
- Agent conversation API (HTTP endpoints)
- Agent telemetry (traces in Phoenix)
- Monitoring agents use case (from TODO_monitoring_agents.md)
  - Prometheus query agent
  - Trace analysis agent
  - Correlation agent
  - GitHub remediation agent

**Run:**
```bash
pytest test_agents.py -v
# or
./run_tests.sh --category agents
```

---

## Test Runner Script

The `run_tests.sh` script provides convenient test execution with multiple options:

### Options

- `--fast`: Run only critical tests (quick smoke test)
- `--slow`: Run all tests including slow tests
- `--parallel`: Run tests in parallel (requires pytest-xdist)
- `--html`: Generate HTML report
- `--category <name>`: Run specific category (infrastructure, observability, platform, agents)
- `--help`: Show help message

### Examples

```bash
# Fast smoke test (critical tests only)
./run_tests.sh --fast

# Run infrastructure tests with HTML report
./run_tests.sh --category infrastructure --html

# Run all tests in parallel
./run_tests.sh --parallel

# Run all slow tests
./run_tests.sh --slow
```

---

## Running Tests with pytest

You can also run tests directly with pytest:

### Run All Tests

```bash
pytest -v
```

### Run Specific Test File

```bash
pytest test_infrastructure.py -v
```

### Run Specific Test Class

```bash
pytest test_infrastructure.py::TestArgoCD -v
```

### Run Specific Test

```bash
pytest test_infrastructure.py::TestArgoCD::test_argocd_server_healthy -v
```

### Run with Markers

```bash
# Run only critical tests
pytest -m critical -v

# Skip slow tests
pytest -m "not slow" -v

# Run only xfail tests
pytest -m xfail -v
```

### Generate Reports

```bash
# HTML report
pytest --html=report.html --self-contained-html

# JSON report
pytest --json-report --json-report-file=report.json

# JUnit XML (for CI)
pytest --junitxml=junit.xml

# All reports
pytest --html=report.html --junitxml=junit.xml --json-report
```

### Parallel Execution

```bash
# Install pytest-xdist
pip install pytest-xdist

# Run tests in parallel (auto-detect CPU cores)
pytest -n auto -v

# Run with 4 workers
pytest -n 4 -v
```

---

## Test Markers

Tests use pytest markers to categorize behavior:

- `@pytest.mark.critical`: Fast, essential tests (smoke tests)
- `@pytest.mark.slow`: Tests that take >10 seconds (port-forwards, API calls)
- `@pytest.mark.xfail`: Expected to fail (known issues documented in ISSUES.md)
- `@pytest.mark.skip`: Temporarily disabled tests

---

## Prerequisites

### Local Testing

1. **Kind cluster with Kagenti platform**:
   ```bash
   ./scripts/kind/00-cleanup.sh
   ./scripts/kind/01-create-cluster.sh
   ./scripts/kind/02-install-argocd.sh
   ./scripts/kind/03-bootstrap-apps.sh
   ```

2. **Python 3.11+**:
   ```bash
   python --version  # Should be 3.11 or higher
   ```

3. **kubectl configured**:
   ```bash
   kubectl config current-context  # Should be: kind-kagenti-demo
   ```

4. **ArgoCD CLI installed**:
   ```bash
   argocd version --client
   ```

5. **Install test dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

---

## CI/CD Integration

### GitHub Actions

Create `.github/workflows/integration-tests.yml`:

```yaml
name: Integration Tests

on:
  push:
    branches: [main, argocd-gitops-dev]
  pull_request:
    branches: [main]

jobs:
  integration-tests:
    runs-on: ubuntu-latest
    timeout-minutes: 60

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Create Kind cluster
        run: ./scripts/kind/01-create-cluster.sh

      - name: Install ArgoCD
        run: ./scripts/kind/02-install-argocd.sh

      - name: Bootstrap applications
        run: ./scripts/kind/03-bootstrap-apps.sh

      - name: Install test dependencies
        run: |
          cd tests/integration
          pip install -r requirements.txt

      - name: Run infrastructure tests
        run: |
          cd tests/integration
          pytest test_infrastructure.py -v --junitxml=junit-infrastructure.xml

      - name: Run observability tests
        run: |
          cd tests/integration
          pytest test_observability.py -v --junitxml=junit-observability.xml

      - name: Run platform tests
        run: |
          cd tests/integration
          pytest test_platform.py -v --junitxml=junit-platform.xml

      - name: Run agent tests
        run: |
          cd tests/integration
          pytest test_agents.py -v --junitxml=junit-agents.xml

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: tests/integration/*.xml
```

---

## Known Issues and Expected Failures

Tests marked with `@pytest.mark.xfail` document known issues:

1. **test_kagenti_operator_healthy**: kagenti-operator image not published (P0)
   - See: ISSUES.md Issue #1

2. **test_grafana_healthy**: Grafana OIDC secret missing (P2)
   - See: ISSUES.md Issue #3

3. **test_research_agent_healthy**: Agent images not built/pushed to registry
   - Requires: Build and push agent container images

4. **test_code_agent_healthy**: Agent images not built/pushed to registry
   - Requires: Build and push agent container images

5. **test_orchestrator_agent_healthy**: Agent images not built/pushed to registry
   - Requires: Build and push agent container images

---

## Troubleshooting

### Test Failures

#### ArgoCD application not synced

**Symptom**: `Application 'platform' is not synced`

**Fix**:
```bash
argocd app sync platform --force --port-forward --grpc-web
```

#### Pod not ready within timeout

**Symptom**: `Pod 'phoenix-xxx' not ready after 300s`

**Diagnosis**:
```bash
kubectl get pods -n observability
kubectl describe pod phoenix-xxx -n observability
kubectl logs -n observability phoenix-xxx
```

**Fix**:
- Increase test timeout: `pytest --timeout=600`
- Check pod events for image pull errors

#### Phoenix GraphQL query fails

**Symptom**: `Connection refused` to Phoenix API

**Diagnosis**:
```bash
kubectl port-forward -n observability svc/phoenix 6006:6006
curl http://localhost:6006/graphql
```

**Fix**:
- Ensure Phoenix pod is running
- Check Phoenix logs for startup errors

### Test Environment Issues

#### kubectl context wrong

**Symptom**: `Cluster not found`

**Fix**:
```bash
kubectl config use-context kind-kagenti-demo
```

#### Python dependencies missing

**Symptom**: `ImportError for pytest, kubernetes, etc.`

**Fix**:
```bash
pip install -r requirements.txt --force-reinstall
```

#### ArgoCD port-forward fails

**Symptom**: argocd CLI commands hang

**Fix**:
```bash
pkill -f "kubectl port-forward.*argocd"
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
```

---

## Contributing

When adding new tests:

1. Follow existing test structure and naming conventions
2. Use descriptive test names: `test_<component>_<what_is_tested>`
3. Add docstrings explaining what the test validates
4. Mark expected failures with `@pytest.mark.xfail(reason="...")`
5. Group related tests into classes
6. Update this README with new test coverage

---

## References

- [Integration Test Strategy Documentation](../../docs/INTEGRATION_TESTS.md)
- [ArgoCD Health Checks](../../TODO_ARGOCD_HEALTH_CHECKS.md)
- [Monitoring Agents Implementation Plan](../../../agent-examples-local/TODO_monitoring_agents.md)
- [Platform Issues](../../ISSUES.md)
- [pytest Documentation](https://docs.pytest.org/)
- [Kubernetes Python Client](https://github.com/kubernetes-client/python)
