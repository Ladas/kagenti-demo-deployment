---
name: deploy-cluster
description: Deploy or redeploy the Kagenti Kind cluster - quick redeploy, manual steps, and troubleshooting cluster deployment
---

# Deploy Cluster Skill

This skill guides you through deploying or redeploying the Kagenti Kind cluster.

## When to Use

- Setting up new cluster
- Full cluster redeploy after major changes
- Cluster is corrupted or unstable
- Testing clean deployment

## Quick Redeploy

```bash
# One-command complete redeploy (15-20 minutes)
./scripts/quick-redeploy.sh
```

**What it does:**
1. Auto-detects repository and branch
2. Destroys existing cluster
3. Creates new Kind cluster
4. Installs ArgoCD
5. Bootstraps applications
6. Optionally builds/loads agent images
7. Syncs root application
8. Shows final status

**Branch Detection:**
- Local: Uses current Git branch
- GitHub Actions PR: Uses PR branch and fork
- Default: Falls back to `main`

**Agent images prompt (local only):**
- `y` - Build from source (2-5 minutes)
- `n` - Load pre-built images (30 seconds)
- `skip` - Skip agents
- CI mode: Automatically skips

## Manual Step-by-Step Deployment

```bash
# 1. Cleanup existing cluster
./scripts/kind/00-cleanup.sh

# 2. Create Kind cluster
./scripts/kind/01-create-cluster.sh

# 3. Install ArgoCD
./scripts/kind/02-install-argocd.sh

# 4. Bootstrap applications
./scripts/kind/03-bootstrap-apps.sh

# 5. Optional: Load agent images
./scripts/kind/04-load-agent-images.sh build  # or 'load'

# 6. Sync root application
argocd app sync kagenti-platform-kind \
  --port-forward --port-forward-namespace argocd --grpc-web \
  --timeout 600

# 7. Monitor deployment
./scripts/monitor-argocd-apps.sh 900  # 15-minute timeout
```

## Check Deployment Health

```bash
# Comprehensive platform status
./scripts/platform-status.sh
```

**Checks:**
- ArgoCD applications (health & sync)
- Platform pods
- Gateway & certificates
- Istio mTLS
- Service accessibility
- OAuth authentication
- Integration tests

## Capture Deployment Snapshot

```bash
# Create timestamped snapshot
./scripts/capture-platform-snapshot.sh before-redeploy

# With E2E tests
RUN_E2E_TESTS=true ./scripts/capture-platform-snapshot.sh full-validation
```

## Troubleshooting Deployment

**Pods stuck in ImagePullBackOff**:
```bash
# Check image availability
docker exec kagenti-demo-control-plane crictl images | grep <image>

# Load missing images
./scripts/kind/04-load-agent-images.sh load
```

**ArgoCD app stuck OutOfSync**:
```bash
# Force sync
argocd app sync <app-name> --force --port-forward --port-forward-namespace argocd --grpc-web
```

**Deployment timeout**:
```bash
# Monitor progress
./scripts/monitor-argocd-apps.sh 1800  # 30-minute timeout
```

## Related Skills

- **gitops-workflow**: Making changes after deployment
- **platform-health**: Health checks
- **troubleshoot-argocd**: ArgoCD issues

🤖 Generated with [Claude Code](https://claude.com/claude-code)
