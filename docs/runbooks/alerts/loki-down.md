# Loki Log Aggregation Service Down

**UID**: `loki-down`
**Severity**: warning
**Component**: loki
**Layer**: observability

---

### Meaning

Loki has no available replicas. Log ingestion and querying are unavailable.

**PromQL Query**: `kube_deployment_status_replicas_available{namespace="observability",deployment="loki"} == 0`

**Alert fires when**: Loki deployment has 0 available replicas

---

### Impact

- **User Impact**: Cannot query logs in Grafana
- **System Impact**: Log ingestion stopped, Promtail cannot forward logs, log data gap
- **Blast Radius**: Log aggregation only (metrics unaffected)

**Severity**: **WARNING** - Log collection impaired but not critical to operations

---

### Diagnosis

```bash
kubectl get pods -n observability -l app=loki
kubectl describe pod -n observability -l app=loki
kubectl logs -n observability -l app=loki --tail=100

# Check storage
kubectl get pvc -n observability | grep loki
```

**Common Causes**: Storage full, pod crashed, configuration error, OOM

---

### Mitigation

**Restart Loki**:
```bash
kubectl rollout restart deployment/loki -n observability
```

**Check storage**:
```bash
kubectl exec -n observability deployment/loki -- df -h /loki
```

**Prevention**: Monitor storage usage, configure retention policies, set appropriate resource limits

---

### Related Information

**Related Alerts**: `promtail-pods-down`, `pvc-high-usage`
**Upstream**: [Loki Runbook](https://runbooks.prometheus-operator.dev/runbooks/general/deployment-down/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
