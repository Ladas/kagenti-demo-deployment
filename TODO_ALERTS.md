# Alert Development TODO

**Created**: 2025-11-16
**Approach**: Test-Driven Development (TDD) for Alert Rules
**Goal**: Production-ready, tested, documented alerts with SOPs

---

## 🎯 Current Status

**Alerts Deployed**: 24 platform health alerts
**Alerts Firing**: 7 (need investigation)
**Test Coverage**: 27 integration tests passing
**Documentation**: Alert creation guide complete

---

## 🔥 Currently Firing Alerts (PRIORITY)

### Critical Alerts:
1. **AlertManager Service Down** ⚠️ FALSE POSITIVE
   - Issue: Istio sidecar not ready (known infrastructure issue)
   - Metric shows: 0 available replicas
   - Reality: Main container is healthy
   - Action: Update alert to check main container OR document as expected during sidecar issues

2. **Keycloak Authentication Service Down** ❓ INVESTIGATE
   - Need to verify: Is Keycloak actually down or false positive?
   - Check: Pod status, replica count, metrics

3. **Istio Gateway Unhealthy** ❓ INVESTIGATE
   - Check: Which gateway? What's the actual status?

4. **Prometheus Metrics Service Down** ⚠️ FALSE POSITIVE
   - We know Prometheus is running (tests pass)
   - Issue: Alert query might be wrong

### Warning Alerts:
5. **Grafana Dashboard Service Down** ⚠️ FALSE POSITIVE
   - Metric shows: 1 available replica
   - Alert firing anyway - query issue

6. **Loki Log Aggregation Service Down** ⚠️ FALSE POSITIVE
   - Metric shows: 1 available replica
   - Alert firing anyway - query issue

7. **Tempo Tracing Service Down** ⚠️ FALSE POSITIVE
   - Metric shows: 1 available replica
   - Alert firing anyway - query issue

---

## 📋 TODO List

### Phase 1: Fix Currently Firing Alerts (IMMEDIATE)

- [ ] **Investigate alert queries causing false positives**
  - [ ] Review PromQL queries for Grafana/Loki/Tempo/Prometheus
  - [ ] Test queries against actual metrics
  - [ ] Identify root cause of false firings

- [ ] **Fix AlertManager alert**
  - [ ] Update to check container readiness instead of deployment available replicas
  - [ ] Or: Document as expected state during Istio issues
  - [ ] Write test to verify alert logic

- [ ] **Investigate and fix Keycloak alert**
  - [ ] Check actual Keycloak deployment status
  - [ ] Verify PromQL query
  - [ ] Write test with mock data

- [ ] **Investigate and fix Gateway alert**
  - [ ] Identify which gateway is triggering
  - [ ] Verify query correctness
  - [ ] Write test

- [ ] **Fix service down alerts (Grafana/Loki/Tempo/Prometheus)**
  - [ ] Root cause why alerts fire despite replicas being available
  - [ ] Fix PromQL queries
  - [ ] Add tests to prevent regression

### Phase 2: Alert Testing with Mock Data (TDD)

- [ ] **Create alert testing framework**
  - [ ] Research PromQL query testing best practices
  - [ ] Create test data generator for Prometheus metrics
  - [ ] Build test harness for alert evaluation

- [ ] **Test each alert with mock datasets**
  - [ ] Infrastructure alerts (7)
  - [ ] Platform alerts (4)
  - [ ] Observability alerts (9)
  - [ ] Application alerts (4)

- [ ] **Validate alert thresholds**
  - [ ] CPU/memory thresholds (90% - is this right?)
  - [ ] Restart count thresholds (3 in 15m - is this right?)
  - [ ] Time windows (for durations - are they optimal?)

### Phase 3: Alert SOP Documentation

- [ ] **Research SOP/Runbook formats**
  - [ ] GitOps alert runbook standards
  - [ ] Prometheus/AlertManager best practices
  - [ ] Industry standards (SRE, incident response)

- [ ] **Create SOP template**
  - [ ] Standardized format for all alerts
  - [ ] Required sections (symptoms, impact, diagnosis, remediation)
  - [ ] GitOps-friendly structure

- [ ] **Document SOPs for all 24 alerts**
  - [ ] Critical alerts first (9 alerts)
  - [ ] Warning alerts (15 alerts)
  - [ ] Include: troubleshooting steps, resolution procedures, escalation

- [ ] **Create runbook structure**
  - [ ] docs/runbooks/alerts/ directory
  - [ ] One file per alert or grouped by component?
  - [ ] Link from alert annotations

### Phase 4: Enhanced Alert Coverage

- [ ] **Analyze gaps in current alert coverage**
  - [ ] Are all critical services covered?
  - [ ] Missing metrics? (disk, network, etc.)
  - [ ] Edge cases not covered?

- [ ] **Add missing alerts**
  - [ ] Disk space/IO
  - [ ] Network connectivity
  - [ ] Certificate renewal failures
  - [ ] Backup/persistence issues
  - [ ] Security events

- [ ] **Add business/SLA alerts**
  - [ ] Request latency
  - [ ] Error rates
  - [ ] Availability metrics
  - [ ] User-facing SLOs

### Phase 5: Alert Monitoring & Tuning

- [ ] **Extend CLAUDE.md with alert monitoring procedures**
  - [ ] How to check currently firing alerts
  - [ ] How to silence alerts
  - [ ] How to modify alert thresholds
  - [ ] How to add new alerts

- [ ] **Create alert dashboard**
  - [ ] Grafana dashboard showing alert status
  - [ ] Alert fire rate over time
  - [ ] Top firing alerts
  - [ ] False positive tracking

- [ ] **Implement alert tuning process**
  - [ ] Track false positive rate
  - [ ] Adjust thresholds based on real data
  - [ ] Document tuning decisions

### Phase 6: Advanced Features

- [ ] **Add alert annotations with correlation**
  - [ ] Link to relevant logs (Loki)
  - [ ] Link to traces (Tempo)
  - [ ] Link to metrics (Prometheus/Grafana)

- [ ] **Implement alert grouping/dependencies**
  - [ ] Inhibit dependent alerts
  - [ ] Root cause analysis hints
  - [ ] Alert correlation

- [ ] **Add notification channels**
  - [ ] Slack integration
  - [ ] PagerDuty integration
  - [ ] Email notifications
  - [ ] Webhook for custom integrations

---

## 🧪 TDD Workflow for Alerts

### For Each Alert:

1. **Write Test First**
   ```python
   def test_alert_fires_when_service_down():
       """Test that alert fires when deployment has 0 replicas."""
       # Create mock Prometheus data
       mock_data = {
           "kube_deployment_status_replicas_available{deployment='grafana'}": 0
       }

       # Evaluate alert query
       result = evaluate_alert_query(GRAFANA_DOWN_QUERY, mock_data)

       # Assert alert fires
       assert result == True, "Alert should fire when replicas = 0"
   ```

2. **Verify Alert Query**
   - Test against actual Prometheus
   - Verify it returns expected results
   - Check for false positives

3. **Implement/Fix Alert**
   - Update PromQL query if needed
   - Adjust thresholds
   - Add proper labels and annotations

4. **Verify Test Passes**
   - Run test with real Prometheus data
   - Run test with mock data
   - Verify no false positives

5. **Document SOP**
   - Write runbook
   - Add troubleshooting steps
   - Link from alert annotations

6. **Commit**
   - Git commit alert + test + documentation together
   - Atomic changes

---

## 📊 Alert Metrics to Track

- **False Positive Rate**: Target < 5%
- **Mean Time to Detect (MTTD)**: Target < 5 minutes
- **Mean Time to Resolve (MTTR)**: Target < 30 minutes
- **Alert Fatigue**: Track silenced/ignored alerts
- **Coverage**: % of critical services with alerts

---

## 📚 Research Topics

- [ ] GitOps alert SOP standards
- [ ] Prometheus alert testing frameworks (promtool, etc.)
- [ ] Alert runbook best practices (Google SRE, etc.)
- [ ] PromQL mock data generation
- [ ] Alert correlation patterns
- [ ] False positive reduction techniques

---

## 🔗 Related Documentation

- [ADDING_NEW_ALERTS.md](./docs/04-observability/ADDING_NEW_ALERTS.md) - How to add alerts
- [alerting-architecture.md](./docs/04-observability/alerting-architecture.md) - Alerting design
- [IMPLEMENTATION_SUMMARY.md](./docs/04-observability/IMPLEMENTATION_SUMMARY.md) - What was built
- CLAUDE.md - Development workflow (to be extended)

---

## ✅ Completed

- [x] Create 24 platform health alerts
- [x] Configure Grafana → AlertManager integration
- [x] Write 27 integration tests
- [x] Document alert creation process
- [x] Provision alerts in Grafana

---

**Status**: 🚧 **IN PROGRESS**
**Next Action**: Investigate and fix currently firing false positive alerts

🤖 Generated with [Claude Code](https://claude.com/claude-code)
