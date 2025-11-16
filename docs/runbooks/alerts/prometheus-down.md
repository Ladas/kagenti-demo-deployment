# Prometheus Metrics Service Down

**UID**: `prometheus-down`
**Severity**: critical
**Component**: prometheus
**Layer**: observability

---

### Meaning

**What does this alert mean?**

Prometheus is not responding to health checks. The metrics collection and alerting system is down.

**PromQL Query**:
```promql
up{job="kubernetes-pods",app="prometheus",kubernetes_namespace="observability"} == 0
```

**Alert fires when**:
- Prometheus pod is down or not ready
- Prometheus `/metrics` endpoint is unreachable
- Network connectivity to Prometheus is blocked

---

### Impact

**What is the impact of this issue?**

- **User Impact**: Loss of observability - cannot view metrics, traces, or system health
- **System Impact**:
  - **ALL alert evaluation stops** - no new alerts will fire
  - Metrics collection halts - data gap in time series
  - Grafana dashboards show no data
  - Service monitoring blind spot
  - Alert history lost for downtime period
- **Blast Radius**: Entire observability stack

**Severity Justification**:
- **CRITICAL** because:
  - Alerting system depends on Prometheus (self-referential)
  - Loss of visibility into system health
  - Cannot detect other incidents
  - Data gap affects historical analysis
  - Other alerts cannot fire without Prometheus

---

### Diagnosis

**How to investigate this alert:**

**1. Check Prometheus pod status:**
```bash
# Check Prometheus pods
kubectl get pods -n observability -l app=prometheus

# Describe pod for events
kubectl describe pod -n observability -l app=prometheus

# Check logs
kubectl logs -n observability -l app=prometheus --tail=100
```

**2. Check Prometheus deployment:**
```bash
# Check deployment status
kubectl get deployment prometheus -n observability

# Check StatefulSet (if using StatefulSet)
kubectl get statefulset prometheus -n observability

# Check replica count
kubectl get deployment prometheus -n observability -o jsonpath='{.status}'
```

**3. Test Prometheus endpoint:**
```bash
# Test from within cluster
kubectl exec -n observability deployment/grafana -- \
  curl -s http://prometheus.observability.svc:9090/-/healthy

# Check if Prometheus can query itself
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=up'
```

**4. Check Prometheus configuration:**
```bash
# Check ConfigMap
kubectl get configmap -n observability | grep prometheus

# View configuration
kubectl get configmap prometheus-config -n observability -o yaml

# Check for configuration reload errors in logs
kubectl logs -n observability -l app=prometheus | grep -i "error.*config"
```

**5. Check storage:**
```bash
# Check PVC if using persistent storage
kubectl get pvc -n observability | grep prometheus

# Check PVC status
kubectl describe pvc prometheus-data -n observability
```

**Common Causes**:
- Pod crashed due to OOM (time series cardinality explosion)
- Configuration error (invalid prometheus.yml)
- Storage full (TSDB cannot write new data)
- Image pull failure
- Corrupted TSDB data files
- Resource limits exceeded
- Node pressure causing eviction

---

### Mitigation

**Immediate Actions**:

1. **Verify the issue is real**:
   ```bash
   # Check if Prometheus pod is running
   kubectl get pods -n observability -l app=prometheus

   # Check if Prometheus is healthy
   kubectl exec -n observability deployment/grafana -- \
     curl -s http://prometheus.observability.svc:9090/-/healthy
   ```

2. **Check for common issues**:
   - **OOMKilled**: Check pod status and increase memory limits
   - **CrashLoopBackOff**: Check logs for config errors or TSDB corruption
   - **Pending**: Check for storage or resource constraints

3. **Restart Prometheus** (if pod exists but failing):
   ```bash
   kubectl rollout restart deployment/prometheus -n observability

   # If using StatefulSet
   kubectl rollout restart statefulset/prometheus -n observability

   # Wait for rollout
   kubectl rollout status deployment/prometheus -n observability --timeout=5m
   ```

**Root Cause Resolution**:

1. **If configuration error**:
   ```bash
   # Validate Prometheus configuration
   kubectl exec -n observability -l app=prometheus -- \
     promtool check config /etc/prometheus/prometheus.yml

   # Check for recent ConfigMap changes
   kubectl describe configmap prometheus-config -n observability

   # Rollback configuration if needed (GitOps)
   git revert <bad-commit>
   argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
   ```

2. **If OOM issues**:
   ```bash
   # Check Prometheus memory usage
   kubectl top pod -n observability -l app=prometheus

   # Check TSDB stats
   kubectl exec -n observability -l app=prometheus -- \
     curl -s http://localhost:9090/api/v1/status/tsdb | python3 -m json.tool

   # Increase memory limits (GitOps)
   # Edit components/02-observability/prometheus/deployment.yaml
   # Increase: resources.limits.memory to 4Gi or higher
   ```

3. **If storage full**:
   ```bash
   # Check PVC usage
   kubectl exec -n observability -l app=prometheus -- df -h /prometheus

   # Increase retention period or add more storage (GitOps)
   # Edit components/02-observability/prometheus/deployment.yaml
   # Add: --storage.tsdb.retention.time=7d (reduce from default 15d)
   ```

4. **If TSDB corruption**:
   ```bash
   # Check for corruption in logs
   kubectl logs -n observability -l app=prometheus | grep -i "corrupt"

   # May need to delete pod to force recreation
   kubectl delete pod -n observability -l app=prometheus

   # In severe cases, may need to clear TSDB (LOSES ALL METRICS)
   # kubectl delete pvc prometheus-data -n observability
   ```

**Prevention**:
- Set appropriate memory limits based on metrics cardinality
- Monitor TSDB disk usage
- Configure retention policy appropriate for storage size
- Use remote write for long-term storage (Thanos, Cortex, Mimir)
- Regular validation of Prometheus configuration before applying
- Monitor scrape target count and cardinality
- Set up Prometheus HA (multiple replicas)

**Escalation**:
- If issue persists after 10 minutes, escalate to platform team
- This impacts all alerting and monitoring
- Related components to check:
  - Grafana (cannot query metrics)
  - AlertManager (no alerts being sent)
  - All monitoring dashboards

---

### Related Information

**Related Alerts**:
- `alertmanager-down` - May be affected by Prometheus outage
- `grafana-down` - Grafana needs Prometheus for dashboards
- `prometheus-target-down` - May have been the cause (scrape failures)

**Related Dashboards**:
- Prometheus Dashboard (self-monitoring)
- TSDB Status Dashboard

**Related Documentation**:
- [Observability Architecture](../CLAUDE.md#monitoring--access)
- [Alert Testing Guide](./ALERT_TESTING_GUIDE.md)

**Upstream Documentation**:
- [Prometheus Troubleshooting](https://prometheus.io/docs/prometheus/latest/troubleshooting/)
- [Prometheus Runbook](https://runbooks.prometheus-operator.dev/runbooks/prometheus/prometheus-down/)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
