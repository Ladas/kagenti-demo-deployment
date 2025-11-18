# Node Memory Pressure

**UID**: `node-memory-pressure`
**Severity**: warning
**Component**: kubernetes
**Layer**: infrastructure

---

### Meaning

A Kubernetes node is experiencing memory pressure - insufficient memory available.

**PromQL Query**: `kube_node_status_condition{condition="MemoryPressure",status="true"} == 1`

**Alert fires when**: Node reports MemoryPressure condition

---

### Impact

- **User Impact**: Service degradation, potential pod evictions
- **System Impact**: OOM kills, pod evictions, scheduling failures
- **Blast Radius**: All pods on the affected node

**Severity**: **WARNING** - Can lead to pod evictions

---

### Diagnosis

```bash
# Check node status
kubectl describe node <node-name>

# Check memory usage
kubectl top node
kubectl top pods -A --sort-by=memory

# Check memory allocation
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

**Common Causes**: Memory leaks, insufficient memory requests/limits, too many pods on node

---

### Mitigation

**Scale down non-critical workloads**:
```bash
kubectl scale deployment <deployment-name> -n <namespace> --replicas=0
```

**Identify memory-hungry pods**:
```bash
kubectl top pods -A --sort-by=memory | head -20
```

**Prevention**: Set appropriate memory requests/limits, monitor for memory leaks, use HPA

---

### Related Information

**Related Alerts**: `kubernetes-node-not-ready`, `pod-high-memory-usage`
**Upstream**: [Node Conditions](https://kubernetes.io/docs/concepts/architecture/nodes/#condition)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
