# Kagenti Platform Test Suite

Comprehensive test suite for validating the Kagenti platform deployment, services, and operational health.

## 📁 Test Structure

```
tests/
├── README.md                           # This file
├── conftest.py                         # Shared pytest fixtures
├── integration/                        # Integration tests for services
│   ├── test_infrastructure.py         # Gateway API, cert-manager, Tekton, Istio
│   ├── test_platform.py               # Keycloak, operators, platform services
│   ├── test_observability.py          # Grafana, Tempo, Phoenix, Kiali
│   └── test_agents.py                 # Agent creation and conversations
└── validation/                        # Validation tests for operational health
    ├── test_app_state.py              # ArgoCD application health validation
    └── test_log_trace_errors.py       # Log and trace error scanning
```

## 🧪 Test Categories

### Integration Tests (`tests/integration/`)

**Purpose**: Validate that deployed services are functioning correctly and can communicate with each other.

**Coverage**:
- Infrastructure: Gateway API, cert-manager, Tekton, Istio (16 tests)
- Platform: Keycloak, operators, CRDs (15 tests)
- Observability: Grafana, Tempo, Phoenix, Kiali (19 tests)
- Agents: Agent creation, conversations, tool execution (14 tests)

**Usage**:
```bash
# Run all integration tests
pytest tests/integration/ -v

# Run specific component
pytest tests/integration/test_observability.py -v

# Skip slow tests
pytest tests/integration/ -v -m "not slow"
```

### Validation Tests (`tests/validation/`)

**Purpose**: Validate operational health and detect issues across the platform.

**Coverage**:
- **App State Validation**: Ensures all ArgoCD applications are Synced and Healthy
- **Log/Trace Error Scanning**: Detects unexpected errors and warnings in logs and traces

**Usage**:
```bash
# Validate all ArgoCD applications
pytest tests/validation/test_app_state.py -v

# Quick validation (critical apps only)
pytest tests/validation/test_app_state.py -v --only-critical

# Scan for errors and warnings
pytest tests/validation/test_log_trace_errors.py -v

# Generate summary report
pytest tests/validation/test_log_trace_errors.py::test_generate_error_warning_summary -v -s
```

## 🚀 Quick Start

### Prerequisites

```bash
# Install dependencies
pip install -r requirements-test.txt

# Ensure cluster is running
kubectl cluster-info

# Ensure ArgoCD is deployed
kubectl get applications -n argocd
```

### Running Tests

```bash
# Full test suite (all tests)
pytest tests/ -v --html=report.html

# Fast validation (~30s)
pytest tests/validation/test_app_state.py -v --only-critical

# Integration tests only (~2m)
pytest tests/integration/ -v -m "not slow"

# Specific test
pytest tests/integration/test_observability.py::test_grafana_accessible -v

# Watch mode (re-run on changes)
pytest tests/integration/ -v -f
```

### Test Markers

Use pytest markers to control test execution:

```bash
# Skip slow tests
pytest -m "not slow"

# Run only xfail tests to check if they pass now
pytest -m "xfail"

# Run critical tests only
pytest -m "critical"
```

## 📊 Test Reports

### HTML Report

```bash
pytest tests/ -v --html=report.html --self-contained-html
open report.html
```

### JSON Report

```bash
pytest tests/ -v --json-report --json-report-file=report.json
cat report.json | jq '.summary'
```

### JUnit XML (for CI/CD)

```bash
pytest tests/ -v --junitxml=junit.xml
```

## 🔧 Configuration

### Environment Variables

```bash
# Custom namespace scanning for log validation
export NAMESPACES_TO_SCAN="kagenti-system,observability,custom-namespace"

# Custom timeout for tests
export TEST_TIMEOUT=300

# Enable debug output
export PYTEST_DEBUG=1
```

### Custom Ignore Patterns

Edit acceptable error/warning patterns in `tests/validation/test_log_trace_errors.py`:

```python
ACCEPTABLE_ERRORS = [
    r"Your custom error pattern here",
    # ...
]

ACCEPTABLE_WARNINGS = [
    r"Your custom warning pattern here",
    # ...
]
```

## 🎯 Test-Driven Development Workflow

**Always write tests before making changes:**

```bash
# 1. Baseline validation
pytest tests/validation/test_app_state.py -v --only-critical

# 2. Write test for your change
vim tests/integration/test_observability.py

# 3. Run test (should fail - Red)
pytest tests/integration/test_observability.py::test_new_feature -v

# 4. Make the change
vim components/02-observability/grafana/deployment.yaml
git add components/02-observability/
git commit -m "Add new Grafana dashboard"
git push origin feature/grafana-dashboard

# 5. Sync via ArgoCD
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# 6. Run test (should pass - Green)
pytest tests/integration/test_observability.py::test_new_feature -v

# 7. Full validation
pytest tests/ -v
```

## 📝 Writing Tests

### Test File Template

```python
"""
Test suite for <component> functionality.
"""
import pytest
from kubernetes import client

@pytest.fixture(scope="module")
def component_deployment(k8s_apps_client):
    """Get the component deployment."""
    return k8s_apps_client.read_namespaced_deployment(
        name="component-name",
        namespace="component-namespace"
    )

def test_component_is_deployed(component_deployment):
    """Test that component is deployed successfully."""
    assert component_deployment is not None
    assert component_deployment.status.ready_replicas >= 1

def test_component_functionality():
    """Test that component performs its core function."""
    # Test implementation
    pass
```

### Best Practices

1. **Use descriptive test names**: `test_grafana_dashboard_loads` not `test_1`
2. **One assertion per test**: Each test should verify one specific behavior
3. **Use fixtures for setup**: Avoid duplicating setup code
4. **Mark slow tests**: Use `@pytest.mark.slow` for tests >5s
5. **Use xfail for known issues**: `@pytest.mark.xfail(reason="...")`
6. **Add retries for flaky tests**: Use `@pytest.mark.flaky(reruns=3)`

## 🐛 Debugging Tests

### Run with verbose output

```bash
pytest tests/integration/test_platform.py -v -s
```

### Run specific test with pdb debugger

```bash
pytest tests/integration/test_platform.py::test_keycloak_accessible -v --pdb
```

### Show local variables on failure

```bash
pytest tests/integration/ -v -l
```

### Capture output

```bash
pytest tests/integration/ -v --capture=no
```

## 🔄 CI/CD Integration

Tests run automatically in GitHub Actions on every push and PR.

### App State Validation Workflow

**File**: `.github/workflows/app-state-validation.yml`

**Triggers**:
- Push to `main` or `argocd-gitops-dev`
- Pull requests

**Steps**:
1. Create Kind cluster
2. Install ArgoCD
3. Bootstrap applications
4. Sync in waves
5. Run validation tests
6. Generate report

### Running Locally (Simulate CI)

```bash
# Clean environment
./scripts/kind/00-cleanup.sh

# Setup cluster
./scripts/kind/01-create-cluster.sh
./scripts/kind/02-install-argocd.sh
./scripts/kind/03-bootstrap-apps.sh

# Sync applications
argocd app sync gateway-api cert-manager tekton istio-base istiod --port-forward --port-forward-namespace argocd --grpc-web

# Wait for stability
sleep 30

# Run tests
pytest tests/validation/test_app_state.py -v
pytest tests/integration/ -v
pytest tests/validation/test_log_trace_errors.py -v
```

## 📚 Related Documentation

- **[TODO_TESTS.md](../TODO_TESTS.md)** - Testing roadmap and tracking
- **[docs/INTEGRATION_TESTS.md](../docs/INTEGRATION_TESTS.md)** - Testing strategy and architecture
- **[CLAUDE.md](../CLAUDE.md)** - Test-driven development workflow

## 🆘 Troubleshooting

### Tests fail with "connection refused"

**Cause**: Service not ready or port-forward died

**Solution**:
```bash
# Check pods are running
kubectl get pods -n observability

# Manually test port-forward
kubectl port-forward -n observability service/grafana 3000:3000
curl http://localhost:3000
```

### Tests timeout

**Cause**: Cluster resources constrained or service slow to start

**Solution**:
```bash
# Increase timeout
pytest tests/integration/ -v --timeout=300

# Check cluster resources
kubectl top nodes
kubectl top pods -A
```

### Import errors

**Cause**: Missing dependencies

**Solution**:
```bash
pip install -r requirements-test.txt
```

### Kubernetes client errors

**Cause**: Kubeconfig not set or wrong context

**Solution**:
```bash
# Check context
kubectl config current-context

# Should be: kind-kagenti-demo
kubectl config use-context kind-kagenti-demo
```

## 📈 Test Coverage Goals

- **Integration Tests**: 80%+ coverage of all services
- **Validation Tests**: 100% of ArgoCD applications validated
- **Error Detection**: Zero unexpected errors/warnings
- **CI/CD**: All tests passing on main branch

## 🎯 Current Status

✅ **Completed**:
- Infrastructure integration tests (16 tests)
- Observability integration tests (19 tests)
- Platform integration tests (15 tests)
- App state validation (comprehensive)
- Log/trace error scanning (comprehensive)

🚧 **In Progress**:
- Agent integration tests (14 tests - pending agent deployment)
- Performance benchmarks
- Load testing

📋 **Planned**:
- Chaos engineering tests
- Security validation tests
- Multi-cluster tests
- Upgrade/rollback tests

See [TODO_TESTS.md](../TODO_TESTS.md) for detailed roadmap.
