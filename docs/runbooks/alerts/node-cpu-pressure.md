# Node CPU Pressure

**UID**: `node-cpu-pressure`
**Severity**: warning
**Component**: kubernetes
**Layer**: infrastructure

---

### Meaning

A Kubernetes node is experiencing CPU pressure - insufficient CPU resources available.

**PromQL Query**: `kube_node_status_condition{condition="CPUPressure",status="true"} == 1`

**Alert fires when**: Node reports CPUPressure condition

---

### Impact

- **User Impact**: Degraded performance, slow response times
- **System Impact**: Pod evictions possible, scheduling delays, throttling
- **Blast Radius**: All pods on the affected node

**Severity**: **WARNING** - Performance degradation, not outage

---

### Diagnosis

```bash
# Check node status
kubectl describe node <node-name>

# Check CPU usage
kubectl top node
kubectl top pods -A --sort-by=cpu

# Check CPU throttling
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

**Common Causes**: Too many CPU-intensive workloads, insufficient CPU requests/limits, CPU-bound applications

---

### Mitigation

**Scale down non-critical workloads**:
```bash
kubectl scale deployment <deployment-name> -n <namespace> --replicas=0
```

**Identify CPU-hungry pods**:
```bash
kubectl top pods -A --sort-by=cpu | head -20
```

**Prevention**: Set appropriate CPU requests/limits, use HPA for autoscaling, monitor CPU usage trends

---

### Related Information

**Related Alerts**: `kubernetes-node-not-ready`, `pod-high-cpu-usage`
**Upstream**: [Node Conditions](https://kubernetes.io/docs/concepts/architecture/nodes/#condition)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
