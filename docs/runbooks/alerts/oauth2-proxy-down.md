# OAuth2-Proxy Service Down

**UID**: `oauth2-proxy-down`
**Severity**: warning
**Component**: oauth2-proxy
**Layer**: platform

---

### Meaning

OAuth2-Proxy deployment has no available replicas. Access to protected services may be blocked.

**PromQL Query**: `kube_deployment_status_replicas_available{namespace="oauth2-proxy"} == 0`

**Alert fires when**: Any OAuth2-Proxy deployment has 0 available replicas

---

### Impact

- **User Impact**: Cannot access OAuth2-protected services (Phoenix, Tempo, Kiali, etc.)
- **System Impact**: Authentication proxy unavailable, redirect loops possible
- **Blast Radius**: All services using OAuth2-Proxy

**Severity**: **WARNING** - Access impaired but core platform operational

---

### Diagnosis

```bash
kubectl get pods -n oauth2-proxy
kubectl describe pod -n oauth2-proxy -l app=oauth2-proxy
kubectl logs -n oauth2-proxy -l app=oauth2-proxy --tail=100
```

**Common Causes**: Keycloak connectivity failure, configuration error, certificate issues

---

### Mitigation

**Restart OAuth2-Proxy**:
```bash
# Identify which proxy is down
kubectl get deployment -n oauth2-proxy

kubectl rollout restart deployment/<proxy-name> -n oauth2-proxy
```

**Check Keycloak connectivity**:
```bash
kubectl exec -n oauth2-proxy deployment/<proxy-name> -- \
  curl -k https://keycloak.localtest.me:9443/realms/master/.well-known/openid-configuration
```

**Prevention**: Monitor Keycloak availability, validate OAuth2 client configurations

---

### Related Information

**Related Alerts**: `keycloak-down`
**Related Documentation**: [OAuth2 Setup](../../docs/oauth2/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
