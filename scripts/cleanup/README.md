# Cleanup Scripts

Automated scripts for cleaning up Kagenti deployments before redeployment.

## 🎯 Quick Reference

| Script | Environment | Use Case |
|--------|-------------|----------|
| `cleanup-environment.sh` | **All** | Interactive menu to choose environment |
| `cleanup-kind-local.sh` | Kind | Clean Kind cluster |
| `cleanup-k3s-local.sh` | K3s | Clean Rancher Desktop K3s |
| `cleanup-openshift-stage.sh` | OpenShift Stage | Clean staging environment |
| `cleanup-openshift-prod.sh` | OpenShift Prod | Clean production (requires approval) |
| `wipe-namespace.sh` | Generic | Safe namespace deletion with backup |
| `force-delete-namespace.sh` | Generic | Force delete stuck namespaces |

## 🚀 Usage

### Interactive Cleanup (Recommended)

```bash
# Choose environment interactively
./scripts/cleanup/cleanup-environment.sh
```

### Direct Environment Cleanup

```bash
# Kind Local
./scripts/cleanup/cleanup-kind-local.sh

# K3s Local
./scripts/cleanup/cleanup-k3s-local.sh

# OpenShift Stage
./scripts/cleanup/cleanup-openshift-stage.sh

# OpenShift Production (requires extra confirmation)
./scripts/cleanup/cleanup-openshift-prod.sh
```

### Generic Namespace Cleanup

```bash
# Safe cleanup with backup
./scripts/cleanup/wipe-namespace.sh observability stage

# Force delete stuck namespace
./scripts/cleanup/force-delete-namespace.sh observability
```

## 📋 Cleanup Options

### Kind Local Options

1. **Delete observability namespace only** (keep cluster)
   - Removes Kagenti deployment
   - Cluster remains for redeployment
   - Fast cleanup

2. **Delete entire Kind cluster** (complete cleanup)
   - Removes everything
   - Requires cluster recreation
   - Use for fresh start

### K3s Local Options

1. **Delete observability namespace only**
   - Removes Grafana and dashboards
   - K3s cluster remains running

2. **Delete observability + ArgoCD namespaces**
   - Removes deployment and GitOps
   - Requires ArgoCD reinstall

3. **Complete K3s reset**
   - Instructions for Rancher Desktop reset
   - Requires manual UI action

### OpenShift Stage Options

1. **Delete observability namespace only**
   - Removes monitoring stack
   - Keeps operators and agents

2. **Delete observability + kagenti-system**
   - Removes monitoring + operators
   - Keeps agents

3. **Delete observability + kagenti-system + team1**
   - Complete Kagenti cleanup
   - Removes all components

4. **Delete observability + ArgoCD**
   - Removes monitoring + GitOps
   - Requires ArgoCD reinstall

### OpenShift Production Options

Same as Stage, but with additional safety checks:
- ✅ Approval checklist required
- ✅ Maintenance window confirmation
- ✅ Comprehensive backup created
- ✅ "DELETE PRODUCTION" confirmation required
- ✅ Extended timeout (10 minutes)

## 🔒 Safety Features

### Automatic Backups

All scripts create automatic backups before deletion:

```bash
backups/
└── <environment>-<timestamp>/
    ├── all.yaml              # All resources
    ├── configmaps.yaml       # ConfigMaps
    ├── secrets.yaml          # Secrets (OpenShift)
    ├── routes.yaml           # Routes (OpenShift)
    └── BACKUP_INFO.txt       # Backup metadata (Production)
```

### Production Safety Checks

OpenShift Production script includes:

1. **Pre-deployment Checklist**
   - Approval from team lead
   - Maintenance window scheduled
   - Stakeholders notified
   - Rollback plan documented
   - Current state documented

2. **Cluster Verification**
   - Checks for "prod" in cluster URL
   - Warns if not detected

3. **Multiple Confirmations**
   - Initial safety check
   - Final "DELETE PRODUCTION" confirmation

4. **Comprehensive Backup**
   - All resources backed up
   - Metadata file created
   - Organized by namespace

## 📊 Cleanup Flow

```
┌─────────────────────┐
│ Run cleanup script  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Verify environment  │
│ - Check cluster     │
│ - Verify context    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Choose cleanup      │
│ option (1-5)        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Create backup       │
│ - All resources     │
│ - Timestamped dir   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Confirm deletion    │
│ (varies by env)     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Delete namespaces   │
│ - Wait for deletion │
│ - Handle timeouts   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Show redeploy       │
│ instructions        │
└─────────────────────┘
```

## 🔄 Redeployment After Cleanup

### Kind Local

```bash
# After cleanup
./scripts/deploy/deploy-kind.sh
```

### K3s Local

```bash
# After namespace cleanup
kubectl apply -k environments/k3s-local/

# After ArgoCD cleanup
./scripts/deploy/bootstrap-argocd.sh
kubectl apply -f argocd-apps/k3s-local.yaml
```

### OpenShift Stage

```bash
# After namespace cleanup
oc apply -k environments/openshift-stage/

# After ArgoCD cleanup
./scripts/deploy/bootstrap-argocd.sh
kubectl apply -f argocd-apps/openshift-stage.yaml
```

### OpenShift Production

```bash
# After namespace cleanup
oc apply -k environments/openshift-prod/

# After ArgoCD cleanup (requires manual sync)
./scripts/deploy/bootstrap-argocd.sh
kubectl apply -f argocd-apps/openshift-prod.yaml
# Then manually sync in ArgoCD UI
```

## ⚠️ Troubleshooting

### Namespace Stuck in Terminating

If namespace deletion hangs:

```bash
# Wait for timeout (2-10 minutes depending on environment)
# If stuck, use force delete script
./scripts/cleanup/force-delete-namespace.sh <namespace>
```

### PVCs Not Deleting

```bash
# Check which pods are using PVCs
kubectl get pods -n <namespace> -o json | \
  jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim) | .metadata.name'

# Delete pods first, then namespace
kubectl delete pods --all -n <namespace>
kubectl delete namespace <namespace>
```

### Finalizers Blocking Deletion

```bash
# List resources with finalizers
kubectl get all -n <namespace> -o json | \
  jq -r '.items[] | select(.metadata.finalizers != null) | .metadata.name'

# Use force-delete-namespace script to remove finalizers
./scripts/cleanup/force-delete-namespace.sh <namespace>
```

### Production Cleanup Failed

```bash
# Check namespace status
oc get namespace <namespace> -o yaml

# Contact cluster admin if stuck
# Restore from backup if needed
oc apply -f backups/<timestamp>/
```

## 📁 Backup Management

### List All Backups

```bash
ls -lht backups/
```

### Restore from Backup

```bash
# Find backup directory
BACKUP_DIR="backups/kind-local-20250115-143022"

# Recreate namespace
kubectl create namespace observability

# Restore resources
kubectl apply -f $BACKUP_DIR/all.yaml
kubectl apply -f $BACKUP_DIR/configmaps.yaml
```

### Cleanup Old Backups

```bash
# Keep last 10 backups
ls -t backups/ | tail -n +11 | xargs -I {} rm -rf backups/{}

# Or keep backups older than 30 days
find backups/ -type d -mtime +30 -exec rm -rf {} \;
```

## 🎯 Best Practices

1. **Always Review Backup**
   - Check backup created successfully
   - Verify backup contains expected resources

2. **Test in Lower Environment First**
   - Test cleanup in Kind/Stage before Production
   - Verify redeployment works

3. **Document Production Cleanups**
   - Create ticket/issue for production cleanup
   - Document reason and timestamp
   - Keep backup for 30+ days

4. **Use ArgoCD Cleanup for GitOps**
   - Delete Application first
   - Then delete namespaces
   - Prevents sync conflicts

5. **Monitor During Cleanup**
   - Watch for errors during deletion
   - Check for stuck resources
   - Use validation scripts after redeployment

## 📚 Related Documentation

- [DEPLOYMENT.md](../../docs/DEPLOYMENT.md) - Deployment procedures
- [CLEANUP.md](../../docs/CLEANUP.md) - Detailed cleanup guide
- [OPENSHIFT.md](../../docs/OPENSHIFT.md) - OpenShift-specific procedures

---

**Note:** These scripts are safe to run multiple times. If namespaces don't exist, scripts will exit gracefully.
