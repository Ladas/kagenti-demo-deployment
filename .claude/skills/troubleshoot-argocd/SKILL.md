---
name: troubleshoot-argocd
description: Troubleshoot ArgoCD application issues - OutOfSync, Degraded health, sync failures, and ArgoCD-specific problems
---

# Troubleshoot ArgoCD Skill

## When to Use

- ArgoCD app stuck OutOfSync
- App health Degraded/Progressing
- Sync failures
- Webhook errors during sync

## Check ArgoCD Status

```bash
# List all apps with status
argocd app list --port-forward --port-forward-namespace argocd --grpc-web

# Get app details
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Check for unhealthy apps
argocd app list --port-forward --port-forward-namespace argocd --grpc-web | \
  grep -E "Degraded|OutOfSync|Unknown"
```

## App Stuck OutOfSync

```bash
# 1. Check what's different
argocd app diff <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# 2. Refresh cache
argocd app get <app-name> --refresh --port-forward --port-forward-namespace argocd --grpc-web

# 3. Force sync
argocd app sync <app-name> --force --port-forward --port-forward-namespace argocd --grpc-web

# 4. Hard sync (force + prune)
argocd app sync <app-name> --force --prune --port-forward --port-forward-namespace argocd --grpc-web
```

## Sync Failures

```bash
# Check error messages
argocd app get <app-name> -o json --port-forward --port-forward-namespace argocd --grpc-web | \
  jq -r '.status.conditions[] | .message'

# View sync history
argocd app history <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Retry with increased timeout
argocd app sync <app-name> --timeout 300 --port-forward --port-forward-namespace argocd --grpc-web
```

## Webhook Errors

**Error**: `failed calling webhook...`

```bash
# Retry sync (webhooks may not be ready)
argocd app sync <app-name> --retry-limit 5 --port-forward --port-forward-namespace argocd --grpc-web

# Or force to bypass some validations
argocd app sync <app-name> --force --port-forward --port-forward-namespace argocd --grpc-web
```

## App Health Degraded

```bash
# Check which resources are unhealthy
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web | \
  grep -E "Health|Status"

# Check pod status
kubectl get pods -n <namespace>

# Force restart deployment
kubectl rollout restart deployment/<name> -n <namespace>
```

## Rollback

```bash
# List history
argocd app history <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Rollback to specific revision
argocd app rollback <app-name> <revision-id> \
  --port-forward --port-forward-namespace argocd --grpc-web
```

## Related Skills

- **gitops-workflow**: GitOps best practices
- **platform-health**: Health checks

🤖 Generated with [Claude Code](https://claude.com/claude-code)
