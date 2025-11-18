# Tekton Pipelines Controller Down

**UID**: `tekton-controller-down`
**Severity**: critical
**Component**: tekton
**Layer**: platform

---

### Meaning

**What does this alert mean?**

The Tekton Pipelines controller is down. Pipeline execution and task management are unavailable.

**PromQL Query**:
```promql
kube_deployment_status_replicas_available{namespace="tekton-pipelines",deployment="tekton-pipelines-controller"} == 0
```

**Alert fires when**:
- Tekton controller deployment has 0 available replicas
- Controller pod is down or not ready
- Controller deployment is scaled to 0

---

### Impact

**What is the impact of this issue?**

- **User Impact**: Cannot trigger or run CI/CD pipelines
- **System Impact**:
  - New PipelineRuns and TaskRuns cannot be created
  - Running pipelines may complete but cannot be monitored
  - Pipeline status updates stop
  - Webhook events not processed
- **Blast Radius**: All Tekton-based CI/CD automation

**Severity Justification**:
- **CRITICAL** because:
  - Core CI/CD functionality unavailable
  - Blocks automated deployments
  - Impacts development workflow
  - May block incident remediation requiring pipeline runs

---

### Diagnosis

**How to investigate this alert:**

**1. Check controller pod:**
```bash
kubectl get pods -n tekton-pipelines -l app=tekton-pipelines-controller
kubectl describe pod -n tekton-pipelines -l app=tekton-pipelines-controller
kubectl logs -n tekton-pipelines -l app=tekton-pipelines-controller --tail=100
```

**2. Check deployment:**
```bash
kubectl get deployment tekton-pipelines-controller -n tekton-pipelines
kubectl describe deployment tekton-pipelines-controller -n tekton-pipelines
```

**3. Check running pipelines:**
```bash
kubectl get pipelineruns -A
kubectl get taskruns -A
```

**Common Causes**:
- Pod crashed due to panic or fatal error
- Kubernetes API connectivity issues
- Webhook configuration errors
- Resource limits exceeded
- RBAC permission issues

---

### Mitigation

**Immediate Actions**:

1. **Restart controller**:
   ```bash
   kubectl rollout restart deployment/tekton-pipelines-controller -n tekton-pipelines
   kubectl rollout status deployment/tekton-pipelines-controller -n tekton-pipelines
   ```

**Root Cause Resolution**:

1. **Check for webhook issues**:
   ```bash
   kubectl get validatingwebhookconfigurations | grep tekton
   kubectl get mutatingwebhookconfigurations | grep tekton
   ```

2. **Verify RBAC**:
   ```bash
   kubectl get clusterrole | grep tekton
   kubectl get clusterrolebinding | grep tekton
   ```

**Prevention**:
- Monitor controller resource usage
- Set appropriate resource limits
- Keep Tekton version updated
- Test pipeline changes in dev first

**Escalation**: Platform team if not resolved in 10 minutes

---

### Related Information

**Related Alerts**: None specific
**Related Documentation**: [Tekton Documentation](https://tekton.dev/docs/)
**Upstream**: [Tekton Troubleshooting](https://tekton.dev/docs/pipelines/troubleshooting/)

---

**Last Updated**: 2025-11-16
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
