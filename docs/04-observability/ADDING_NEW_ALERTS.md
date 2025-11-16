# Adding New Alerts to Grafana

**Last Updated**: 2025-11-16

This guide explains how to create, provision, and manage alert rules in the Kagenti observability stack.

---

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Alert Rule Structure](#alert-rule-structure)
- [Creating New Alert Rules](#creating-new-alert-rules)
- [Provisioning Methods](#provisioning-methods)
- [Testing Alert Rules](#testing-alert-rules)
- [Alert Severity Levels](#alert-severity-levels)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)

---

## 🏗️ Architecture Overview

The Kagenti alerting architecture follows this flow:

```
Grafana Alert Rules → Evaluate Metrics/Logs/Traces
         ↓
   Condition Met (Firing)
         ↓
   Send to Grafana Alertmanager (internal routing)
         ↓
   Forward to External AlertManager (configured as contact point)
         ↓
  AlertManager
    ├→ Route to notification channels (Slack, PagerDuty, Email)
    └→ Send to Korrel8r for signal correlation
              ↓
       Korrel8r stores: alert + related traces/logs/metrics
              ↓
       Grafana UI queries Korrel8r API
         to show correlated signals
```

**Key Components**:
- **Grafana Unified Alerting**: Evaluates alert rules, generates alerts
- **Grafana Alertmanager**: Internal routing and grouping
- **External AlertManager**: Advanced routing, deduplication, silencing, inhibition
- **Korrel8r**: Signal correlation for faster incident resolution
- **Notification Channels**: Slack, PagerDuty, Email, etc.

**See also**: [alerting-architecture.md](./alerting-architecture.md) for detailed architecture documentation.

---

## 📝 Alert Rule Structure

Grafana alert rules consist of several key components:

### Basic Structure

```yaml
- uid: unique-alert-id                # Unique identifier for the alert
  title: Human-Readable Alert Title   # Displayed in Grafana UI
  condition: A                         # Which query result to evaluate (A, B, C, etc.)
  data:                                # Data source queries
    - refId: A                         # Reference ID for the query
      queryType: ''                    # Query type (empty for PromQL)
      relativeTimeRange:
        from: 300                      # Look back 5 minutes
        to: 0                          # Until now
      datasourceUid: PBFA97CFB590B2093 # Prometheus datasource UID
      model:
        expr: up{job="prometheus"} == 0  # PromQL query
        refId: A
  noDataState: OK                      # What to do if query returns no data
  execErrState: Alerting               # What to do if query execution fails
  for: 2m                              # Alert must be firing for this duration
  annotations:                         # Human-readable context
    description: 'Detailed description with variables: {{ $labels.pod }}'
    summary: Brief summary
    runbook_url: 'https://docs.example.com/runbooks/alert-name'
  labels:                              # Labels for routing and grouping
    severity: critical                 # Severity level (critical/warning/info)
    component: prometheus              # Component being monitored
    layer: observability               # Architecture layer
```

### Key Fields Explained

#### `noDataState`
What to do when the query returns no data:
- `OK`: Don't alert
- `Alerting`: Trigger alert
- `NoData`: Special "NoData" state

#### `execErrState`
What to do when the query execution fails:
- `OK`: Don't alert
- `Alerting`: Trigger alert
- `Error`: Special "Error" state

#### `for`
How long the condition must be true before firing:
- Short duration (10s-1m): Fast alerts for critical issues
- Medium duration (2m-5m): Standard alerts with some tolerance
- Long duration (10m+): Reduce noise for transient issues

---

## 🆕 Creating New Alert Rules

### Method 1: Grafana UI (Recommended for Development)

**Best for**: Quick testing, prototyping, one-off alerts

1. **Navigate to Alerting**:
   - Open Grafana: https://grafana.localtest.me:9443
   - Go to **Alerting** → **Alert rules**
   - Click **Create alert rule**

2. **Configure Query**:
   - Select **Prometheus** datasource
   - Enter PromQL query (e.g., `up{job="grafana"} == 0`)
   - Set time range and evaluation interval

3. **Set Condition**:
   - Choose which query result to evaluate (usually A)
   - Define threshold or condition

4. **Configure Alert Details**:
   - **Name**: Descriptive title
   - **Folder**: Kagenti (or create new folder)
   - **Group**: Group related alerts (e.g., "infrastructure_health")
   - **For**: How long condition must be true (e.g., 2m)

5. **Add Annotations**:
   - **Summary**: Brief description
   - **Description**: Detailed description with context
   - **Runbook URL**: Link to troubleshooting guide (optional)

6. **Add Labels**:
   - `severity`: critical/warning/info
   - `component`: Component name (e.g., prometheus, grafana, keycloak)
   - `layer`: infrastructure/platform/observability/application

7. **Save and Test**:
   - Click **Save rule and exit**
   - Monitor for firing state

8. **Export to YAML** (for provisioning):
   - Go to **Alert rules** → Click your rule → **Export**
   - Copy YAML to `components/02-observability/grafana/alert-rules-*.yaml`

### Method 2: Provisioning via YAML (Recommended for Production)

**Best for**: Version-controlled, reproducible, GitOps workflow

1. **Create or Edit Alert Rules File**:
   ```bash
   vim components/02-observability/grafana/alert-rules-custom.yaml
   ```

2. **Add Alert Rule**:
   ```yaml
   apiVersion: 1

   groups:
     - name: custom_alerts
       interval: 1m
       orgId: 1
       folder: Kagenti
       rules:
         - uid: my-new-alert
           title: My New Alert
           condition: A
           data:
             - refId: A
               queryType: ''
               relativeTimeRange:
                 from: 300
                 to: 0
               datasourceUid: PBFA97CFB590B2093  # Prometheus
               model:
                 expr: up{job="my-service"} == 0
                 refId: A
           noDataState: OK
           execErrState: Alerting
           for: 2m
           annotations:
             description: 'My service is down'
             summary: Service unavailable
           labels:
             severity: critical
             component: my-service
             layer: application
   ```

3. **Add to Alerting ConfigMap**:

   Edit `components/02-observability/grafana/alerting-provisioning.yaml`:

   ```yaml
   data:
     # ... existing files ...

     # Add new alert rules file
     alert-rules-custom.yaml: |
       # Paste your alert rules YAML here
   ```

4. **Commit and Deploy**:
   ```bash
   git add components/02-observability/grafana/
   git commit -m "feat(observability): Add custom alert rules"
   git push origin <branch>

   # Sync with ArgoCD
   argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

   # OR apply directly for fast testing
   kubectl apply -k components/02-observability/grafana/
   ```

### Method 3: Grafana API (Advanced)

**Best for**: Programmatic creation, automation, testing

```bash
# Create JSON file with alert rule
cat > /tmp/new-alert.json << 'EOF'
{
  "uid": "my-api-alert",
  "title": "My API Alert",
  "condition": "A",
  "data": [
    {
      "refId": "A",
      "queryType": "",
      "relativeTimeRange": {"from": 300, "to": 0},
      "datasourceUid": "PBFA97CFB590B2093",
      "model": {
        "expr": "up{job=\"my-service\"} == 0",
        "refId": "A"
      }
    }
  ],
  "noDataState": "OK",
  "execErrState": "Alerting",
  "for": "2m",
  "annotations": {
    "description": "Service is down",
    "summary": "My service unavailable"
  },
  "labels": {
    "severity": "warning",
    "component": "my-service"
  },
  "folderUID": "ff4at4vfmiv40c",  # Get from: GET /api/folders
  "ruleGroup": "custom_alerts"
}
EOF

# Copy to Grafana pod
kubectl cp /tmp/new-alert.json observability/$(kubectl get pod -n observability -l app=grafana -o jsonpath='{.items[0].metadata.name}'):/tmp/new-alert.json

# Create alert via API
kubectl exec -n observability deployment/grafana -- \
  curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin123 \
  http://localhost:3000/api/v1/provisioning/alert-rules \
  -d @/tmp/new-alert.json
```

---

## 🔧 Provisioning Methods

### Provisioning via ConfigMap (Recommended)

Alert rules are provisioned via the `grafana-alerting` ConfigMap:

```yaml
# components/02-observability/grafana/alerting-provisioning.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alerting
  namespace: observability
data:
  # Contact points (AlertManager integration)
  alertmanager.yaml: |
    # ... contact point configuration ...

  # Notification policies (routing rules)
  policies.yaml: |
    # ... routing configuration ...

  # Alert rules
  alert-rules-platform-health.yaml: |
    apiVersion: 1
    groups:
      - name: infrastructure_health
        # ... alert rules ...
```

**Grafana Deployment** mounts this ConfigMap:

```yaml
# components/02-observability/grafana/deployment.yaml
volumeMounts:
  - name: grafana-alerting
    mountPath: /etc/grafana/provisioning/alerting

volumes:
  - name: grafana-alerting
    configMap:
      name: grafana-alerting
```

**Changes to the ConfigMap** trigger automatic reload by Grafana (no restart required).

### File Structure

```
components/02-observability/grafana/
├── alerting-provisioning.yaml          # ConfigMap with all alerting config
├── alert-rules-platform-health.yaml    # Platform health alert rules
├── alert-rules-custom.yaml             # Your custom alert rules (if any)
└── sample-alert-rule.yaml              # Example/template file
```

---

## 🧪 Testing Alert Rules

### 1. Check Alert Rule Status

```bash
# List all alert rules
kubectl exec -n observability deployment/grafana -- \
  curl -s -u admin:admin123 \
  http://localhost:3000/api/v1/provisioning/alert-rules | \
  python3 -m json.tool

# Get specific alert rule
kubectl exec -n observability deployment/grafana -- \
  curl -s -u admin:admin123 \
  http://localhost:3000/api/v1/provisioning/alert-rules/<alert-uid> | \
  python3 -m json.tool
```

### 2. Check Alert State (Firing/Pending/OK)

```bash
# Check Grafana's internal alertmanager
kubectl exec -n observability deployment/grafana -- \
  curl -s -u admin:admin123 \
  "http://localhost:3000/api/alertmanager/grafana/api/v2/alerts" | \
  python3 -m json.tool
```

### 3. Manually Trigger Alert

Create a test alert that always fires:

```yaml
- uid: test-alert-always-firing
  title: Test Alert - Always Firing
  condition: A
  data:
    - refId: A
      queryType: ''
      relativeTimeRange:
        from: 60
        to: 0
      datasourceUid: PBFA97CFB590B2093
      model:
        expr: vector(1)  # Always returns 1 (true)
        refId: A
  noDataState: OK
  execErrState: OK
  for: 10s  # Fires after 10 seconds
  annotations:
    description: This is a test alert
    summary: Test alert
  labels:
    severity: warning
    test: "true"
```

### 4. Check AlertManager Received Alerts

```bash
# Check external AlertManager for alerts
kubectl exec -n observability -c alertmanager deployment/alertmanager -- \
  wget -qO- http://localhost:9093/api/v2/alerts | \
  python3 -m json.tool
```

### 5. Validate PromQL Query

Before creating an alert, test the PromQL query in Prometheus or Grafana:

```bash
# Test query in Prometheus
kubectl exec -n observability deployment/grafana -- \
  curl -s "http://prometheus.observability.svc:9090/api/v1/query?query=up%7Bjob%3D%22prometheus%22%7D" | \
  python3 -m json.tool
```

Or use Grafana **Explore** → Prometheus datasource → Enter query

---

## 🚨 Alert Severity Levels

Use consistent severity labels for proper routing:

| Severity | When to Use | Response Time | Notification | Example |
|----------|-------------|---------------|--------------|---------|
| **critical** | Service down, data loss, security breach | Immediate (< 5 min) | PagerDuty, Slack | Keycloak down, Node not ready |
| **warning** | Degraded performance, approaching limits | < 30 min | Slack, Email | High CPU (>80%), Pod restarts |
| **info** | Informational, non-urgent | Best effort | Email only | Certificate expires in 30 days |

### Severity-Based Routing

The notification policies route alerts based on severity:

```yaml
# components/02-observability/grafana/alerting-provisioning.yaml
policies:
  - receiver: alertmanager
    routes:
      # Critical alerts - fast notification
      - receiver: alertmanager
        matchers:
          - severity = critical
        group_wait: 10s
        repeat_interval: 4h

      # Warning alerts - standard notification
      - receiver: alertmanager
        matchers:
          - severity = warning
        group_wait: 30s
        repeat_interval: 12h
```

---

## ✅ Best Practices

### 1. Alert Naming

**Good**:
- `Pod High CPU Usage`
- `Prometheus Scrape Target Down`
- `Certificate Expiring Soon`

**Bad**:
- `Alert 1`
- `cpu`
- `ERROR!!!`

**Guidelines**:
- Use Title Case
- Be specific and descriptive
- Include the component being monitored
- Describe the problem, not the symptom

### 2. Query Design

**Use relative time ranges**:
```yaml
relativeTimeRange:
  from: 300   # 5 minutes ago
  to: 0       # now
```

**Don't hardcode timestamps** - alerts won't work after the timestamp passes.

**Avoid expensive queries**:
- Limit `rate()` and `increase()` to reasonable time windows (5m-15m)
- Use label filtering to reduce cardinality
- Test query performance before creating alert

**Example - Efficient Query**:
```promql
# Good: Filters by namespace and job
up{namespace="observability",job="prometheus"} == 0

# Bad: No filtering, high cardinality
up == 0
```

### 3. Alert Tuning

**Use `for` duration to reduce noise**:
```yaml
for: 2m  # Alert must fire for 2 minutes before notifying
```

**Choose appropriate evaluation intervals**:
```yaml
interval: 1m   # For critical services
interval: 5m   # For less critical metrics
```

**Handle NoData and Error states**:
```yaml
noDataState: OK          # Don't alert if metric doesn't exist yet
execErrState: Alerting   # Alert if query fails (critical services)
```

### 4. Annotations

**Use template variables** for dynamic context:
```yaml
annotations:
  description: 'Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is using {{ printf "%.0f" $values.A.Value }}% CPU'
  summary: Pod CPU usage exceeds 90%
  runbook_url: 'https://docs.kagenti.io/runbooks/high-cpu'
```

**Include runbook URLs** for common issues:
```yaml
annotations:
  runbook_url: 'https://docs.kagenti.io/runbooks/keycloak-down'
```

### 5. Labels

**Always include**:
- `severity`: critical/warning/info
- `component`: Component name (e.g., prometheus, keycloak)
- `layer`: Architecture layer (infrastructure/platform/observability/application)

**Optional but useful**:
- `team`: Responsible team
- `service`: Service name
- `environment`: Environment (dev/staging/prod)

**Example**:
```yaml
labels:
  severity: critical
  component: keycloak
  layer: platform
  team: platform-team
  service: authentication
```

### 6. Alert Groups

**Group related alerts together**:
```yaml
groups:
  - name: infrastructure_health     # All infrastructure alerts
  - name: platform_health          # All platform alerts
  - name: observability_health     # All observability alerts
  - name: application_health       # All application alerts
```

**Benefits**:
- Easier to manage
- Better organization
- Consistent evaluation intervals

---

## 🐛 Troubleshooting

### Alert Not Firing

**1. Check alert rule exists**:
```bash
kubectl exec -n observability deployment/grafana -- \
  curl -s -u admin:admin123 \
  http://localhost:3000/api/v1/provisioning/alert-rules | \
  grep -i "my-alert"
```

**2. Check query returns data**:
```bash
# Test PromQL query
kubectl exec -n observability deployment/grafana -- \
  curl -s "http://prometheus.observability.svc:9090/api/v1/query?query=<your-query>" | \
  python3 -m json.tool
```

**3. Check `for` duration**:
- Alert must be in firing state for `for` duration before triggering
- Reduce `for` duration for testing

**4. Check noDataState and execErrState**:
- If query returns no data, check `noDataState` is not set to `OK`
- If query fails, check `execErrState` is set to `Alerting`

### Alert Firing But Not Sent to AlertManager

**1. Check Grafana logs**:
```bash
kubectl logs -n observability deployment/grafana --tail=100 | grep -i alert
```

**2. Check AlertManager contact point**:
```bash
kubectl exec -n observability deployment/grafana -- \
  curl -s -u admin:admin123 \
  http://localhost:3000/api/v1/provisioning/contact-points | \
  python3 -m json.tool
```

**3. Check notification policies**:
```bash
kubectl exec -n observability deployment/grafana -- \
  curl -s -u admin:admin123 \
  http://localhost:3000/api/v1/provisioning/policies | \
  python3 -m json.tool
```

**4. Check AlertManager connectivity**:
```bash
# From Grafana pod
kubectl exec -n observability deployment/grafana -- \
  curl -v http://alertmanager.observability.svc:9093/api/v2/status

# From AlertManager pod (if sidecar issue)
kubectl exec -n observability -c alertmanager deployment/alertmanager -- \
  wget -qO- http://localhost:9093/api/v2/status
```

### Alert Configuration Not Loading

**1. Check ConfigMap exists**:
```bash
kubectl get configmap -n observability grafana-alerting -o yaml
```

**2. Check Grafana deployment mounts ConfigMap**:
```bash
kubectl get deployment -n observability grafana -o yaml | grep -A 5 "grafana-alerting"
```

**3. Check Grafana logs for provisioning errors**:
```bash
kubectl logs -n observability deployment/grafana | grep -i provisioning
```

**4. Restart Grafana to force reload**:
```bash
kubectl rollout restart deployment/grafana -n observability
kubectl rollout status deployment/grafana -n observability
```

### PromQL Query Errors

**Common issues**:
- **Syntax error**: Check PromQL syntax in Prometheus or Grafana Explore
- **No data**: Metric doesn't exist or label selectors are wrong
- **Cardinality too high**: Query returns too many time series

**Test queries**:
```bash
# In Grafana Explore
1. Go to Explore → Prometheus datasource
2. Enter your PromQL query
3. Check results and errors

# Or via API
kubectl exec -n observability deployment/grafana -- \
  curl -s "http://prometheus.observability.svc:9090/api/v1/query?query=<encoded-query>"
```

---

## 📚 Examples

### Example 1: Simple Service Down Alert

```yaml
- uid: keycloak-down
  title: Keycloak Authentication Service Down
  condition: A
  data:
    - refId: A
      queryType: ''
      relativeTimeRange:
        from: 180
        to: 0
      datasourceUid: PBFA97CFB590B2093
      model:
        expr: kube_deployment_status_replicas_available{namespace="keycloak",deployment="keycloak"} == 0
        refId: A
  noDataState: Alerting
  execErrState: Alerting
  for: 2m
  annotations:
    description: 'Keycloak authentication service is down. User authentication will fail.'
    summary: Keycloak has no available replicas
  labels:
    severity: critical
    component: keycloak
    layer: platform
```

### Example 2: Threshold Alert with Variable

```yaml
- uid: pod-high-cpu-usage
  title: Pod High CPU Usage
  condition: A
  data:
    - refId: A
      queryType: ''
      relativeTimeRange:
        from: 300
        to: 0
      datasourceUid: PBFA97CFB590B2093
      model:
        expr: |
          sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace, pod, container)
          / sum(container_spec_cpu_quota{container!="",container!="POD"} / container_spec_cpu_period{container!="",container!="POD"}) by (namespace, pod, container) * 100 > 90
        refId: A
  noDataState: OK
  execErrState: OK
  for: 5m
  annotations:
    description: 'Pod {{ $labels.pod }} container {{ $labels.container }} in namespace {{ $labels.namespace }} is using {{ printf "%.0f" $values.A.Value }}% CPU'
    summary: Pod CPU usage exceeds 90%
  labels:
    severity: warning
    component: application
    layer: application
```

### Example 3: Multi-Query Alert (Compare Two Metrics)

```yaml
- uid: high-error-rate
  title: High HTTP Error Rate
  condition: C
  data:
    # Query A: Total requests
    - refId: A
      queryType: ''
      relativeTimeRange:
        from: 300
        to: 0
      datasourceUid: PBFA97CFB590B2093
      model:
        expr: sum(rate(http_requests_total[5m]))
        refId: A

    # Query B: Error requests (5xx)
    - refId: B
      queryType: ''
      relativeTimeRange:
        from: 300
        to: 0
      datasourceUid: PBFA97CFB590B2093
      model:
        expr: sum(rate(http_requests_total{status=~"5.."}[5m]))
        refId: B

    # Query C: Error rate percentage
    - refId: C
      queryType: ''
      datasourceUid: __expr__
      model:
        type: math
        expression: (B / A) * 100 > 5  # > 5% error rate
        refId: C
  noDataState: OK
  execErrState: OK
  for: 2m
  annotations:
    description: 'HTTP error rate is {{ printf "%.2f" $values.C.Value }}%'
    summary: Elevated HTTP 5xx error rate
  labels:
    severity: warning
    component: api-gateway
```

### Example 4: Absence Alert (Metric Missing)

```yaml
- uid: prometheus-not-scraping-cadvisor
  title: Prometheus Not Scraping cAdvisor
  condition: A
  data:
    - refId: A
      queryType: ''
      relativeTimeRange:
        from: 600
        to: 0
      datasourceUid: PBFA97CFB590B2093
      model:
        expr: absent(up{job="kubernetes-cadvisor"})
        refId: A
  noDataState: OK
  execErrState: OK
  for: 5m
  annotations:
    description: 'Prometheus is not scraping cAdvisor metrics. Container metrics will be unavailable.'
    summary: cAdvisor scrape target is missing
  labels:
    severity: critical
    component: prometheus
    layer: observability
```

---

## 📖 Additional Resources

- **Grafana Alerting Docs**: https://grafana.com/docs/grafana/latest/alerting/
- **PromQL Syntax**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **AlertManager Configuration**: https://prometheus.io/docs/alerting/latest/configuration/
- **Kagenti Alerting Architecture**: [alerting-architecture.md](./alerting-architecture.md)
- **Kagenti Implementation Summary**: [IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md)

---

## 🚀 Quick Start Checklist

- [ ] Understand the alerting architecture
- [ ] Review existing alert rules in `alert-rules-platform-health.yaml`
- [ ] Test PromQL query in Grafana Explore or Prometheus
- [ ] Create alert rule (UI or YAML)
- [ ] Set appropriate `for` duration to reduce noise
- [ ] Add descriptive annotations with variables
- [ ] Set correct severity label (critical/warning/info)
- [ ] Test alert fires correctly
- [ ] Verify alert sent to AlertManager (if applicable)
- [ ] Commit to Git (if using provisioning)
- [ ] Monitor for false positives and tune as needed

---

**Status**: ✅ **Ready for Use**

🤖 Generated with [Claude Code](https://claude.com/claude-code)
