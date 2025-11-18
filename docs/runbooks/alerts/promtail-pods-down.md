# Promtail Log Collection Degraded

**UID**: `promtail-pods-down`
**Severity**: warning
**Component**: promtail
**Layer**: observability

---

### Meaning

Less than 80% of Promtail pods are running. Log collection is degraded.

**PromQL Query**: `(kube_daemonset_status_number_available{namespace="observability",daemonset="promtail"} / kube_daemonset_status_desired_number_scheduled{namespace="observability",daemonset="promtail"}) < 0.8`

**Alert fires when**: Fewer than 80% of desired Promtail pods are available

---

### Impact

- **User Impact**: Incomplete log collection, missing logs from some nodes
- **System Impact**: Log gaps from nodes where Promtail is down
- **Blast Radius**: Nodes without running Promtail pods

**Severity**: **WARNING** - Partial log collection, not complete outage

---

### Diagnosis

```bash
# Check Promtail DaemonSet
kubectl get daemonset promtail -n observability

# Check which nodes are missing Promtail
kubectl get pods -n observability -l app=promtail -o wide

# Check pod status
kubectl describe pod -n observability -l app=promtail
kubectl logs -n observability -l app=promtail --tail=50
```

**Common Causes**: Node issues, pod evicted, image pull failure, resource constraints

---

### Mitigation

**Restart failed Promtail pods**:
```bash
# Delete failed pods (DaemonSet will recreate)
kubectl delete pod -n observability <promtail-pod-name>
```

**Check node status**:
```bash
kubectl get nodes
kubectl describe node <node-name>
```

**Prevention**: Monitor node health, ensure adequate node resources for DaemonSet pods

---

### Related Information

**Related Alerts**: `loki-down`, `kubernetes-node-not-ready`
**Upstream**: [Promtail Documentation](https://grafana.com/docs/loki/latest/clients/promtail/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
