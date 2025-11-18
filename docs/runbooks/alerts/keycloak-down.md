# Keycloak Authentication Service Down

**UID**: `keycloak-down`
**Severity**: critical
**Component**: keycloak
**Layer**: platform

---

### Meaning

**What does this alert mean?**

The Keycloak authentication service has no available replicas, meaning user authentication and authorization are completely unavailable.

**PromQL Query**:
```promql
kube_deployment_status_replicas_available{namespace="keycloak",deployment="keycloak"} == 0
```

**Alert fires when**:
- Keycloak deployment has 0 available (ready) replicas
- All Keycloak pods are down or not ready
- Keycloak deployment is scaled to 0

---

### Impact

**What is the impact of this issue?**

- **User Impact**: **ALL user authentication fails**. Users cannot:
  - Log in to any platform service (Grafana, Phoenix, Kiali, etc.)
  - Obtain OAuth2 tokens
  - Access any OAuth2-protected service
  - New sessions cannot be created (existing sessions may work until expiry)
- **System Impact**:
  - OAuth2-Proxy cannot validate tokens
  - Service-to-service authentication blocked (if using Keycloak)
  - User management unavailable
- **Blast Radius**: All services requiring authentication (entire platform)

**Severity Justification**:
- **CRITICAL** because:
  - Complete authentication outage
  - No alternative authentication method
  - Blocks all user access to protected services
  - Platform effectively unusable for new sessions

---

### Diagnosis

**How to investigate this alert:**

**1. Check Keycloak pod status:**
```bash
# Check Keycloak pods
kubectl get pods -n keycloak -l app=keycloak

# Describe pod for events
kubectl describe pod -n keycloak -l app=keycloak

# Check logs
kubectl logs -n keycloak -l app=keycloak --tail=100
```

**2. Check Keycloak deployment:**
```bash
# Check deployment status
kubectl get deployment keycloak -n keycloak

# Check replica count and conditions
kubectl describe deployment keycloak -n keycloak
```

**3. Check Keycloak database:**
```bash
# If using PostgreSQL
kubectl get pods -n keycloak -l app=postgresql

# Check database logs
kubectl logs -n keycloak -l app=postgresql --tail=50
```

**4. Test Keycloak endpoint:**
```bash
# Test from within cluster
kubectl run test-keycloak -n keycloak --image=curlimages/curl:latest --restart=Never --rm -it \
  -- curl -k -I https://keycloak.localtest.me:9443

# Check realm configuration
kubectl exec -n keycloak deployment/keycloak -- \
  curl -s http://localhost:8080/realms/master/.well-known/openid-configuration
```

**5. Check recent events:**
```bash
kubectl get events -n keycloak --sort-by='.lastTimestamp' | tail -20
```

**Common Causes**:
- Database connectivity failure (PostgreSQL/H2)
- Configuration error in realm import
- Out of memory (Java heap exhaustion)
- Image pull failure
- Certificate/TLS configuration issues
- Database migration failure on startup
- Resource limits too restrictive

---

### Mitigation

**Immediate Actions**:

1. **Verify the issue is real**:
   ```bash
   # Check if Keycloak pods exist
   kubectl get pods -n keycloak -l app=keycloak

   # Check if deployment exists
   kubectl get deployment keycloak -n keycloak
   ```

2. **Check for common issues**:
   - **CrashLoopBackOff**: Check logs for Java exceptions or config errors
   - **OOMKilled**: Check if pod was killed due to memory
   - **ImagePullBackOff**: Verify image exists
   - **Pending**: Check for resource constraints

3. **Restart Keycloak** (if pods exist but failing):
   ```bash
   kubectl rollout restart deployment/keycloak -n keycloak

   # Wait for rollout
   kubectl rollout status deployment/keycloak -n keycloak --timeout=5m
   ```

4. **Scale up Keycloak** (if scaled to 0):
   ```bash
   kubectl scale deployment/keycloak -n keycloak --replicas=1
   ```

**Root Cause Resolution**:

1. **If database connection issues**:
   ```bash
   # Check database pod
   kubectl get pods -n keycloak -l app=postgresql

   # Check database logs for errors
   kubectl logs -n keycloak -l app=postgresql --tail=100

   # Verify database service
   kubectl get svc -n keycloak | grep postgres

   # Test database connectivity from Keycloak pod
   kubectl exec -n keycloak deployment/keycloak -- \
     nc -zv postgresql.keycloak.svc 5432
   ```

2. **If OOM issues**:
   ```bash
   # Check Keycloak pod resource usage
   kubectl top pod -n keycloak -l app=keycloak

   # Increase Java heap size via environment variable (GitOps)
   # Edit components/01-platform/keycloak/deployment.yaml
   # Add: JAVA_OPTS_APPEND: "-Xms512m -Xmx1024m"
   ```

3. **If realm import fails**:
   ```bash
   # Check realm import job
   kubectl get jobs -n keycloak

   # Check realm import logs
   kubectl logs -n keycloak job/keycloak-realm-import

   # Verify realm configuration
   kubectl get configmap -n keycloak | grep realm
   ```

4. **If certificate issues**:
   ```bash
   # Check certificates
   kubectl get certificate -n keycloak

   # Describe certificate
   kubectl describe certificate keycloak-tls -n keycloak

   # Check if cert-manager created the secret
   kubectl get secret -n keycloak | grep tls
   ```

**Prevention**:
- Set appropriate JVM heap sizes based on usage
- Monitor Keycloak resource usage
- Use persistent volume for Keycloak database (H2) or external PostgreSQL
- Regular backup of Keycloak realms and users
- Test realm configurations before applying
- Enable readiness/liveness probes with appropriate timeouts
- Monitor database connection pool usage

**Escalation**:
- If issue persists after 10 minutes, escalate to platform team
- This is a **P0 incident** - complete authentication outage
- Related components to check:
  - OAuth2-Proxy (will also fail)
  - PostgreSQL database
  - Certificate manager
  - Gateway (for external access)

---

### Related Information

**Related Alerts**:
- `oauth2-proxy-down` - OAuth2 proxies will fail without Keycloak
- `gateway-unhealthy` - May block external Keycloak access

**Related Dashboards**:
- Keycloak Metrics Dashboard (if available)
- Authentication Flow Dashboard

**Related Documentation**:
- [OAuth2 Setup](../../docs/oauth2/)
- [Platform Status](../../CLAUDE.md#monitoring--access)

**Upstream Documentation**:
- [Keycloak Server Administration](https://www.keycloak.org/docs/latest/server_admin/)
- [Keycloak on Kubernetes](https://www.keycloak.org/operator/installation)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
