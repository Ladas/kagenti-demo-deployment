# Pod in CrashLoopBackOff

**UID**: `pod-crashloop-backoff`
**Severity**: critical
**Component**: application
**Layer**: application

---

### Meaning

**What does this alert mean?**

A pod is repeatedly crashing and Kubernetes is backing off restart attempts. The pod cannot start successfully.

**PromQL Query**:
```promql
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1
```

**Alert fires when**:
- Pod has crashed multiple times
- Kubernetes is in exponential backoff mode (waiting longer between restart attempts)
- Pod startup fails consistently

---

### Impact

**What is the impact of this issue?**

- **User Impact**: Service unavailable if all replicas are crash looping
- **System Impact**:
  - Application functionality lost
  - Potential data corruption if mid-operation crash
  - Resource waste from constant restarts
- **Blast Radius**: Specific pod/container (may affect entire service if single replica)

**Severity Justification**:
- **CRITICAL** because:
  - Indicates systematic failure (not transient)
  - Will not self-recover without intervention
  - May indicate broader configuration or deployment issues

---

### Diagnosis

**How to investigate this alert:**

**1. Identify the crashing pod:**
```bash
# Find pods in CrashLoopBackOff
kubectl get pods -A | grep CrashLoopBackOff

# Get detailed pod status
kubectl describe pod <pod-name> -n <namespace>
```

**2. Check pod logs (current and previous):**
```bash
# Current container logs
kubectl logs <pod-name> -n <namespace> -c <container-name>

# Previous container logs (before crash)
kubectl logs <pod-name> -n <namespace> -c <container-name> --previous

# All containers in pod
kubectl logs <pod-name> -n <namespace> --all-containers=true --previous
```

**3. Check pod events:**
```bash
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name> --sort-by='.lastTimestamp'
```

**4. Check container exit code:**
```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[*].lastState.terminated}'
```

**5. Check resource usage:**
```bash
kubectl top pod <pod-name> -n <namespace>
```

**Common Causes**:
- **Application error**: Bug causing panic/crash on startup
- **Configuration error**: Missing/invalid environment variables or config files
- **Dependency unavailable**: Database, API, or external service not accessible
- **OOMKilled**: Container exceeds memory limits
- **Liveness probe failure**: Health check kills container
- **Permission error**: Cannot read files or access resources
- **Image error**: Wrong image tag or corrupted image

---

### Mitigation

**Immediate Actions**:

1. **Check previous logs for error**:
   ```bash
   kubectl logs <pod-name> -n <namespace> --previous | tail -50
   ```

2. **Common fixes**:

   **If application error**:
   ```bash
   # Check for panic/exception in logs
   # Rollback to previous working version
   kubectl rollout undo deployment/<deployment-name> -n <namespace>
   ```

   **If OOMKilled**:
   ```bash
   # Check exit code 137 (OOMKilled)
   kubectl describe pod <pod-name> -n <namespace> | grep "Exit Code"

   # Increase memory limits (GitOps)
   # Edit deployment YAML to increase resources.limits.memory
   ```

   **If configuration error**:
   ```bash
   # Check ConfigMap/Secret exists
   kubectl get configmap -n <namespace>
   kubectl get secret -n <namespace>

   # Check environment variables
   kubectl describe pod <pod-name> -n <namespace> | grep -A 20 "Environment:"
   ```

   **If dependency unavailable**:
   ```bash
   # Check if dependent service is running
   kubectl get pods -n <namespace> -l app=<dependency>

   # Check network connectivity
   kubectl run test -n <namespace> --image=curlimages/curl --restart=Never --rm -it \
     -- curl -v <service-url>
   ```

   **If liveness probe too aggressive**:
   ```bash
   # Check liveness probe configuration
   kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep -A 10 "livenessProbe"

   # Temporarily disable or adjust probe (GitOps)
   # Increase initialDelaySeconds or failureThreshold
   ```

**Root Cause Resolution**:

1. **Fix application code** (if bug):
   ```bash
   # Deploy fixed version
   # Update image tag in GitOps repo
   git commit -m "Fix crash bug" && git push
   argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web
   ```

2. **Fix configuration** (if config error):
   ```bash
   # Update ConfigMap/Secret
   # Edit via GitOps
   git commit -m "Fix config" && git push
   argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web

   # Force pod restart to pick up new config
   kubectl rollout restart deployment/<deployment-name> -n <namespace>
   ```

3. **Adjust resources** (if OOM):
   ```bash
   # Edit deployment resources (GitOps)
   # Increase memory limits and requests
   # components/<layer>/<service>/deployment.yaml
   ```

**Prevention**:
- Test deployments in dev environment first
- Set appropriate resource limits based on actual usage
- Configure health checks with appropriate timeouts
- Use readiness probes to prevent traffic during startup
- Monitor application logs for errors
- Implement graceful degradation for dependency failures
- Use init containers for dependency checks

**Escalation**:
- If root cause unclear after 15 minutes, escalate to development team
- Provide: pod name, namespace, logs, events, exit code
- Related components: Check dependent services

---

### Related Information

**Related Alerts**:
- `pod-frequent-restarts` - May precede CrashLoopBackOff
- `pod-high-memory-usage` - May cause OOM leading to crashes

**Related Dashboards**:
- Pod Status Dashboard
- Application Logs Dashboard

**Related Documentation**:
- [Troubleshooting Guide](../../CLAUDE.md#troubleshooting)
- [GitOps Workflow](../../CLAUDE.md#development-iteration)

**Upstream Documentation**:
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Debug Crashes](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
