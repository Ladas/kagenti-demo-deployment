# Pod Restarting Frequently

**UID**: `pod-frequent-restarts`
**Severity**: warning
**Component**: application
**Layer**: application

---

### Meaning

A pod has restarted more than 3 times in the last 15 minutes.

**PromQL Query**: `increase(kube_pod_container_status_restarts_total[15m]) > 3`

**Alert fires when**: Pod restart count increases by more than 3 in 15 minutes

---

### Impact

- **User Impact**: Service interruptions, connection resets
- **System Impact**: Degraded service availability, potential data inconsistency
- **Blast Radius**: Specific pod/container

**Severity**: **WARNING** - May lead to CrashLoopBackOff if continues

---

### Diagnosis

```bash
# Check pod restart count
kubectl get pod <pod-name> -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs from previous instance
kubectl logs <pod-name> -n <namespace> --previous

# Check liveness probe configuration
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 "livenessProbe"
```

**Common Causes**: Liveness probe too aggressive, application crashes, OOM, dependency failures

---

### Mitigation

**Check why pod is restarting**:
```bash
kubectl logs <pod-name> -n <namespace> --previous
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "State:"
```

**Adjust liveness probe** (if too aggressive):
```yaml
livenessProbe:
  initialDelaySeconds: 60  # Increase
  periodSeconds: 30
  failureThreshold: 5  # Increase
```

**Prevention**: Optimize liveness probes, fix application bugs, ensure dependencies are available

---

### Related Information

**Related Alerts**: `pod-crashloop-backoff` (next stage if restarts continue)
**Upstream**: [Configure Liveness Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
