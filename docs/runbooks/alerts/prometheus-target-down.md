# Prometheus Scrape Target Down

**UID**: `prometheus-target-down`
**Severity**: warning
**Component**: prometheus
**Layer**: observability

---

### Meaning

Prometheus cannot scrape a target endpoint. Metrics are not being collected from this target.

**PromQL Query**: `up{job!=""} == 0`

**Alert fires when**: Prometheus `up` metric shows 0 for a target

---

### Impact

- **User Impact**: Metrics not available for affected target in dashboards
- **System Impact**: Metrics gap, cannot monitor target health, alerts for this target may not fire
- **Blast Radius**: Specific scrape target only

**Severity**: **WARNING** - Monitoring gap for specific service

---

### Diagnosis

```bash
# Check Prometheus targets
kubectl port-forward -n observability svc/prometheus 9090:9090 &
# Open http://localhost:9090/targets

# Query affected target
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=up{job="<job-name>"}'

# Check if target pod is running
kubectl get pods -n <namespace> -l <job-label-selector>
```

**Common Causes**: Target pod down, metrics port not exposed, network policy blocking scrape, authentication required

---

### Mitigation

**Check target pod**:
```bash
kubectl get pods -n <namespace> -l <selector>
kubectl logs -n <namespace> <pod-name>
```

**Test metrics endpoint**:
```bash
kubectl exec -n observability deployment/grafana -- \
  curl -s http://<service>.<namespace>.svc:<port>/metrics
```

**Check Prometheus scrape config**:
```bash
kubectl get configmap prometheus-config -n observability -o yaml
```

**Prevention**: Ensure metrics endpoints are accessible, configure proper network policies, validate scrape configs

---

### Related Information

**Related Alerts**: `prometheus-high-scrape-failure`
**Upstream**: [Prometheus Scraping](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
