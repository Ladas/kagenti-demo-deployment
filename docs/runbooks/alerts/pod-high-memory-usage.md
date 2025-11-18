# Pod High Memory Usage

**UID**: `pod-high-memory-usage`
**Severity**: warning
**Component**: application
**Layer**: application

---

### Meaning

A pod is using over 90% of its memory limit.

**PromQL Query**: `sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace, pod, container) / sum(container_spec_memory_limit_bytes{container!="",container!="POD"}) by (namespace, pod, container) * 100 > 90`

**Alert fires when**: Pod memory usage exceeds 90% of limit

---

### Impact

- **User Impact**: Service degradation, potential crashes
- **System Impact**: Risk of OOMKill, pod restart
- **Blast Radius**: Specific pod/container

**Severity**: **WARNING** - High risk of OOM, may lead to pod restart

---

### Diagnosis

```bash
# Check pod memory usage
kubectl top pod <pod-name> -n <namespace>

# Check memory limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Limits"

# Check for memory leaks in logs
kubectl logs <pod-name> -n <namespace> --tail=100
```

**Common Causes**: Memory leak, high traffic, large data processing, insufficient limits

---

### Mitigation

**Increase memory limits** (GitOps):
```yaml
# Edit deployment YAML
resources:
  limits:
    memory: "2Gi"  # Increase from current value
  requests:
    memory: "1Gi"
```

**Restart pod** (if memory leak suspected):
```bash
kubectl delete pod <pod-name> -n <namespace>
```

**Prevention**: Fix memory leaks, set appropriate limits, monitor memory trends, use HPA

---

### Related Information

**Related Alerts**: `node-memory-pressure`, `pod-crashloop-backoff` (if OOMKilled)
**Upstream**: [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
