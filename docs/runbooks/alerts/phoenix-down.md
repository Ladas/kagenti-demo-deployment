# Phoenix LLM Observability Down

**UID**: `phoenix-down`
**Severity**: warning
**Component**: phoenix
**Layer**: observability

---

### Meaning

Phoenix LLM observability service has no available replicas. Agent trace visibility is impacted.

**PromQL Query**: `kube_deployment_status_replicas_available{namespace="observability",deployment="phoenix"} == 0`

**Alert fires when**: Phoenix deployment has 0 available replicas

---

### Impact

- **User Impact**: Cannot view LLM/agent traces and spans in Phoenix UI
- **System Impact**: LLM trace collection stopped, agent observability degraded
- **Blast Radius**: LLM observability only

**Severity**: **WARNING** - Agent tracing impaired but agents continue running

---

### Diagnosis

```bash
kubectl get pods -n observability -l app=phoenix
kubectl describe pod -n observability -l app=phoenix
kubectl logs -n observability -l app=phoenix --tail=100
```

**Common Causes**: Pod crashed, database connectivity issues, configuration error

---

### Mitigation

**Restart Phoenix**:
```bash
kubectl rollout restart deployment/phoenix -n observability
```

**Check mTLS configuration**:
```bash
# Phoenix needs PERMISSIVE mTLS for OAuth2-Proxy
kubectl get peerauthentication -n observability phoenix-mtls-permissive
```

**Prevention**: Monitor Phoenix resource usage, validate trace data retention

---

### Related Information

**Related Alerts**: `oauth2-proxy-down` (Phoenix is OAuth2-protected)
**Related Documentation**: [mTLS Configuration](../../docs/ENCRYPTION_ARCHITECTURE.md)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
