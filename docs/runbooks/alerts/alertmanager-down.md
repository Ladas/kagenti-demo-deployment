# AlertManager Service Down

**UID**: `alertmanager-down`
**Severity**: critical
**Component**: alertmanager
**Layer**: observability

---

### Meaning

**What does this alert mean?**

AlertManager deployment shows 0 available replicas. Alert routing and notifications may be impacted.

⚠️ **NOTE**: This alert may fire when the Istio sidecar is not ready (known infrastructure issue). The main AlertManager container may still be healthy and functional.

**PromQL Query**:
```promql
kube_deployment_status_replicas_available{namespace="observability",deployment="alertmanager"} == 0
```

**Alert fires when**:
- AlertManager deployment reports 0 available replicas
- Pod is not fully ready (main container + Istio sidecar)
- AlertManager pod is down

---

### Impact

**What is the impact of this issue?**

- **User Impact**: Alert notifications may not be delivered (Slack, PagerDuty, email, etc.)
- **System Impact**:
  - Alert grouping and deduplication stops
  - Alert silencing/inhibition rules not applied
  - Alert history lost during downtime
  - Prometheus can still evaluate alerts but cannot route them
- **Blast Radius**: All alert notifications

**Severity Justification**:
- **CRITICAL** because:
  - Loss of alert notification delivery
  - Incidents may go unnoticed
  - On-call engineers not paged
  - Alert routing and grouping essential for operations

**However**: If main container is healthy but only sidecar not ready, this is low impact.

---

### Diagnosis

**How to investigate this alert:**

**1. Check pod status (including sidecar):**
```bash
# Check AlertManager pod - look for 1/2 or 2/2 ready containers
kubectl get pods -n observability -l app=alertmanager

# Describe pod to see container status
kubectl describe pod -n observability -l app=alertmanager

# Check which containers are ready
kubectl get pods -n observability -l app=alertmanager \
  -o jsonpath='{.items[0].status.containerStatuses[*].name}'
```

**2. Check main AlertManager container health:**
```bash
# Query main container directly (bypasses sidecar)
kubectl exec -n observability -c alertmanager deployment/alertmanager -- \
  wget -qO- http://localhost:9093/-/ready

# Check AlertManager API
kubectl exec -n observability -c alertmanager deployment/alertmanager -- \
  wget -qO- http://localhost:9093/api/v2/status
```

**3. Check Istio sidecar status:**
```bash
# Check istio-proxy container
kubectl logs -n observability -l app=alertmanager -c istio-proxy --tail=50

# Check if sidecar is ready
kubectl get pod -n observability -l app=alertmanager \
  -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="istio-proxy")].ready}'
```

**4. Check AlertManager logs:**
```bash
# Main container logs
kubectl logs -n observability -l app=alertmanager -c alertmanager --tail=100

# Check for configuration errors
kubectl logs -n observability -l app=alertmanager -c alertmanager | grep -i error
```

**5. Test alert delivery:**
```bash
# Send test alert to AlertManager
kubectl exec -n observability deployment/grafana -- \
  curl -s -X POST http://alertmanager.observability.svc:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"test","severity":"info"},"annotations":{"summary":"Test alert"}}]'
```

**Common Causes**:
- **Istio sidecar not ready** (MOST COMMON - low impact)
- Configuration error in alertmanager.yml
- Persistent volume issues
- Image pull failure
- Resource limits exceeded
- Network policy blocking traffic

---

### Mitigation

**Immediate Actions**:

1. **Determine if this is a false positive (sidecar issue)**:
   ```bash
   # Check main container health
   kubectl exec -n observability -c alertmanager deployment/alertmanager -- \
     wget -qO- http://localhost:9093/-/ready

   # If returns "OK" → main container is healthy, only sidecar issue
   # This is LOW impact - alerts still work
   ```

2. **If main container is healthy but sidecar not ready**:
   ```bash
   # Check sidecar logs for why it's not ready
   kubectl logs -n observability -l app=alertmanager -c istio-proxy --tail=100

   # Common issue: sidecar waiting for proxy to be ready
   # Usually resolves itself after 1-2 minutes
   ```

3. **If main container is also unhealthy**:
   ```bash
   # Check logs for errors
   kubectl logs -n observability -l app=alertmanager -c alertmanager --tail=100

   # Restart AlertManager
   kubectl rollout restart deployment/alertmanager -n observability
   ```

**Root Cause Resolution**:

1. **If configuration error**:
   ```bash
   # Check AlertManager configuration
   kubectl get configmap -n observability | grep alertmanager

   # Validate configuration
   kubectl exec -n observability -c alertmanager deployment/alertmanager -- \
     amtool check-config /etc/alertmanager/alertmanager.yml

   # Fix configuration via GitOps
   # Edit components/02-observability/alertmanager/config.yaml
   git add . && git commit -m "Fix AlertManager config" && git push
   argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
   ```

2. **If Istio sidecar perpetually not ready**:
   ```bash
   # Check mTLS policy
   kubectl get peerauthentication -n observability

   # Check if there are conflicting policies
   kubectl describe peerauthentication -n observability

   # May need to set PERMISSIVE mode for AlertManager
   # See: components/02-observability/mtls-policy.yaml
   ```

3. **If storage issues**:
   ```bash
   # Check PVC
   kubectl get pvc -n observability | grep alertmanager

   # Check disk usage
   kubectl exec -n observability -c alertmanager deployment/alertmanager -- df -h
   ```

**Prevention**:
- **Accept sidecar delays as normal** (1-2 minutes is expected)
- Monitor AlertManager notification delivery rate
- Set up redundant AlertManager instances (HA)
- Validate configuration before deploying
- Use Prometheus to monitor AlertManager health independently
- Consider PERMISSIVE mTLS if sidecar issues persist

**Escalation**:
- If main container is healthy, this is LOW priority (sidecar issue)
- If main container is down > 5 minutes, escalate to platform team
- Related components to check:
  - Prometheus (sends alerts to AlertManager)
  - Grafana (sends alerts to AlertManager)
  - Notification channels (Slack, PagerDuty, etc.)

---

### Related Information

**Related Alerts**:
- `prometheus-down` - Prometheus cannot send alerts if down
- `grafana-down` - Grafana cannot send alerts if down

**Related Dashboards**:
- AlertManager Dashboard (Grafana)
- Alert Delivery Rate Dashboard

**Related Documentation**:
- [Alert Monitoring](../../CLAUDE.md#alert-monitoring)
- [Encryption Architecture](../ENCRYPTION_ARCHITECTURE.md) - mTLS and sidecar

**Upstream Documentation**:
- [AlertManager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [AlertManager Troubleshooting](https://prometheus.io/docs/alerting/latest/troubleshooting/)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
