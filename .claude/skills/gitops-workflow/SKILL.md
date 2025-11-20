---
name: gitops-workflow
description: GitOps development workflow - making changes via Git, ArgoCD sync, validation, and force sync options for the Kagenti platform
---

# GitOps Workflow Skill

This skill guides you through the GitOps development workflow for making changes to the Kagenti platform.

## When to Use

- Making ANY changes to platform configuration
- Deploying new components
- Updating existing deployments
- Modifying ConfigMaps, Secrets, or other resources
- Before running `kubectl apply` (don't! Use GitOps instead)

## Core Philosophy

**ALL changes to the Kind cluster happen via ArgoCD syncing from Git**. This ensures:
- ✅ Every change is tracked in Git
- ✅ No configuration drift
- ✅ Reproducible deployments
- ✅ Easy rollback
- ✅ Branch-based development

**🚫 No `kubectl apply` allowed** (except for ArgoCD installation and debugging only).

## Standard GitOps Workflow

### 1. Create Feature Branch

```bash
# Create and switch to feature branch
git checkout -b feature/update-grafana
```

### 2. Make Changes

```bash
# Edit configuration files
vim components/02-observability/grafana/deployment.yaml

# Or for multiple files
vim components/02-observability/grafana/*.yaml
```

### 3. Validate BEFORE Committing

**CRITICAL: Always validate before committing!**

```bash
# Validate kustomize builds successfully
kustomize build components/02-observability/grafana/ > /dev/null

# If using overlays
kustomize build components/02-observability/grafana/overlays/kind/ > /dev/null

# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('path/to/file.yaml'))"

# Check for trailing whitespace, tabs, etc.
git diff --check
```

**Common validation errors**:
- YAML syntax errors (indentation, missing colons)
- Invalid field names
- Missing required fields
- Incorrect kustomization.yaml references

### 4. Preview Changes (Optional)

```bash
# See what ArgoCD will change BEFORE committing
argocd app diff observability --port-forward --port-forward-namespace argocd --grpc-web

# Output shows:
# - Resources to be created (green +)
# - Resources to be modified (yellow ~)
# - Resources to be deleted (red -)
```

### 5. Commit and Push

```bash
# Add changes
git add components/02-observability/

# Commit with descriptive message
git commit -m "Update Grafana image to v10.2.0

- Upgrade from v10.1.5 to v10.2.0
- Add new dashboard for Istio metrics
- Update datasource configuration for Loki
"

# Push to remote
git push origin feature/update-grafana
```

**Good commit messages**:
- First line: Brief summary (< 72 chars)
- Blank line
- Detailed explanation of what/why

### 6. Sync from Git

```bash
# Normal sync (recommended)
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# Sync with timeout (for slow deployments)
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web --timeout 300

# Sync and wait for health
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web --wait

# Sync specific resource only
argocd app sync observability --resource Deployment:grafana --port-forward --port-forward-namespace argocd --grpc-web
```

### 7. Verify Deployment

```bash
# Check application status
argocd app get observability --port-forward --port-forward-namespace argocd --grpc-web

# Check pod status
kubectl get pods -n observability

# Check logs
kubectl logs -n observability deployment/grafana --tail=50

# Run platform status check
./scripts/platform-status.sh
```

### 8. Run Tests

```bash
# Run targeted tests
pytest tests/integration/test_observability.py::test_grafana_dashboard -v

# Or full validation
pytest tests/validation/test_app_state.py -v
```

### 9. Merge When Ready

```bash
# Switch to main branch
git checkout main

# Merge feature branch
git merge feature/update-grafana

# Push to main
git push origin main

# Sync main branch (if needed)
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
```

## Force Sync Options

### When to Use Force Sync

**Use `--force`** when:
- ArgoCD shows "OutOfSync" but changes don't apply
- StatefulSet pods not recreating after config change
- Need to bypass ArgoCD's sync optimizations
- Previous sync failed midway

**Use `--prune`** when:
- Need to delete resources removed from Git
- Cleaning up orphaned resources
- Ensuring cluster matches Git exactly

**Use `--force --prune` together** (nuclear option) when:
- Complete rebuild required
- Significant drift between Git and cluster
- Previous sync strategies failed

### Force Sync Commands

```bash
# Force sync (bypass cache)
argocd app sync observability --force \
  --port-forward --port-forward-namespace argocd --grpc-web

# Hard sync (force + prune orphaned resources)
argocd app sync observability --force --prune \
  --port-forward --port-forward-namespace argocd --grpc-web

# Force sync all applications (use with caution!)
argocd app list -o name --port-forward --port-forward-namespace argocd --grpc-web | \
  xargs -I {} argocd app sync {} --force --port-forward --port-forward-namespace argocd --grpc-web
```

**⚠️ Warning**: `--force --prune` will delete resources not in Git. Use carefully!

## ArgoCD Application Management

### Check Application Status

```bash
# List all applications
argocd app list --port-forward --port-forward-namespace argocd --grpc-web

# Get specific app details
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Check sync status only
argocd app get <app-name> -o json --port-forward --port-forward-namespace argocd --grpc-web | \
  jq -r '.status.sync.status'

# Check health status only
argocd app get <app-name> -o json --port-forward --port-forward-namespace argocd --grpc-web | \
  jq -r '.status.health.status'
```

### View Sync History

```bash
# See previous syncs
argocd app history <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Output shows:
# - Revision (Git commit SHA)
# - Date
# - Author
# - Message
```

### Rollback to Previous Version

```bash
# List history to find revision ID
argocd app history <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Rollback to specific revision
argocd app rollback <app-name> <revision-id> \
  --port-forward --port-forward-namespace argocd --grpc-web

# Example: Rollback to revision 5
argocd app rollback observability 5 \
  --port-forward --port-forward-namespace argocd --grpc-web
```

### Compare Git vs Cluster

```bash
# See differences between Git and cluster
argocd app diff <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Save diff to file
argocd app diff <app-name> --port-forward --port-forward-namespace argocd --grpc-web > /tmp/diff.txt

# Show only resource names
argocd app diff <app-name> --port-forward --port-forward-namespace argocd --grpc-web | \
  grep "^====" | awk '{print $2}'
```

## Branch-Based Development

### Working on Multiple Features

```bash
# Feature 1: Update Grafana
git checkout -b feature/grafana-upgrade
# ... make changes, commit, push
git checkout main

# Feature 2: Add new alert
git checkout -b feature/new-alert
# ... make changes, commit, push
git checkout main

# ArgoCD can track different branches per app
argocd app set <app-name> --revision feature/grafana-upgrade \
  --port-forward --port-forward-namespace argocd --grpc-web
```

### Testing Changes in Isolation

```bash
# Create test branch
git checkout -b test/experimental-feature

# Make changes and commit
# ... edit files ...
git add .
git commit -m "Experimental: Test new feature"
git push origin test/experimental-feature

# Point ArgoCD app to test branch
argocd app set observability --revision test/experimental-feature \
  --port-forward --port-forward-namespace argocd --grpc-web

# Sync to deploy
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# When done testing, switch back to main
argocd app set observability --revision main \
  --port-forward --port-forward-namespace argocd --grpc-web
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
```

## Common Workflows

### Update Container Image

```bash
# 1. Edit deployment
vim components/02-observability/grafana/deployment.yaml
# Change image: grafana/grafana:10.1.5 → grafana/grafana:10.2.0

# 2. Validate
kustomize build components/02-observability/grafana/ > /dev/null

# 3. Commit and push
git add components/02-observability/grafana/deployment.yaml
git commit -m "Update Grafana image to v10.2.0"
git push

# 4. Sync
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# 5. Verify
kubectl get pods -n observability -l app=grafana
kubectl logs -n observability deployment/grafana --tail=20
```

### Add New ConfigMap

```bash
# 1. Create ConfigMap file
cat > components/02-observability/grafana/custom-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-custom-config
  namespace: observability
data:
  custom.ini: |
    [custom]
    setting = value
EOF

# 2. Add to kustomization.yaml
vim components/02-observability/grafana/kustomization.yaml
# Add under resources:
# - custom-config.yaml

# 3. Validate
kustomize build components/02-observability/grafana/ > /dev/null

# 4. Commit and sync
git add components/02-observability/grafana/
git commit -m "Add custom Grafana configuration"
git push
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
```

### Delete Resource

```bash
# 1. Remove from kustomization.yaml
vim components/02-observability/grafana/kustomization.yaml
# Remove resource reference

# 2. Commit
git add components/02-observability/grafana/kustomization.yaml
git commit -m "Remove deprecated ConfigMap"
git push

# 3. Sync with --prune to delete
argocd app sync observability --prune \
  --port-forward --port-forward-namespace argocd --grpc-web
```

## Emergency: Quick Fix in Production

**When you need to apply a hotfix immediately**:

```bash
# 1. Make change and commit
vim components/02-observability/grafana/deployment.yaml
git add components/02-observability/grafana/deployment.yaml
git commit -m "HOTFIX: Increase Grafana memory limit"
git push

# 2. Force sync with short timeout
argocd app sync observability --force --timeout 60 \
  --port-forward --port-forward-namespace argocd --grpc-web

# 3. Verify immediately
kubectl get pods -n observability -l app=grafana -w

# 4. Check logs for errors
kubectl logs -n observability deployment/grafana --tail=50 -f
```

## Troubleshooting GitOps Issues

### Issue: ArgoCD shows OutOfSync but sync doesn't fix it

```bash
# Try force sync
argocd app sync <app-name> --force --port-forward --port-forward-namespace argocd --grpc-web

# If still fails, check app details
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Look for error messages in status
argocd app get <app-name> -o json --port-forward --port-forward-namespace argocd --grpc-web | \
  jq -r '.status.conditions[] | .message'
```

### Issue: Changes not applying

```bash
# 1. Verify Git commit is on remote
git log --oneline -5
git push  # If needed

# 2. Check ArgoCD is tracking correct branch/commit
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web | \
  grep "Repo:\|Revision:"

# 3. Refresh ArgoCD cache
argocd app get <app-name> --refresh --port-forward --port-forward-namespace argocd --grpc-web

# 4. Force sync
argocd app sync <app-name> --force --port-forward --port-forward-namespace argocd --grpc-web
```

### Issue: Webhook errors during sync

```bash
# Common with operators (cert-manager, tekton, istio)
# Error: "failed calling webhook..."

# Solution: Retry sync (webhooks may not be ready)
argocd app sync <app-name> --retry-limit 5 \
  --port-forward --port-forward-namespace argocd --grpc-web

# Or use --force to bypass some validations
argocd app sync <app-name> --force \
  --port-forward --port-forward-namespace argocd --grpc-web
```

## Related Skills

- **tdd-workflow**: Test-driven development and validation
- **deploy-cluster**: Full cluster deployment
- **troubleshoot-argocd**: ArgoCD-specific troubleshooting

## Related Documentation

- [CLAUDE.md](../../../CLAUDE.md) - Main workflow documentation
- [argocd_architecture.md](../../../argocd_architecture.md) - ArgoCD architecture
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

## GitOps Best Practices

1. **Always validate before commit**: Use `kustomize build` to catch errors early
2. **Write descriptive commit messages**: Explain what and why
3. **Use feature branches**: Isolate changes for testing
4. **Preview with diff**: Check changes before syncing
5. **Test after sync**: Run integration tests to verify
6. **Document breaking changes**: In commit message or PR description
7. **Use --prune carefully**: Understand what will be deleted

🤖 Generated with [Claude Code](https://claude.com/claude-code)
