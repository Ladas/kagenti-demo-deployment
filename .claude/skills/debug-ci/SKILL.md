---
name: debug-ci
description: Debug CI/CD failures in GitHub Actions - download artifacts, analyze test failures, and investigate CI-specific issues
---

# Debug CI Skill

## When to Use

- GitHub Actions CI failing
- Tests pass locally but fail in CI
- Need to analyze CI artifacts
- Investigating CI timeout issues

## Quick Status Check

```bash
# View latest CI runs
gh run list --repo redhat-et/kagenti-demo-deployment --limit 5

# Watch run in real-time
gh run watch <run-id> --repo redhat-et/kagenti-demo-deployment

# View run summary
gh run view <run-id> --repo redhat-et/kagenti-demo-deployment
```

## Download CI Artifacts

```bash
# List artifacts
gh run view <run-id> --repo redhat-et/kagenti-demo-deployment --json artifacts

# Download crash logs
gh run download <run-id> --name crash-debug-logs --dir /tmp/ci-debug \
  --repo redhat-et/kagenti-demo-deployment

# Examine logs
ls -lah /tmp/ci-debug/
```

## Analyze Failures

```bash
# Find CrashLoopBackOff pods
grep -r "CrashLoopBackOff" /tmp/ci-debug/all-events.txt

# Check operator errors
grep -i "error\|failed\|panic" /tmp/ci-debug/*-operator-all.log

# Check image pull issues
grep -i "ImagePullBackOff" /tmp/ci-debug/all-events.txt

# Check degraded ArgoCD apps
cat /tmp/ci-debug/argocd-applications.yaml | \
  yq eval '.items[] | select(.status.health.status != "Healthy") | .metadata.name'
```

## Common CI Failure Patterns

**Pattern 1: Timeout < 5 minutes**
- Likely: Operator CrashLoopBackOff or Tekton failure
- Check: operator logs, CRD creation

**Pattern 2: Timeout after 60 minutes**
- Likely: Slow image pulls, resource constraints
- Check: image pull events, resource usage

**Pattern 3: Tests pass but E2E fails**
- Likely: Apps excluded from validation
- Check: EXCLUDE_APPS in workflow

## Compare Local vs CI

```bash
# Run same checks as CI locally
./scripts/platform-status.sh

# Run pytest with same flags
pytest tests/validation/test_app_state.py -v --html=report.html

# Compare ArgoCD status
kubectl get applications -n argocd -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.health.status)"'
```

## Related Skills

- **platform-health**: Health checks
- **tdd-workflow**: Running tests

🤖 Generated with [Claude Code](https://claude.com/claude-code)
