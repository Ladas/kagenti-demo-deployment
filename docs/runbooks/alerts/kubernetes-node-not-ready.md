# Kubernetes Node Not Ready

**UID**: `kubernetes-node-not-ready`
**Severity**: critical
**Component**: kubernetes
**Layer**: infrastructure

---

### Meaning

**What does this alert mean?**

A Kubernetes node is in NotReady state, meaning the kubelet is not functioning properly and the node cannot accept new pods.

**PromQL Query**:
```promql
kube_node_status_condition{condition="Ready",status="true"} == 0
```

**Alert fires when**:
- Node kubelet stops reporting healthy status
- Node has lost connectivity to control plane
- Node has critical resource pressure (disk, memory, PID)
- Node has network plugin failure

---

### Impact

**What is the impact of this issue?**

- **User Impact**: Services running on the affected node may become unavailable
- **System Impact**:
  - Pods on the node are marked as NotReady
  - No new pods scheduled to the node
  - Existing pods may be evicted if node stays NotReady
  - Cluster capacity reduced
- **Blast Radius**: All pods running on the affected node

**Severity Justification**:
- **CRITICAL** because:
  - Can cause widespread pod evictions
  - Reduces cluster reliability
  - May indicate node hardware failure
  - Can cascade to other nodes in Kind (single-node cluster)

---

### Diagnosis

**How to investigate this alert:**

**1. Check node status:**
```bash
# List all nodes with status
kubectl get nodes -o wide

# Describe the NotReady node
kubectl describe node <node-name>

# Check node conditions
kubectl get node <node-name> -o jsonpath='{.status.conditions}' | python3 -m json.tool
```

**2. Check kubelet:**
```bash
# For Kind cluster - check kubelet logs in Docker
docker exec kagenti-demo-control-plane journalctl -u kubelet --no-pager | tail -100

# Check kubelet status
docker exec kagenti-demo-control-plane systemctl status kubelet
```

**3. Check node resources:**
```bash
# Check node resource usage
kubectl top node

# Check disk pressure
kubectl get node <node-name> -o jsonpath='{.status.conditions[?(@.type=="DiskPressure")]}'

# Check memory pressure
kubectl get node <node-name> -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")]}'

# Check PID pressure
kubectl get node <node-name> -o jsonpath='{.status.conditions[?(@.type=="PIDPressure")]}'
```

**4. Check pod distribution:**
```bash
# List pods on the node
kubectl get pods -A -o wide --field-selector spec.nodeName=<node-name>

# Check for evicted pods
kubectl get pods -A | grep Evicted
```

**Common Causes**:
- **Disk pressure**: Node running out of disk space
- **Memory pressure**: Node running out of memory
- **Network issues**: CNI plugin failure or connectivity loss
- **Kubelet crash**: Kubelet process died
- **Docker/containerd issues**: Container runtime failure
- **Resource exhaustion**: Too many pods/containers on node

---

### Mitigation

**Immediate Actions**:

1. **Verify the issue**:
   ```bash
   # Check if node is truly NotReady
   kubectl get nodes

   # For Kind cluster, check if Docker container is running
   docker ps | grep kagenti-demo
   ```

2. **Check for resource pressure**:
   ```bash
   # Check node conditions
   kubectl describe node <node-name> | grep -A 10 "Conditions:"
   ```

3. **For Kind cluster - restart node if needed**:
   ```bash
   # ONLY if node is completely unresponsive
   docker restart kagenti-demo-control-plane

   # Wait for node to come back
   kubectl wait --for=condition=Ready node/<node-name> --timeout=5m
   ```

**Root Cause Resolution**:

1. **If disk pressure**:
   ```bash
   # For Kind - clean up unused images
   docker exec kagenti-demo-control-plane crictl rmi --prune

   # Clean up unused volumes
   docker exec kagenti-demo-control-plane sh -c 'rm -rf /var/lib/containerd/tmp/*'

   # Check disk usage
   docker exec kagenti-demo-control-plane df -h
   ```

2. **If memory pressure**:
   ```bash
   # Identify memory-hungry pods
   kubectl top pods -A --sort-by=memory

   # Consider scaling down non-critical workloads
   kubectl scale deployment <deployment-name> -n <namespace> --replicas=0
   ```

3. **If network issues**:
   ```bash
   # Check CNI plugin logs (for Kind using kindnet)
   kubectl logs -n kube-system -l app=kindnet

   # Restart CNI pods if needed
   kubectl delete pod -n kube-system -l app=kindnet
   ```

4. **If kubelet issues**:
   ```bash
   # Restart kubelet (Kind cluster)
   docker exec kagenti-demo-control-plane systemctl restart kubelet

   # Check kubelet is running
   docker exec kagenti-demo-control-plane systemctl status kubelet
   ```

**Prevention**:
- Monitor node resource usage proactively
- Set appropriate resource requests/limits on pods
- Use pod disruption budgets for critical services
- Configure cluster autoscaling (production)
- Regular cleanup of unused images and volumes
- For Kind: Increase Docker Desktop resources if needed

**Escalation**:
- If node doesn't recover in 10 minutes, consider cluster rebuild (Kind)
- For production: Escalate to infrastructure team
- Related components to check:
  - All pods on the affected node
  - Kubernetes control plane components

---

### Related Information

**Related Alerts**:
- `node-cpu-pressure` - CPU resource exhaustion
- `node-memory-pressure` - Memory resource exhaustion
- `pod-crashloop-backoff` - May be caused by node issues

**Related Dashboards**:
- Kubernetes Nodes Dashboard (Grafana)
- Node Resource Usage Dashboard

**Related Documentation**:
- [Kind Cluster Setup](../../scripts/kind/)
- [Troubleshooting Guide](../../CLAUDE.md#troubleshooting)

**Upstream Documentation**:
- [Node Status](https://kubernetes.io/docs/concepts/architecture/nodes/#condition)
- [Debugging Nodes](https://kubernetes.io/docs/tasks/debug/debug-cluster/debug-node/)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
