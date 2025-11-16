# Istio Gateway Unhealthy

**UID**: `gateway-unhealthy`
**Severity**: critical
**Component**: gateway
**Layer**: infrastructure

---

### Meaning

**What does this alert mean?**

The Istio Gateway deployment has no available replicas. This means external traffic cannot enter the service mesh.

**PromQL Query**:
```promql
kube_deployment_status_replicas_available{deployment=~".*gateway.*istio.*"} == 0
```

**Alert fires when**:
- Gateway deployment has 0 available (ready) replicas
- All gateway pods are down or not ready
- Gateway deployment is scaled to 0

---

### Impact

**What is the impact of this issue?**

- **User Impact**: **ALL external services are unreachable**. Users cannot access:
  - Grafana dashboards
  - Keycloak authentication
  - Kagenti UI
  - Any service exposed via the gateway
- **System Impact**:
  - Ingress traffic completely blocked
  - HTTPS termination unavailable
  - External DNS resolution points to non-functioning endpoint
- **Blast Radius**: All services exposed via HTTPRoute/Gateway API

**Severity Justification**:
- **CRITICAL** because:
  - Complete platform outage for external users
  - No alternative ingress path
  - Blocks authentication and all user-facing services
  - Production traffic completely disrupted

---

### Diagnosis

**How to investigate this alert:**

**1. Check gateway pod status:**
```bash
# Check gateway pods
kubectl get pods -n default -l istio=gateway

# Get detailed pod info
kubectl describe pod -n default -l istio=gateway

# Check logs
kubectl logs -n default -l istio=gateway --tail=100
```

**2. Check gateway deployment:**
```bash
# Check deployment status
kubectl get deployment -n default | grep gateway

# Check replica count
kubectl get deployment external-gateway-istio -n default -o jsonpath='{.status}'
```

**3. Check gateway service:**
```bash
# Check service endpoints
kubectl get svc external-gateway-istio -n default
kubectl get endpoints external-gateway-istio -n default
```

**4. Check recent events:**
```bash
kubectl get events -n default --sort-by='.lastTimestamp' | tail -20
```

**5. Test gateway from debug pod:**
```bash
# Create test pod
kubectl run test-gateway -n default --image=curlimages/curl:latest --restart=Never --rm -it \
  -- curl -k -I https://grafana.localtest.me:9443
```

**Common Causes**:
- Pod crashed due to configuration error
- Image pull failure
- Node resource pressure causing eviction
- Invalid Gateway or HTTPRoute configuration
- Certificate issues preventing pod startup
- Resource limits too restrictive

---

### Mitigation

**Immediate Actions**:

1. **Verify the issue is real**:
   ```bash
   # Check if any gateway pods exist
   kubectl get pods -n default -l istio=gateway

   # Check if deployment exists
   kubectl get deployment external-gateway-istio -n default
   ```

2. **Check for common issues**:
   - **CrashLoopBackOff**: Check logs for Envoy configuration errors
   - **ImagePullBackOff**: Verify image exists and credentials are correct
   - **Pending**: Check for resource constraints or node affinity issues

3. **Restart the gateway** (if pods exist but not ready):
   ```bash
   kubectl rollout restart deployment/external-gateway-istio -n default

   # Wait for rollout
   kubectl rollout status deployment/external-gateway-istio -n default --timeout=5m
   ```

4. **Scale up gateway** (if scaled to 0):
   ```bash
   kubectl scale deployment/external-gateway-istio -n default --replicas=1
   ```

**Root Cause Resolution**:

1. **If Envoy configuration error**:
   ```bash
   # Check Gateway configuration
   kubectl get gateway external-gateway -n default -o yaml

   # Validate HTTPRoutes
   kubectl get httproute -A

   # Check istiod logs for configuration issues
   kubectl logs -n istio-system -l app=istiod --tail=100 | grep -i error
   ```

2. **If certificate issues**:
   ```bash
   # Check certificates
   kubectl get certificate -A

   # Describe wildcard certificate
   kubectl describe certificate wildcard-localtest-me-tls -n default

   # Check cert-manager logs
   kubectl logs -n cert-manager deployment/cert-manager --tail=100
   ```

3. **If resource constraints**:
   ```bash
   # Check node resources
   kubectl top nodes

   # Check pod resource requests
   kubectl describe deployment external-gateway-istio -n default | grep -A 5 "Requests"

   # Increase resources if needed (GitOps)
   # Edit components/00-infrastructure/gateway/deployment.yaml
   ```

**Prevention**:
- Enable HPA for gateway in production
- Set pod disruption budgets
- Use multiple replicas for high availability
- Monitor gateway resource usage
- Validate Gateway/HTTPRoute configs before applying
- Test certificate renewal process regularly

**Escalation**:
- If issue persists after 5 minutes, escalate immediately to platform team
- This is a **P0 incident** - complete platform outage
- Related components to check:
  - Istiod (control plane)
  - Cert-manager (certificate issues)
  - Keycloak (authentication chain)

---

### Related Information

**Related Alerts**:
- `istiod-down` - Control plane issues affect gateway
- `certificate-expiring-soon` - Certificate issues may block gateway startup
- `keycloak-down` - Authentication unavailable affects user access

**Related Dashboards**:
- Istio Gateway Dashboard (Grafana)
- Gateway Traffic Dashboard

**Related Documentation**:
- [Gateway Configuration](../ENCRYPTION_ARCHITECTURE.md)
- [Troubleshooting Guide](../../CLAUDE.md#troubleshooting)

**Upstream Documentation**:
- [Istio Gateway](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/)
- [Envoy Proxy Debugging](https://www.envoyproxy.io/docs/envoy/latest/operations/admin)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
