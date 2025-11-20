---
name: tdd-workflow
description: Test-driven development workflow for the Kagenti platform - validation, testing, and TDD approach for platform changes
---

# TDD Workflow Skill

This skill guides you through test-driven development for platform changes.

## When to Use

- Before making platform changes (write test first)
- After making changes (validate with tests)
- Investigating test failures
- Adding new components (TDD approach)

## TDD Workflow

### 1. Write Test First

```bash
# Create test for new functionality
vim tests/integration/test_new_feature.py
```

### 2. Validate Syntax BEFORE Committing

```bash
# Validate kustomize builds successfully
kustomize build components/<path>/ > /dev/null

# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('file.yaml'))"
```

### 3. Commit and Push

```bash
git add components/ tests/
git commit -m "Add new feature with tests"
git push
```

### 4. Sync from Git

```bash
argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web
```

### 5. Validate Deployment

```bash
# Check platform status
./scripts/platform-status.sh
```

### 6. Run Tests

```bash
# Fast validation (critical apps only, ~30s)
pytest tests/validation/test_app_state.py -v --only-critical

# Specific component tests
pytest tests/integration/test_<component>.py -v

# Full test suite
pytest tests/ -v --html=report.html
```

## Quick Test Commands

```bash
# Platform health check (includes pytest)
./scripts/platform-status.sh

# Critical apps validation
pytest tests/validation/test_app_state.py -v --only-critical

# Observability tests
pytest tests/integration/test_observability.py -v

# Platform tests
pytest tests/integration/test_platform.py -v

# Specific test
pytest tests/integration/test_observability.py::test_grafana_accessible -v

# Generate HTML report
pytest tests/ -v --html=report.html --self-contained-html
```

## Test Categories

**App State Validation** (`tests/validation/test_app_state.py`):
- Validates ALL ArgoCD applications Healthy and Synced
- Critical apps: gateway-api, cert-manager, istio, tekton, keycloak, operators, platform, UI
- Optional apps: observability, kiali, ollama

**Integration Tests** (`tests/integration/`):
- test_observability.py: Grafana, Prometheus, Loki, Tempo
- test_platform.py: Keycloak, OAuth2-Proxy, Gateway
- test_infrastructure.py: Cert-manager, Tekton, ArgoCD

**E2E Tests** (`tests/e2e/`):
- test_platform_e2e.py: End-to-end workflows

## Test Markers

```bash
# Run only critical tests
pytest -m critical -v

# Run only observability tests
pytest -m observability -v

# Run only platform tests
pytest -m platform -v

# Skip slow tests
pytest -m "not slow" -v
```

## Related Skills

- **gitops-workflow**: Making changes via Git
- **platform-health**: Platform health checks

🤖 Generated with [Claude Code](https://claude.com/claude-code)
