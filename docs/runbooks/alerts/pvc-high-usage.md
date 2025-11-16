# PersistentVolumeClaim High Usage

**UID**: `pvc-high-usage`
**Severity**: warning
**Component**: storage
**Layer**: infrastructure

---

### Meaning

A PersistentVolumeClaim (PVC) is over 85% full.

**PromQL Query**: `(kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100 > 85`

**Alert fires when**: PVC usage exceeds 85% of capacity

---

### Impact

- **User Impact**: Service may fail if disk fills completely
- **System Impact**: Write failures, application crashes, data loss risk
- **Blast Radius**: Services using the specific PVC

**Severity**: **WARNING** - Proactive alert before storage full

---

### Diagnosis

```bash
# Check PVC usage
kubectl get pvc -A

# Check which pod is using the PVC
kubectl get pods -A -o json | grep -B 10 <pvc-name>

# Check disk usage from pod
kubectl exec -n <namespace> <pod-name> -- df -h
```

**Common Causes**: Log accumulation, data growth, missing cleanup jobs, retention policies not working

---

### Mitigation

**Clean up old data**:
```bash
# For Prometheus/Loki/Tempo - configure retention
# Edit deployment to reduce retention period

# For application data - run cleanup job
kubectl exec -n <namespace> <pod-name> -- rm -rf /data/old/*
```

**Expand PVC** (if supported by storage class):
```bash
kubectl patch pvc <pvc-name> -n <namespace> -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

**Prevention**: Configure data retention policies, monitor storage growth, set up automated cleanup

---

### Related Information

**Related Alerts**: `loki-down`, `tempo-down`, `prometheus-down` (may be caused by storage full)
**Upstream**: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
