# Prometheus High Scrape Failure Rate

**UID**: `prometheus-high-scrape-failure`
**Severity**: warning
**Component**: prometheus
**Layer**: observability

---

### Meaning

Prometheus is experiencing high scrape failure rate for a job.

**PromQL Query**: `rate(prometheus_target_scrapes_sample_duplicate_timestamp_total[5m]) > 0.1`

**Alert fires when**: Scrape failure rate exceeds 0.1 failures per second

---

### Impact

- **User Impact**: Incomplete metrics collection, dashboard data gaps
- **System Impact**: Metrics reliability degraded, alert evaluation may be inaccurate
- **Blast Radius**: Specific Prometheus job

**Severity**: **WARNING** - Metrics quality degraded

---

### Diagnosis

```bash
# Check Prometheus targets page
kubectl port-forward -n observability svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# Query scrape failures
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=rate(prometheus_target_scrapes_sample_duplicate_timestamp_total[5m])'

# Check Prometheus logs
kubectl logs -n observability -l app=prometheus --tail=100 | grep -i "scrape"
```

**Common Causes**: Target returning duplicate timestamps, target responding slowly, target returning invalid metrics, network issues

---

### Mitigation

**Check affected targets**:
```bash
# Identify which job has failures
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://prometheus.observability.svc:9090/api/v1/targets' | python3 -m json.tool
```

**Increase scrape timeout** (if targets are slow):
```yaml
# Edit Prometheus scrape config
scrape_configs:
  - job_name: '<job-name>'
    scrape_interval: 60s
    scrape_timeout: 30s  # Increase
```

**Prevention**: Monitor scrape duration, ensure targets respond quickly, validate metrics format

---

### Related Information

**Related Alerts**: `prometheus-target-down`
**Upstream**: [Prometheus Troubleshooting](https://prometheus.io/docs/prometheus/latest/troubleshooting/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
