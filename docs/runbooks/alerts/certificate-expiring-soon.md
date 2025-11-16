# TLS Certificate Expiring Soon

**UID**: `certificate-expiring-soon`
**Severity**: warning
**Component**: cert-manager
**Layer**: infrastructure

---

### Meaning

A TLS certificate expires in less than 14 days.

**PromQL Query**: `(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 14`

**Alert fires when**: Certificate has less than 14 days until expiration

---

### Impact

- **User Impact**: Service may become unreachable when certificate expires
- **System Impact**: TLS handshake failures, browser warnings, service disruption
- **Blast Radius**: Specific service using the expiring certificate

**Severity**: **WARNING** - Proactive alert, gives time to renew before expiration

---

### Diagnosis

```bash
# List all certificates
kubectl get certificate -A

# Describe specific certificate
kubectl describe certificate <cert-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=100
```

**Common Causes**: cert-manager not running, Let's Encrypt rate limits, DNS challenge failure, ACME solver issues

---

### Mitigation

**Force certificate renewal**:
```bash
# Delete certificate secret (cert-manager will recreate)
kubectl delete secret <cert-secret-name> -n <namespace>

# Annotate certificate to force renewal
kubectl annotate certificate <cert-name> -n <namespace> \
  cert-manager.io/issue-temporary-certificate="true" --overwrite
```

**Check cert-manager**:
```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager deployment/cert-manager
```

**Prevention**: Monitor cert-manager health, ensure ACME challenges can complete, avoid rate limits

---

### Related Information

**Related Alerts**: `gateway-unhealthy` (may fail if certificates expire)
**Upstream**: [cert-manager Troubleshooting](https://cert-manager.io/docs/troubleshooting/)

**Last Updated**: 2025-11-16

🤖 Generated with [Claude Code](https://claude.com/claude-code)
