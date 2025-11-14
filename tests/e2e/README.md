# End-to-End Tests for Kagenti Platform

This directory contains end-to-end tests for the complete Kagenti platform deployment.

## Test Coverage

The E2E test suite validates:

### ✅ Infrastructure Layer (Wave 0)
- ArgoCD server health
- Cert-Manager installation
- Tekton Pipelines controller
- Gateway API CRDs

### ✅ Service Mesh & Infrastructure Services (Wave 5)
- Istio control plane (istiod)
- Keycloak identity provider
- Container registry
- Kiali service mesh dashboard

### ✅ Kubernetes Operators (Wave 10)
- platform-operator (agentic-platform-controller-manager)
- Platform CRDs (Platform, Component, Agent, AgentBuild, AgentCard)
- kagenti-operator (marked as `xfail` - image not published)

### ✅ Platform Services (Wave 15)
- Kagenti UI deployment
- OAuth2 configuration Job
- External Gateway configuration
- TLS certificates (localtest.me)

### ✅ Observability Stack (Wave 20)
- Jaeger distributed tracing
- Tempo trace aggregation
- OpenTelemetry Collector
- Phoenix observability UI
- Grafana (marked as `xfail` - OIDC secret missing)

### ⏸️ Agent Deployment (Wave 25)
- research-agent (marked as `xfail` - image not built)
- code-agent (marked as `xfail` - image not built)
- orchestrator-agent (marked as `xfail` - image not built)

### ✅ ArgoCD Applications
- Application existence checks
- Sync status validation
- Health status checks

### ✅ Overall Platform Health
- No CrashLoopBackOff pods
- >80% pod health threshold
- All deployments have ready replicas

## Prerequisites

### Local Testing

1. **Kind cluster with Kagenti platform deployed**
   ```bash
   ./scripts/kind/01-create-cluster.sh
   ./scripts/kind/02-install-argocd.sh
   ./scripts/kind/03-bootstrap-apps.sh
   ```

2. **Python 3.11+**
   ```bash
   python --version  # Should be 3.11 or higher
   ```

3. **kubectl configured**
   ```bash
   kubectl config current-context  # Should be: kind-kagenti-demo
   ```

4. **ArgoCD CLI installed**
   ```bash
   argocd version --client
   ```

## Installation

Install test dependencies:

```bash
cd tests/e2e
pip install -r requirements.txt
```

## Usage

### Run All Tests

```bash
pytest test_platform.py -v
```

### Run Specific Test Class

```bash
# Test only infrastructure components
pytest test_platform.py::TestInfrastructure -v

# Test only observability stack
pytest test_platform.py::TestObservability -v

# Test only operators
pytest test_platform.py::TestOperators -v
```

### Run Specific Test

```bash
pytest test_platform.py::TestInfrastructure::test_argocd_healthy -v
```

### Generate HTML Report

```bash
pytest test_platform.py -v --html=report.html --self-contained-html
```

### Run with Detailed Output

```bash
pytest test_platform.py -v -s
```

### Skip xFail Tests

```bash
pytest test_platform.py -v --runxfail=no
```

### Run Only Failed Tests from Last Run

```bash
pytest test_platform.py -v --lf
```

## GitHub Actions

The tests run automatically in GitHub Actions on:
- Push to `main` or `argocd-gitops-dev` branches
- Pull requests to `main`
- Manual workflow trigger

See `.github/workflows/e2e-tests.yaml` for the full CI pipeline.

## Test Results Interpretation

### Exit Codes
- `0`: All tests passed
- `1`: Some tests failed
- `2`: Test execution was interrupted
- `3`: Internal error occurred
- `4`: pytest command line usage error
- `5`: No tests were collected

### Test Markers

- ✅ **PASSED**: Test passed successfully
- ❌ **FAILED**: Test failed - indicates a problem
- ⏭️ **SKIPPED**: Test skipped (not applicable in current environment)
- ⚠️ **xFAIL**: Test expected to fail (known issue documented in ISSUES.md)
- 🎉 **xPASS**: Test expected to fail but passed (issue may be resolved!)

### Known Expected Failures (xFail)

These tests are marked with `@pytest.mark.xfail` and document known issues:

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

## Troubleshooting

### Test Hangs or Times Out

Increase pytest timeout:
```bash
pytest test_platform.py -v --timeout=600  # 10 minutes
```

### Connection Refused to ArgoCD

Ensure ArgoCD server is running:
```bash
kubectl get pods -n argocd
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

### Kubernetes API Permission Errors

Ensure your kubeconfig has proper permissions:
```bash
kubectl auth can-i --list
```

### Import Errors

Reinstall dependencies:
```bash
pip install -r requirements.txt --force-reinstall
```

## Contributing

When adding new tests:

1. Follow the existing test structure
2. Use descriptive test names: `test_<component>_<what_is_tested>`
3. Add docstrings explaining what the test validates
4. Mark expected failures with `@pytest.mark.xfail(reason="...")`
5. Group related tests into classes
6. Update this README with new test coverage

## Reference

- [pytest Documentation](https://docs.pytest.org/)
- [Kubernetes Python Client](https://github.com/kubernetes-client/python)
- [ArgoCD API](https://argo-cd.readthedocs.io/en/stable/developer-guide/api-docs/)
- [Kagenti Platform Issues](../../ISSUES.md)
- [Deployment Status](../../DEPLOYMENT_STATUS.md)
