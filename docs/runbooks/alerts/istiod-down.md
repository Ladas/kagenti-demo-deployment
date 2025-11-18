# Istio Control Plane Down

**UID**: `istiod-down`
**Severity**: critical
**Component**: istio
**Layer**: infrastructure

---

### Meaning

**What does this alert mean?**

The Istio control plane (istiod) is not responding to health checks. This means the service mesh control plane is down or unreachable.

**PromQL Query**:
```promql
up{job="istiod"} == 0
```

**Alert fires when**:
- Prometheus cannot scrape the istiod /metrics endpoint
- The istiod pod is down or not ready
- Network connectivity to istiod is blocked

---

### Impact

**What is the impact of this issue?**

- **User Impact**: New service deployments cannot get sidecar injection. Existing services continue to work but cannot update configurations.
- **System Impact**:
  - No new mTLS certificates issued
  - Configuration updates (VirtualService, DestinationRule, etc.) not applied
  - Service mesh observability degraded
  - Gateway configurations frozen
- **Blast Radius**: Entire service mesh (all namespaces with `istio-injection=enabled`)

**Severity Justification**:
- **CRITICAL** because:
  - Service mesh control plane is core infrastructure
  - Blocks deployment of new services
  - Prevents security policy updates
  - mTLS certificate rotation may fail

---

### Diagnosis

**How to investigate this alert:**

**1. Check istiod pod status:**
```bash
# Check istiod pods
kubectl get pods -n istio-system -l app=istiod

# Describe pod for events
kubectl describe pod -n istio-system -l app=istiod

# Check logs
kubectl logs -n istio-system -l app=istiod --tail=100
```

**2. Check istiod deployment:**
```bash
# Check deployment status
kubectl get deployment istiod -n istio-system

# Check replica count
kubectl get deployment istiod -n istio-system -o jsonpath='{.status.availableReplicas}'
```

**3. Check Prometheus scrape target:**
```bash
# Query Prometheus for istiod up metric
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=up{job="istiod"}' | python3 -m json.tool
```

**4. Check recent events:**
```bash
kubectl get events -n istio-system --sort-by='.lastTimestamp' | tail -20
```

**5. Verify Istio installation:**
```bash
# Check Istio version
istioctl version

# Analyze Istio configuration
istioctl analyze -A
```

**Common Causes**:
- Pod crashed due to OOM or configuration error
- Image pull failure
- Node resource pressure
- Network policy blocking Prometheus scraping
- Kubernetes API server connectivity issues
- Certificate/webhook configuration problems

---

### Mitigation

**Immediate Actions**:

1. **Verify the issue is real**:
   ```bash
   # Check if istiod pod is running
   kubectl get pods -n istio-system -l app=istiod

   # Check if istiod is healthy
   kubectl exec -n istio-system deployment/istiod -- curl -s http://localhost:15014/ready
   ```

2. **Check for common issues**:
   - **OOM killed**: Check pod status for `OOMKilled`
   - **Image pull error**: Check pod events for image pull failures
   - **CrashLoopBackOff**: Check logs for startup errors

3. **Restart istiod** (if pod is in bad state):
   ```bash
   kubectl rollout restart deployment/istiod -n istio-system

   # Wait for rollout to complete
   kubectl rollout status deployment/istiod -n istio-system
   ```

**Root Cause Resolution**:

1. **If pod is OOMKilled**:
   ```bash
   # Increase memory limits
   kubectl patch deployment istiod -n istio-system -p '
   {
     "spec": {
       "template": {
         "spec": {
           "containers": [{
             "name": "discovery",
             "resources": {
               "limits": {"memory": "2Gi"},
               "requests": {"memory": "1Gi"}
             }
           }]
         }
       }
     }
   }'
   ```

2. **If configuration error**:
   ```bash
   # Check istiod configuration
   kubectl get configmap istio -n istio-system -o yaml

   # Validate configuration
   istioctl analyze -A
   ```

3. **If webhook issues**:
   ```bash
   # Check validating webhooks
   kubectl get validatingwebhookconfiguration

   # Check mutating webhooks
   kubectl get mutatingwebhookconfiguration
   ```

**Prevention**:
- Set appropriate resource limits based on cluster size
- Monitor istiod resource usage
- Enable HPA for istiod in production
- Keep Istio version up to date
- Regular validation of Istio configuration

**Escalation**:
- If issue persists after 10 minutes, escalate to platform team
- Related components to check:
  - Istio Gateway (may also be affected)
  - Kubernetes API server
  - Certificate manager

---

### Related Information

**Related Alerts**:
- `gateway-unhealthy` - Gateway may fail if istiod is down
- `kubernetes-node-not-ready` - Node issues may affect istiod

**Related Dashboards**:
- Istio Control Plane Dashboard (Grafana)
- Istio Mesh Dashboard

**Related Documentation**:
- [Istio Architecture](../ENCRYPTION_ARCHITECTURE.md)
- [ArgoCD GitOps Workflow](../../CLAUDE.md)

**Upstream Documentation**:
- [Istio Debugging](https://istio.io/latest/docs/ops/diagnostic-tools/)
- [Istiod Health Checks](https://istio.io/latest/docs/ops/diagnostic-tools/controlz/)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
