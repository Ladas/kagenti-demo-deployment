# Kagenti Operator Down

**UID**: `kagenti-operator-down`
**Severity**: critical
**Component**: kagenti-operator
**Layer**: platform

---

### Meaning

**What does this alert mean?**

The Kagenti operator is down. Agent lifecycle management is impacted.

**PromQL Query**:
```promql
kube_deployment_status_replicas_available{namespace="kagenti-system",deployment=~"kagenti-.*"} == 0
```

**Alert fires when**:
- Kagenti operator deployment has 0 available replicas
- Operator pod is down or not ready

---

### Impact

**What is the impact of this issue?**

- **User Impact**: Cannot create, update, or delete agents
- **System Impact**:
  - Agent custom resources not reconciled
  - Agent deployments not managed
  - Agent configuration changes not applied
- **Blast Radius**: All Kagenti agent operations

**Severity Justification**:
- **CRITICAL** because operator is core to Kagenti platform functionality

---

### Diagnosis

**How to investigate this alert:**

**1. Check operator pod:**
```bash
kubectl get pods -n kagenti-system -l app.kubernetes.io/name=kagenti-operator
kubectl describe pod -n kagenti-system -l app.kubernetes.io/name=kagenti-operator
kubectl logs -n kagenti-system -l app.kubernetes.io/name=kagenti-operator --tail=100
```

**2. Check deployment:**
```bash
kubectl get deployment -n kagenti-system | grep kagenti
kubectl describe deployment -n kagenti-system -l app.kubernetes.io/name=kagenti-operator
```

**3. Check CRDs:**
```bash
kubectl get crd | grep kagenti
```

**Common Causes**:
- Pod crashed due to reconciliation error
- CRD installation issues
- Kubernetes API connectivity problems
- Resource limits exceeded

---

### Mitigation

**Immediate Actions**:

1. **Restart operator**:
   ```bash
   kubectl rollout restart deployment -n kagenti-system -l app.kubernetes.io/name=kagenti-operator
   ```

**Root Cause Resolution**:

1. **Check CRDs**:
   ```bash
   kubectl get crd | grep kagenti
   kubectl describe crd agents.kagenti.io
   ```

2. **Check RBAC**:
   ```bash
   kubectl get clusterrole | grep kagenti
   kubectl get clusterrolebinding | grep kagenti
   ```

**Prevention**:
- Monitor operator logs for reconciliation errors
- Keep operator version updated
- Test agent CRD changes in dev environment

**Escalation**: Escalate to platform team if not resolved in 10 minutes

---

### Related Information

**Related Documentation**: [Kagenti Architecture](../../argocd_architecture.md)
**Upstream**: Kagenti operator documentation (internal)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
