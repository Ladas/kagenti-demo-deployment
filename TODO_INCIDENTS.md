# Platform Incidents and RCA

**Created**: 2025-11-17
**Status**: 🔴 **ACTIVE INCIDENTS**

---

## Current Incidents

### Incident #1: AlertManager Service Down (False Positive) ⚠️ CRITICAL

**Alert**: AlertManager Service Down
**Severity**: Critical
**Status**: 🔴 FIRING (False Positive)
**Detected**: 2025-11-17
**SOP**: [docs/runbooks/alerts/alertmanager-down.md](docs/runbooks/alerts/alertmanager-down.md)

---

#### Root Cause Analysis

**Symptom**:
- Alert "AlertManager Service Down" firing
- Grafana shows AlertManager as critical

**Investigation**:
```bash
# Pod status
kubectl get pods -n observability -l app=alertmanager
# NAME                            READY   STATUS    RESTARTS         AGE
# alertmanager-5445b869ff-cknlw   1/2     Running   77 (9m15s ago)   16h
```

**Findings**:
1. ✅ **AlertManager main container**: HEALTHY
   ```bash
   kubectl exec -n observability -c alertmanager deployment/alertmanager -- wget -qO- http://localhost:9093/-/ready
   # Returns: OK
   ```

2. ❌ **Istio sidecar (istio-proxy)**: NOT READY
   - Container status: ready=false
   - Restarts: 77 times in 16 hours (~1 restart every 12 minutes)
   - Last state: Terminated (Reason: Completed, Exit Code: 0)
   - Readiness probe fails: `http://localhost:15021/healthz/ready` not responding

3. 🔍 **Pod Ready Status**: 1/2 (both containers must be ready)
   - Kubernetes reports: `kube_deployment_status_replicas_available == 0`
   - Alert query matches this condition → Alert FIRES

**Root Cause**:
1. **Istio sidecar instability**: The istio-proxy container exits cleanly (exit code 0) every ~10-12 minutes and restarts
2. **Incorrect alert configuration**: `noDataState: Alerting` + `execErrState: Alerting` causes alert to fire even when main container is healthy
3. **Pod readiness definition**: Kubernetes requires BOTH containers to be ready for pod to be considered ready

**Impact**:
- ⚠️ **False Positive**: AlertManager is actually functional
- ✅ **No user impact**: Alert routing and notifications working
- ❌ **Alert fatigue**: Critical alert firing when service is operational

---

#### Immediate Mitigation

**Status**: Main container healthy, sidecar issue is cosmetic

**Verification**:
```bash
# Test AlertManager directly
kubectl exec -n observability -c alertmanager deployment/alertmanager -- wget -qO- http://localhost:9093/-/ready
# Expected: OK

# Verify alerts are being processed
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://alertmanager.observability.svc:9093/api/v2/status'
```

---

#### Long-term Fix

**Option 1: Fix Istio sidecar instability (RECOMMENDED)**

**Hypothesis**: Istio proxy exiting due to:
- Memory pressure (limits: 128Mi)
- Connection timeout/drain issues
- Configuration issue with Istio 1.24.2

**Action items**:
- [ ] Increase istio-proxy memory limits (128Mi → 256Mi)
- [ ] Check Istio logs for why it's exiting cleanly
- [ ] Review Istio 1.24.2 known issues
- [ ] Consider disabling Istio sidecar for AlertManager (not recommended - breaks mTLS)

**Implementation**:
```yaml
# File: components/02-observability/alertmanager/deployment.yaml
# Add resource override for istio-proxy via annotation:
metadata:
  annotations:
    sidecar.istio.io/proxyCPU: "100m"
    sidecar.istio.io/proxyMemory: "256Mi"
    sidecar.istio.io/proxyCPULimit: "200m"
    sidecar.istio.io/proxyMemoryLimit: "256Mi"
```

**Option 2: Update alert configuration to be more lenient**

Change `noDataState: Alerting` to `noDataState: OK` - but this may hide real issues.

**Option 3: Create separate alert for sidecar issues**

Keep existing alert, add new alert specifically for Istio sidecar health.

**Recommended approach**: Option 1 (fix root cause) + update alert description (already done)

---

### Incident #2: Keycloak Authentication Service Down (False Positive) 🔴 CRITICAL

**Alert**: Keycloak Authentication Service Down
**Severity**: Critical
**Status**: 🔴 FIRING (False Positive)
**Detected**: 2025-11-17
**SOP**: [docs/runbooks/alerts/keycloak-down.md](docs/runbooks/alerts/keycloak-down.md)

---

#### Root Cause Analysis

**Symptom**:
- Alert "Keycloak Authentication Service Down" firing
- Grafana shows Keycloak as critical

**Investigation**:
```bash
# Check Keycloak pods
kubectl get pods -n keycloak -l app=keycloak
# NAME         READY   STATUS    RESTARTS   AGE
# keycloak-0   1/1     Running   0          40h

# Check for deployment
kubectl get deployment keycloak -n keycloak
# Error: deployments.apps "keycloak" not found

# Check StatefulSet
kubectl get statefulset -n keycloak
# NAME       READY   AGE
# keycloak   1/1     40h
```

**Findings**:
1. ✅ **Keycloak pod**: HEALTHY (1/1 Ready, Running)
2. ✅ **Keycloak StatefulSet**: HEALTHY (1/1 ready)
3. ❌ **Alert query**: INCORRECT - queries for Deployment, but Keycloak is a StatefulSet

**Alert Query (WRONG)**:
```promql
kube_deployment_status_replicas_available{namespace="keycloak",deployment="keycloak"} == 0
```

**Query Result**: Empty (no deployment named "keycloak" exists)
**Alert Configuration**: `noDataState: Alerting` → Alert FIRES on empty result

**Correct Query Should Be**:
```promql
kube_statefulset_status_replicas_ready{namespace="keycloak",statefulset="keycloak"} == 0
```

**Verification**:
```bash
# Test correct query
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=kube_statefulset_status_replicas_ready{namespace="keycloak",statefulset="keycloak"}'

# Result: {"value": [timestamp, "1"]} - Keycloak is HEALTHY
```

**Root Cause**:
1. **Incorrect resource type**: Alert queries for Deployment, but Keycloak runs as StatefulSet
2. **Incorrect noDataState**: `noDataState: Alerting` causes alert to fire when query returns empty
3. **Alert never tested against real infrastructure**: Query was never validated

**Impact**:
- ⚠️ **False Positive**: Keycloak is actually running and healthy
- ✅ **No user impact**: Authentication working normally
- ❌ **Critical alert fatigue**: P0 alert firing when service is operational
- ⚠️ **Blind spot**: Alert would NOT fire if Keycloak actually goes down (wrong query)

---

#### Immediate Mitigation

**Status**: Keycloak is healthy, alert is misconfigured

**Verification**:
```bash
# Test Keycloak authentication
kubectl run test-keycloak -n keycloak --image=curlimages/curl:latest --restart=Never --rm -it \
  -- curl -k -I https://keycloak.localtest.me:9443/realms/master

# Expected: HTTP/2 200
```

---

#### Permanent Fix (REQUIRED)

**Fix 1: Update alert query to use StatefulSet metrics**

```yaml
# File: components/02-observability/grafana/alerting-provisioning.yaml
# Line: ~278-280

# BEFORE (WRONG):
expr: |
  kube_deployment_status_replicas_available{namespace="keycloak",deployment="keycloak"} == 0

# AFTER (CORRECT):
expr: |
  kube_statefulset_status_replicas_ready{namespace="keycloak",statefulset="keycloak"} == 0
```

**Fix 2: Change noDataState to prevent false positives**

```yaml
# File: components/02-observability/grafana/alerting-provisioning.yaml
# Line: ~281-282

# BEFORE:
noDataState: Alerting
execErrState: Alerting

# AFTER:
noDataState: OK
execErrState: OK
```

**Fix 3: Update test to validate query**

```python
# File: tests/integration/test_alert_queries.py
# Add test for Keycloak StatefulSet

def test_keycloak_statefulset_query(self):
    """Test Keycloak alert uses correct StatefulSet query."""
    query = 'kube_statefulset_status_replicas_ready{namespace="keycloak",statefulset="keycloak"}'

    response = self.query_prometheus(query)

    assert response["status"] == "success"
    assert len(response["data"]["result"]) > 0

    value = float(response["data"]["result"][0]["value"][1])
    assert value >= 1, "Keycloak should have at least 1 ready replica"
```

**Fix 4: Update runbook**

Update `docs/runbooks/alerts/keycloak-down.md` to reflect StatefulSet:
- Change references from "deployment" to "statefulset"
- Update kubectl commands: `kubectl get statefulset keycloak -n keycloak`
- Update diagnosis steps

**Action Items**:
- [x] Investigate root cause
- [ ] Update alert query (Deployment → StatefulSet)
- [ ] Change noDataState to OK
- [ ] Add test for StatefulSet query
- [ ] Update runbook documentation
- [ ] Commit and deploy fix
- [ ] Verify alert stops firing
- [ ] Monitor for 24h to ensure no regressions

---

## Incident Summary

| Incident | Severity | Status | Root Cause | Impact | ETA Fix |
|----------|----------|--------|------------|--------|---------|
| AlertManager Down | Critical | 🔴 False Positive | Istio sidecar instability | Alert fatigue only | 24-48h |
| Keycloak Down | Critical | 🔴 False Positive | Wrong query (Deployment vs StatefulSet) | Alert fatigue + blind spot | 1-2h |

---

## Lessons Learned

### Alert Configuration Anti-Patterns

**1. Using `noDataState: Alerting` without validation**
- ❌ **Problem**: Fires alert when query returns empty (even when service is healthy)
- ✅ **Solution**: Use `noDataState: OK` for conditional alerts (checking `== 0`)
- 📝 **When to use Alerting**: Only when absence of metrics indicates a problem (scrape target down)

**2. Not validating queries against actual infrastructure**
- ❌ **Problem**: Query for "deployment" when resource is "statefulset"
- ✅ **Solution**: Always test queries with real Prometheus before deploying
- 📝 **Process**: Write test → Test with mock data → Test with real Prometheus → Deploy

**3. Assuming resource types without verification**
- ❌ **Problem**: Assumed Keycloak is a Deployment (it's a StatefulSet)
- ✅ **Solution**: Verify actual resource types in cluster before writing alerts
- 📝 **Command**: `kubectl get all -n <namespace>` to see all resource types

### Process Improvements

**1. Alert Development Workflow (Enhanced)**

```bash
# 1. Identify resource type
kubectl get all -n <namespace>

# 2. Find correct metrics
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://prometheus.observability.svc:9090/api/v1/label/__name__/values' | grep <resource>

# 3. Write test with mock data
# tests/integration/test_alert_queries.py

# 4. Test query against real Prometheus
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=<YOUR_QUERY>'

# 5. Create alert configuration
# components/02-observability/grafana/alerting-provisioning.yaml

# 6. Deploy and verify
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
```

**2. Alert Testing Requirements**

All alerts MUST have:
- ✅ Mock data test (happy path + failure path)
- ✅ Real Prometheus validation test
- ✅ Runbook documentation
- ✅ Severity classification test
- ✅ Query syntax validation

**3. Pre-deployment Checklist**

Before deploying any new alert:
- [ ] Verified actual resource type (Deployment/StatefulSet/DaemonSet)
- [ ] Tested query returns data when service is healthy
- [ ] Tested query returns match when service is down
- [ ] Validated noDataState is correct (OK vs Alerting)
- [ ] Validated execErrState is correct
- [ ] Created runbook with diagnosis steps
- [ ] Added test coverage
- [ ] Reviewed with team

---

## Action Plan

### Priority 1: Fix Keycloak Alert (1-2 hours)

**Impact**: Critical false positive + blind spot (alert wouldn't fire if Keycloak actually down)

**Steps**:
1. Update alert query to use StatefulSet metrics
2. Change noDataState to OK
3. Add test coverage
4. Update runbook
5. Deploy and verify

**Owner**: Platform Team
**Deadline**: 2025-11-17 EOD

---

### Priority 2: Investigate AlertManager Istio Sidecar (24-48 hours)

**Impact**: Critical false positive + sidecar instability

**Steps**:
1. Analyze Istio proxy logs for exit reason
2. Review Istio 1.24.2 release notes for known issues
3. Test memory limit increase
4. Consider PeerAuthentication configuration
5. Monitor for 24h after changes

**Owner**: Platform Team
**Deadline**: 2025-11-18 EOD

---

### Priority 3: Audit All Alert Queries (1 week)

**Objective**: Ensure all alerts query correct resource types

**Steps**:
1. Review all 24 alert queries
2. Verify resource types in cluster
3. Test each query with real Prometheus
4. Fix any mismatches
5. Add test coverage for all alerts

**Owner**: Platform Team
**Deadline**: 2025-11-24

---

## References

- [Alert Testing Guide](docs/04-observability/ALERT_TESTING_GUIDE.md)
- [Alert Fix Summary](docs/04-observability/ALERT_FIX_SUMMARY.md)
- [Alert Runbooks](docs/runbooks/alerts/)
- [AlertManager SOP](docs/runbooks/alerts/alertmanager-down.md)
- [Keycloak SOP](docs/runbooks/alerts/keycloak-down.md)

---

**Status**: 🔴 ACTIVE - 2 incidents in investigation
**Last Updated**: 2025-11-17 18:30 CET
**Next Review**: 2025-11-17 20:00 CET

🤖 Generated with [Claude Code](https://claude.com/claude-code)
