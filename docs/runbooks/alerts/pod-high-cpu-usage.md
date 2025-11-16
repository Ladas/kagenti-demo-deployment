# Pod High CPU Usage

**UID**: `pod-high-cpu-usage`
**Severity**: warning
**Component**: application
**Layer**: application

---

### Meaning

A pod is using over 90% of its CPU quota.

**PromQL Query**: `sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace, pod, container) / sum(container_spec_cpu_quota{container!="",container!="POD"} / container_spec_cpu_period{container!="",container!="POD"}) by (namespace, pod, container) * 100 > 90`

**Alert fires when**: Pod CPU usage exceeds 90% of limit

---

### Impact

- **User Impact**: Slow response times, degraded performance
- **System Impact**: CPU throttling, potential performance impact on colocated pods
- **Blast Radius**: Specific pod/container

**Severity**: **WARNING** - Performance degradation, not outage

---

### Diagnosis

```bash
# Check pod CPU usage
kubectl top pod <pod-name> -n <namespace>

# Check CPU limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Limits"

# Check logs for high CPU activity
kubectl logs <pod-name> -n <namespace> --tail=100
```

**Common Causes**: High traffic, inefficient code, CPU-intensive operations, infinite loops

---

### Mitigation

**Scale horizontally**:
```bash
kubectl scale deployment <deployment-name> -n <namespace> --replicas=3
```

**Increase CPU limits** (GitOps):
```yaml
# Edit deployment YAML
resources:
  limits:
    cpu: "2000m"  # Increase from current value
  requests:
    cpu: "1000m"
```

**Prevention**: Set appropriate CPU limits, optimize code, use HPA, monitor CPU trends

---

### Related Information

**Related Alerts**: `node-cpu-pressure`
**Upstream**: [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
