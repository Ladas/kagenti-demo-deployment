# Alert Runbook Template

This template follows the prometheus-operator standardized format for alert runbooks.

---

## Alert Name: [Alert Title]

**UID**: `[alert-uid]`
**Severity**: [critical/warning/info]
**Component**: [component-name]
**Layer**: [infrastructure/platform/observability/application]

---

### Meaning

**What does this alert mean?**

[Clear explanation of what condition triggers this alert]

**PromQL Query**:
```promql
[The actual PromQL query that triggers the alert]
```

**Alert fires when**:
- [Condition 1]
- [Condition 2]

---

### Impact

**What is the impact of this issue?**

- **User Impact**: [How does this affect end users?]
- **System Impact**: [How does this affect the platform?]
- **Blast Radius**: [What systems/services are affected?]

**Severity Justification**:
- [Why is this alert critical/warning/info?]

---

### Diagnosis

**How to investigate this alert:**

**1. Check alert details:**
```bash
# View firing alert
kubectl exec -n observability deployment/grafana -- \
  curl -s 'http://localhost:3000/api/alertmanager/grafana/api/v2/alerts' \
  -u admin:admin123 | grep -A 20 "[alert-uid]"
```

**2. Check component status:**
```bash
# Check pods
kubectl get pods -n [namespace] -l app=[component]

# Check deployment
kubectl get deployment [deployment-name] -n [namespace]

# Check logs
kubectl logs -n [namespace] deployment/[deployment-name] --tail=100
```

**3. Check metrics:**
```bash
# Query Prometheus
kubectl exec -n observability deployment/grafana -- \
  curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
  --data-urlencode 'query=[PROMQL_QUERY]' | python3 -m json.tool
```

**4. Check recent events:**
```bash
kubectl get events -n [namespace] --sort-by='.lastTimestamp' | tail -20
```

**Common Causes**:
- [Cause 1]
- [Cause 2]
- [Cause 3]

---

### Mitigation

**Immediate Actions**:

1. **Verify the issue is real**:
   ```bash
   [verification command]
   ```

2. **Check for known issues**:
   - [Known issue 1]
   - [Known issue 2]

3. **Restart the service** (if appropriate):
   ```bash
   kubectl rollout restart deployment/[deployment-name] -n [namespace]
   ```

**Root Cause Resolution**:

1. **[Resolution step 1]**:
   ```bash
   [command]
   ```

2. **[Resolution step 2]**:
   ```bash
   [command]
   ```

**Prevention**:
- [Prevention measure 1]
- [Prevention measure 2]

**Escalation**:
- If issue persists after [X minutes], escalate to: [team/person]
- Related components to check: [component-list]

---

### Related Information

**Related Alerts**:
- [Related alert 1]
- [Related alert 2]

**Related Dashboards**:
- [Dashboard URL or name]

**Related Documentation**:
- [Link to component docs]
- [Link to architecture docs]

**Upstream Documentation**:
- [Link to official component documentation]

---

**Last Updated**: [YYYY-MM-DD]
**Maintainer**: Kagenti Platform Team

🤖 Generated with [Claude Code](https://claude.com/claude-code)
