# Grafana Dashboard Service Down

**UID**: `grafana-down`
**Severity**: warning
**Component**: grafana
**Layer**: observability

---

### Meaning

Grafana has no available replicas. Dashboard visualization and alerting UI are unavailable.

**PromQL Query**: `kube_deployment_status_replicas_available{namespace="observability",deployment="grafana"} == 0`

**Alert fires when**: Grafana deployment has 0 available replicas

---

### Impact

- **User Impact**: Cannot access dashboards, metrics visualization, or alerting UI
- **System Impact**: Alert management UI unavailable, but alert evaluation continues in Prometheus
- **Blast Radius**: Grafana dashboards only (metrics collection unaffected)

**Severity**: **WARNING** - Observability impaired but metrics collection continues

---

### Diagnosis

```bash
# Check Grafana pod
kubectl get pods -n observability -l app=grafana
kubectl describe pod -n observability -l app=grafana
kubectl logs -n observability -l app=grafana --tail=100

# Check deployment
kubectl get deployment grafana -n observability
```

**Common Causes**: Pod crashed, image pull failure, configuration error, resource limits

---

### Mitigation

**Restart Grafana**:
```bash
kubectl rollout restart deployment/grafana -n observability
kubectl rollout status deployment/grafana -n observability
```

**Check configuration**:
```bash
kubectl get configmap -n observability | grep grafana
kubectl logs -n observability -l app=grafana | grep -i error
```

**Prevention**: Monitor Grafana resource usage, validate datasource configurations, test dashboard changes

---

### Related Information

**Related Alerts**: `prometheus-down`, `alertmanager-down`
**Upstream**: [Grafana Runbook](https://runbooks.prometheus-operator.dev/runbooks/general/deployment-down/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
