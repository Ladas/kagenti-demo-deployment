# Alerting Architecture: Grafana + AlertManager + Korrel8r

**Status**: Implementation In Progress
**Last Updated**: 2025-11-16

---

## 🎯 Overview

This document describes the integrated alerting architecture that combines:
- **Grafana Alerting** - Alert definition and evaluation
- **AlertManager** - Alert aggregation, routing, and notification
- **Korrel8r** - Signal correlation (alert ↔ trace ↔ log ↔ metric)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GRAFANA ALERTING                          │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Alert Rules (defined in Grafana)                            │ │
│  │  • Metrics-based alerts (from Prometheus)                   │ │
│  │  • Log-based alerts (from Loki)                             │ │
│  │  • Trace-based alerts (from Tempo)                          │ │
│  └──────────────────────────┬───────────────────────────────────┘ │
│                             │                                     │
│                             ▼                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Alert Evaluation Engine                                     │ │
│  │  • Evaluates rules against datasources                      │ │
│  │  • Triggers alerts when conditions met                      │ │
│  │  • Enriches alerts with metadata                            │ │
│  └──────────────────────────┬───────────────────────────────────┘ │
└─────────────────────────────┼───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         ALERTMANAGER                             │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Alert Receiver (from Grafana)                               │ │
│  │  • Receives alerts via webhook                              │ │
│  │  • Parses alert payload                                     │ │
│  └──────────────────────────┬───────────────────────────────────┘ │
│                             │                                     │
│                             ▼                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Alert Processing Pipeline                                   │ │
│  │  • Grouping - Group similar alerts                          │ │
│  │  • Deduplication - Remove duplicate alerts                  │ │
│  │  • Silencing - Honor silence rules                          │ │
│  │  • Inhibition - Suppress dependent alerts                   │ │
│  └──────────────────────────┬───────────────────────────────────┘ │
│                             │                                     │
│                             ▼                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Routing Tree                                                │ │
│  │  • Route alerts based on labels                             │ │
│  │  • Multiple receivers per route                             │ │
│  └──────────┬─────────────────────────┬────────────────────────┘ │
└─────────────┼─────────────────────────┼─────────────────────────┘
              │                         │
              ▼                         ▼
┌─────────────────────────┐   ┌─────────────────────────────────┐
│  Notification Channels  │   │          KORREL8R               │
│  • Slack                │   │  ┌───────────────────────────┐  │
│  • Email                │   │  │ Alert Correlation Engine  │  │
│  • PagerDuty            │   │  │  • Receives alert event   │  │
│  • Webhook              │   │  │  • Extracts metadata      │  │
│  • ...                  │   │  │  • Finds related signals: │  │
│                         │   │  │    - Traces (via trace_id)│  │
└─────────────────────────┘   │  │    - Logs (via labels)    │  │
                              │  │    - Metrics (via query)  │  │
                              │  │  • Stores correlation     │  │
                              │  └────────────┬──────────────┘  │
                              │               │                 │
                              └───────────────┼─────────────────┘
                                              │
                                              ▼
                              ┌───────────────────────────────┐
                              │      GRAFANA UI               │
                              │  • Query Korrel8r API         │
                              │  • Display correlated signals │
                              │  • Jump to traces/logs        │
                              │  • Enhanced debugging context │
                              └───────────────────────────────┘
```

---

## 🔄 Alert Flow

### 1. Alert Definition (Grafana)

```yaml
# Example: High CPU alert
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alert-rules
data:
  alerts.yaml: |
    groups:
      - name: kubernetes_resources
        interval: 30s
        rules:
          - alert: HighCPUUsage
            expr: |
              sum(rate(container_cpu_usage_seconds_total{container!=""}[5m]))
              / sum(machine_cpu_cores) * 100 > 80
            for: 5m
            labels:
              severity: warning
              component: kubernetes
            annotations:
              summary: "High CPU usage detected"
              description: "CPU usage is {{ $value }}% (threshold: 80%)"
              runbook_url: "https://docs.example.com/runbooks/high-cpu"
```

### 2. Alert Evaluation (Grafana Alerting Engine)

- Grafana evaluates rule every 30s
- If condition is true for 5m → trigger alert
- Alert sent to AlertManager via webhook

### 3. Alert Processing (AlertManager)

```yaml
# AlertManager configuration
route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
      continue: true  # Also send to korrel8r

    - match:
        severity: warning
      receiver: 'slack'
      continue: true

    - match_re:
        severity: .+
      receiver: 'korrel8r'  # All alerts go to Korrel8r

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://slack-webhook.example.com/hook'

  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<key>'

  - name: 'slack'
    slack_configs:
      - api_url: '<webhook-url>'
        channel: '#alerts'

  - name: 'korrel8r'
    webhook_configs:
      - url: 'http://korrel8r.observability.svc:8080/api/v1/alerts'
        send_resolved: true
```

### 4. Signal Correlation (Korrel8r)

When Korrel8r receives an alert:

```json
{
  "status": "firing",
  "labels": {
    "alertname": "HighCPUUsage",
    "severity": "warning",
    "namespace": "observability",
    "pod": "grafana-abc123"
  },
  "annotations": {
    "summary": "High CPU usage detected",
    "trace_id": "abc123...",
    "request_id": "xyz789..."
  },
  "startsAt": "2025-11-16T10:00:00Z"
}
```

Korrel8r:
1. **Extracts correlation keys**: trace_id, request_id, namespace, pod
2. **Queries related signals**:
   - **Traces**: `GET /traces?trace_id=abc123...`
   - **Logs**: `GET /loki/api/v1/query_range?query={namespace="observability",pod="grafana-abc123"}`
   - **Metrics**: `GET /prometheus/api/v1/query?query=container_cpu_usage{pod="grafana-abc123"}`
3. **Stores correlations**: Alert ID → [Trace IDs, Log queries, Metric queries]
4. **Provides API**: Grafana can query `GET /korrel8r/api/v1/correlations?alert_id=...`

### 5. Enhanced UI (Grafana + Korrel8r)

Grafana dashboard shows:
```
🚨 ALERT: HighCPUUsage (FIRING since 10:00)
   Pod: grafana-abc123
   CPU: 85% (threshold: 80%)

   📊 Related Signals (via Korrel8r):
   • 🔍 Traces: 15 traces found [View in Tempo →]
   • 📝 Logs: 2,341 log lines [View in Loki →]
   • 📈 Metrics: CPU spike correlates with:
     - Memory increase (82% → 91%)
     - Request rate spike (150 req/s → 800 req/s)
     - Slow query detected (5s avg latency)
```

---

## 🎯 Benefits

### Why Use This Architecture?

| Component | Purpose | Benefits |
|-----------|---------|----------|
| **Grafana Alerting** | Alert definition | • Unified UI for dashboards + alerts<br>• Query builder for metrics/logs/traces<br>• Version control for alert rules |
| **AlertManager** | Alert routing & aggregation | • Powerful routing based on labels<br>• Deduplication & grouping<br>• Silencing & inhibition<br>• Multiple notification channels |
| **Korrel8r** | Signal correlation | • Automatic trace/log/metric linking<br>• Faster root cause analysis<br>• Reduced MTTR (Mean Time To Resolution)<br>• Enhanced debugging context |

### vs. Grafana Alerting Only

**Without AlertManager + Korrel8r:**
- ❌ No alert grouping/deduplication
- ❌ No advanced routing
- ❌ Limited notification channels
- ❌ Manual correlation of signals
- ❌ Slower debugging

**With AlertManager + Korrel8r:**
- ✅ Smart alert aggregation
- ✅ Flexible routing to multiple channels
- ✅ Automatic signal correlation
- ✅ Faster incident resolution
- ✅ Better operational visibility

---

## 📋 Implementation Checklist

### Phase 1: AlertManager Deployment
- [ ] Create AlertManager deployment manifests
- [ ] Configure AlertManager with routes
- [ ] Add NetworkPolicy for AlertManager
- [ ] Configure mTLS (PERMISSIVE mode)
- [ ] Write pytest tests for AlertManager

### Phase 2: Grafana Integration
- [ ] Configure Grafana to send alerts to AlertManager
- [ ] Create sample alert rules
- [ ] Test alert evaluation and routing

### Phase 3: Korrel8r Integration
- [ ] Fix Korrel8r CrashLoopBackOff (see TODO_TRACING.md)
- [ ] Configure AlertManager → Korrel8r webhook
- [ ] Implement correlation API endpoints
- [ ] Test alert → signal correlation

### Phase 4: Testing & Documentation
- [ ] Write integration tests for full flow
- [ ] Create runbooks for common alerts
- [ ] Document alert routing configuration
- [ ] Add Grafana dashboard with correlation UI

---

## 🧪 Testing Strategy

### Unit Tests
- AlertManager config validation
- Route matching logic
- Korrel8r correlation logic

### Integration Tests
```python
def test_alert_flow_end_to_end():
    """Test complete alert flow: trigger → route → correlate."""
    # 1. Trigger alert condition in Prometheus
    # 2. Wait for Grafana to evaluate and fire
    # 3. Verify AlertManager receives alert
    # 4. Verify Korrel8r receives and correlates
    # 5. Verify Grafana can query correlated signals
```

### Performance Tests
- Alert processing latency
- Correlation query performance
- AlertManager throughput

---

## 🔒 Security Considerations

### mTLS Configuration
- AlertManager: **PERMISSIVE** mode (receives alerts from Grafana via HTTP)
- Korrel8r: **PERMISSIVE** mode (receives webhooks from AlertManager)
- All external APIs: OAuth2-Proxy authentication

### Network Policies
```yaml
# Allow Grafana → AlertManager
# Allow AlertManager → Korrel8r
# Allow AlertManager → external webhooks (Slack, etc.)
# Deny all other traffic
```

---

## 📊 Metrics & Monitoring

### AlertManager Metrics
- `alertmanager_alerts_received_total` - Total alerts received
- `alertmanager_alerts_invalid_total` - Invalid alerts
- `alertmanager_notifications_total` - Notifications sent
- `alertmanager_notification_latency_seconds` - Notification latency

### Korrel8r Metrics
- `korrel8r_alerts_correlated_total` - Alerts successfully correlated
- `korrel8r_correlation_duration_seconds` - Time to correlate signals
- `korrel8r_api_requests_total` - API requests

---

## 📚 References

- [AlertManager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)
- [Korrel8r](https://github.com/korrel8r/korrel8r)
- [TODO_TRACING.md](../../TODO_TRACING.md) - Korrel8r implementation status

---

**Next Steps**: Implement AlertManager deployment manifests with TDD approach.
