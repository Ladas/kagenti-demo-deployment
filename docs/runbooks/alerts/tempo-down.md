# Tempo Tracing Service Down

**UID**: `tempo-down`
**Severity**: warning
**Component**: tempo
**Layer**: observability

---

### Meaning

Tempo has no available replicas. Distributed tracing collection and querying are unavailable.

**PromQL Query**: `kube_deployment_status_replicas_available{namespace="observability",deployment="tempo"} == 0`

**Alert fires when**: Tempo deployment has 0 available replicas

---

### Impact

- **User Impact**: Cannot view distributed traces in Grafana
- **System Impact**: Trace ingestion stopped, trace data gap, cannot correlate requests
- **Blast Radius**: Tracing only (metrics and logs unaffected)

**Severity**: **WARNING** - Tracing impaired but core services operational

---

### Diagnosis

```bash
kubectl get pods -n observability -l app=tempo
kubectl describe pod -n observability -l app=tempo
kubectl logs -n observability -l app=tempo --tail=100
```

**Common Causes**: Pod crashed, storage full, configuration error, OOM

---

### Mitigation

**Restart Tempo**:
```bash
kubectl rollout restart deployment/tempo -n observability
```

**Prevention**: Monitor storage usage, configure trace retention, set resource limits

---

### Related Information

**Related Alerts**: `pvc-high-usage`
**Upstream**: [Tempo Runbook](https://runbooks.prometheus-operator.dev/runbooks/general/deployment-down/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
