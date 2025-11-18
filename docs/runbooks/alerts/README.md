# Alert Runbooks

**Last Updated**: 2025-11-16
**Total Alerts**: 24 (9 critical, 15 warning)

---

## Overview

This directory contains standardized runbooks for all Kagenti platform alerts. Each runbook follows the prometheus-operator format and includes:

- **Meaning**: What the alert means and when it fires
- **Impact**: User impact, system impact, and blast radius
- **Diagnosis**: Step-by-step investigation procedures
- **Mitigation**: Immediate actions and root cause resolution
- **Related Information**: Related alerts, dashboards, and upstream documentation

---

## Alert Index

### 🔴 Critical Alerts (9)

Alerts that indicate severe service degradation or outages requiring immediate attention.

#### Infrastructure Layer (3)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **Istio Control Plane Down** | `istiod-down` | Istio control plane (istiod) is not responding | [istiod-down.md](./istiod-down.md) |
| **Istio Gateway Unhealthy** | `gateway-unhealthy` | Gateway has no available replicas (complete outage) | [gateway-unhealthy.md](./gateway-unhealthy.md) |
| **Kubernetes Node Not Ready** | `kubernetes-node-not-ready` | Node is in NotReady state | [kubernetes-node-not-ready.md](./kubernetes-node-not-ready.md) |

#### Platform Layer (4)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **Keycloak Authentication Service Down** | `keycloak-down` | Keycloak has no available replicas (auth outage) | [keycloak-down.md](./keycloak-down.md) |
| **Tekton Pipelines Controller Down** | `tekton-controller-down` | Tekton controller unavailable (CI/CD blocked) | [tekton-controller-down.md](./tekton-controller-down.md) |
| **Kagenti Operator Down** | `kagenti-operator-down` | Kagenti operator unavailable (agent management blocked) | [kagenti-operator-down.md](./kagenti-operator-down.md) |

#### Observability Layer (2)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **Prometheus Metrics Service Down** | `prometheus-down` | Prometheus unavailable (alerting stops) | [prometheus-down.md](./prometheus-down.md) |
| **AlertManager Service Down** | `alertmanager-down` | AlertManager unavailable (notifications blocked) | [alertmanager-down.md](./alertmanager-down.md) |

#### Application Layer (1)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **Pod in CrashLoopBackOff** | `pod-crashloop-backoff` | Pod repeatedly crashing | [pod-crashloop-backoff.md](./pod-crashloop-backoff.md) |

---

### ⚠️ Warning Alerts (15)

Alerts indicating degraded performance or non-critical service issues.

#### Infrastructure Layer (3)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **TLS Certificate Expiring Soon** | `certificate-expiring-soon` | Certificate expires in <14 days | [certificate-expiring-soon.md](./certificate-expiring-soon.md) |
| **Node CPU Pressure** | `node-cpu-pressure` | Node experiencing CPU resource pressure | [node-cpu-pressure.md](./node-cpu-pressure.md) |
| **Node Memory Pressure** | `node-memory-pressure` | Node experiencing memory pressure | [node-memory-pressure.md](./node-memory-pressure.md) |

#### Platform Layer (1)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **OAuth2-Proxy Service Down** | `oauth2-proxy-down` | OAuth2-Proxy deployment unavailable | [oauth2-proxy-down.md](./oauth2-proxy-down.md) |

#### Observability Layer (6)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **Grafana Dashboard Service Down** | `grafana-down` | Grafana unavailable (dashboards inaccessible) | [grafana-down.md](./grafana-down.md) |
| **Tempo Tracing Service Down** | `tempo-down` | Tempo unavailable (trace collection stopped) | [tempo-down.md](./tempo-down.md) |
| **Loki Log Aggregation Service Down** | `loki-down` | Loki unavailable (log collection stopped) | [loki-down.md](./loki-down.md) |
| **Phoenix LLM Observability Down** | `phoenix-down` | Phoenix unavailable (LLM tracing stopped) | [phoenix-down.md](./phoenix-down.md) |
| **Promtail Log Collection Degraded** | `promtail-pods-down` | <80% of Promtail pods running | [promtail-pods-down.md](./promtail-pods-down.md) |
| **Prometheus Scrape Target Down** | `prometheus-target-down` | Prometheus cannot scrape a target | [prometheus-target-down.md](./prometheus-target-down.md) |
| **Prometheus High Scrape Failure Rate** | `prometheus-high-scrape-failure` | High scrape failure rate detected | [prometheus-high-scrape-failure.md](./prometheus-high-scrape-failure.md) |

#### Application Layer (5)

| Alert | UID | Description | Runbook |
|-------|-----|-------------|---------|
| **Pod High CPU Usage** | `pod-high-cpu-usage` | Pod using >90% CPU quota | [pod-high-cpu-usage.md](./pod-high-cpu-usage.md) |
| **Pod High Memory Usage** | `pod-high-memory-usage` | Pod using >90% memory limit | [pod-high-memory-usage.md](./pod-high-memory-usage.md) |
| **Pod Restarting Frequently** | `pod-frequent-restarts` | Pod restarted >3 times in 15m | [pod-frequent-restarts.md](./pod-frequent-restarts.md) |
| **PersistentVolumeClaim High Usage** | `pvc-high-usage` | PVC >85% full | [pvc-high-usage.md](./pvc-high-usage.md) |

---

## Severity Guidelines

### Critical (9 alerts)

**When to use**: Service unavailability that blocks core functionality

**Examples**:
- Complete authentication outage (Keycloak down)
- All external access blocked (Gateway down)
- Alerting system stopped (Prometheus down)
- Service mesh control plane failure (Istiod down)

**Response Time**: Immediate (P0 incident)

---

### Warning (15 alerts)

**When to use**: Degraded performance or non-critical service issues

**Examples**:
- Dashboard unavailable (Grafana down) - metrics collection continues
- Certificate expiring soon (14 days) - proactive alert
- High resource usage (CPU/memory >90%) - performance degradation
- Log collection degraded (Promtail pods down) - partial outage

**Response Time**: Within 1 hour

---

## Using These Runbooks

### During an Incident

1. **Identify the firing alert**:
   ```bash
   # Check currently firing alerts
   kubectl exec -n observability deployment/grafana -- \
     curl -s 'http://localhost:3000/api/alertmanager/grafana/api/v2/alerts' \
     -u admin:admin123 | python3 -c "
   import sys, json
   alerts = json.load(sys.stdin)
   firing = [a for a in alerts if a.get('status', {}).get('state') == 'active']
   for alert in firing:
       labels = alert.get('labels', {})
       print(f\"• {labels.get('alertname')} ({labels.get('severity')})\")
   "
   ```

2. **Open the corresponding runbook** from the index above

3. **Follow the Diagnosis section** to investigate

4. **Execute Mitigation steps** as appropriate

5. **Verify resolution**:
   ```bash
   # Wait for alert to resolve
   watch -n 10 "kubectl exec -n observability deployment/grafana -- curl -s 'http://localhost:3000/api/alertmanager/grafana/api/v2/alerts' -u admin:admin123 | python3 -c 'import sys,json; print(len([a for a in json.load(sys.stdin) if a.get(\"status\",{}).get(\"state\")==\"active\"]))'"
   ```

### Before Deployment

Use runbooks to understand alert behavior:

```bash
# Test alert query with mock data
pytest tests/integration/test_alert_queries.py::TestAlertQueriesWithMockData::test_<alert>_query_logic -v

# Validate alert against real Prometheus
pytest tests/integration/test_alert_queries.py::TestAlertQueriesAgainstRealPrometheus -v
```

---

## Alert Configuration

All alerts are configured in:
```
components/02-observability/grafana/alerting-provisioning.yaml
```

**GitOps Workflow for Alert Changes**:

1. Edit alert configuration:
   ```bash
   vim components/02-observability/grafana/alerting-provisioning.yaml
   ```

2. Validate YAML syntax:
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('components/02-observability/grafana/alerting-provisioning.yaml'))"
   ```

3. Test alert query:
   ```bash
   kubectl exec -n observability deployment/grafana -- \
     curl -s -G 'http://prometheus.observability.svc:9090/api/v1/query' \
     --data-urlencode 'query=<YOUR_PROMQL_QUERY>'
   ```

4. Commit changes:
   ```bash
   git add components/02-observability/
   git commit -m "Update alert: <description>"
   git push
   ```

5. Apply via ArgoCD:
   ```bash
   argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web
   ```

6. Verify alert loaded:
   ```bash
   kubectl exec -n observability deployment/grafana -- \
     curl -s 'http://localhost:3000/api/v1/provisioning/alert-rules' \
     -u admin:admin123 | grep <alert-uid>
   ```

---

## Related Documentation

- [Alert Testing Guide](../../04-observability/ALERT_TESTING_GUIDE.md) - TDD approach for alerts
- [Alert Fix Summary](../../04-observability/ALERT_FIX_SUMMARY.md) - Common alert issues and fixes
- [Adding New Alerts](../../04-observability/ADDING_NEW_ALERTS.md) - How to create new alerts
- [Alert Monitoring](../../../CLAUDE.md#alert-monitoring) - Day-to-day alert management
- [Runbook Template](./TEMPLATE.md) - Template for creating new runbooks

---

## Contributing

When adding a new alert, ensure you:

1. ✅ Create a runbook using the [TEMPLATE.md](./TEMPLATE.md)
2. ✅ Add tests in `tests/integration/test_alert_queries.py`
3. ✅ Update this README index
4. ✅ Add `runbook_url` annotation pointing to the runbook
5. ✅ Follow prometheus-operator runbook format

---

**Maintained by**: Kagenti Platform Team
**Format Standard**: [prometheus-operator runbooks](https://runbooks.prometheus-operator.dev/)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
