# Monitoring Agents System - Implementation Plan

## Overview
Build an intelligent monitoring system using AI agents that:
- Query Prometheus metrics, distributed traces (Phoenix/Tempo), logs (Loki), and correlation data (Korrel8r)
- Correlate observability data to identify issues and perform root cause analysis
- Automatically create PRs for infrastructure and application issues
- Deploy via GitOps with automatic infrastructure connection using Kagenti AgentBuild CRD

**GitOps Repository**: `kagenti-demo-deployment`
- All monitoring agent deployments will be added to the kagenti-demo-deployment repository
- Infrastructure changes will be proposed via PRs to kagenti-demo-deployment
- Follows the existing component structure: `components/03-applications/agents/monitoring/`

**Research Documents**:
- [Phoenix Configuration Research](./RESEARCH_Phoenix_Configuration.md) - Comprehensive analysis of Phoenix/Arize deployment and configuration
- [Authentication Architecture](./AUTHENTICATION_ARCHITECTURE.md) - Complete auth strategy (Keycloak + mTLS)
- [Critical Review](./CRITICAL_REVIEW_TODO.md) - Issues found and recommendations
- [Verification Phoenix vs Jaeger](./VERIFICATION_Phoenix_vs_Jaeger.md) - Proof of Phoenix independence
- [Next Steps Complete](./NEXT_STEPS_COMPLETE.md) - Comprehensive implementation guide
- [CLAUDE.md](./CLAUDE.md) - GitOps workflow and platform practices

---

## Phase 0: Current Infrastructure Assessment

**CRITICAL DISCOVERY**: Most observability infrastructure is already deployed! ✅

### 0.1 Deployed Components (Verified)

#### Observability Stack (components/02-observability/)
- ✅ **Prometheus** - `prometheus.observability.svc:9090`
  - Metrics collection and storage
  - ServiceMonitor-based discovery
  - Configured for kubernetes-pods and otel-collector scraping

- ✅ **Grafana** - `grafana.observability.svc:3000` (external: https://grafana.localtest.me:9443)
  - Visualization dashboards
  - Prometheus datasource configured
  - OAuth2-Proxy protected

- ✅ **Tempo** - `tempo-query-frontend.observability.svc:3200`, collector at `:4317`
  - Distributed tracing for infrastructure spans
  - OTLP ingestion via OTEL Collector
  - Object storage backend (S3-compatible)

- ✅ **Phoenix (Arize)** - `phoenix.observability.svc:6006` (HTTP), `:4317` (OTLP gRPC), `:9090` (Prometheus metrics)
  - LLM-specific tracing (agent interactions, prompts, completions)
  - GraphQL API at `/graphql`
  - PostgreSQL backend for trace storage
  - **Exclusive routing**: Only receives LLM traces (CHAIN, LLM, TOOL, AGENT spans)

- ✅ **Loki** - `loki-query-frontend.observability.svc:3100`
  - Log aggregation and querying
  - Promtail DaemonSet for log collection
  - S3-compatible object storage

- ✅ **OTEL Collector** - `otel-collector.observability.svc:4317` (gRPC), `:4318` (HTTP), `:8888` (metrics)
  - **Intelligent routing processor**:
    - LLM traces (openinference.span.kind = CHAIN/LLM/TOOL/AGENT) → Phoenix
    - Infrastructure traces → Tempo
  - **SpanMetrics connector**: Generates metrics from spans without exposing trace content
  - Prometheus metrics exposed for self-monitoring

- ✅ **Korrel8r** - `korrel8r.observability.svc:8080` 🎉 **ALREADY DEPLOYED!**
  - Signal correlation engine (trace ↔ log ↔ metric)
  - REST API for correlation queries
  - Configured stores:
    - Tempo (traces): `http://tempo.observability.svc:3200`
    - Loki (logs): `http://loki-query-frontend.observability.svc:3100`
    - Prometheus (metrics): `http://prometheus.observability.svc:9090`
  - Correlation rules:
    - `trace_to_log`: `{trace_id="$trace_id"}`
    - `log_to_trace`: `traceID="$trace_id"`
    - Service name-based correlation

- ✅ **Promtail** - DaemonSet on all nodes
  - Log collection from all pods
  - Forwards to Loki

- ✅ **Kiali** - `kiali.kiali-system.svc:20001` (external: https://kiali.localtest.me:9443)
  - Service mesh observability
  - Service graph visualization
  - Traffic metrics and traces

#### Platform Infrastructure (components/01-platform/)
- ✅ **Tekton Pipelines** - `tekton-pipelines` namespace
  - CI/CD for AgentBuild
  - Pipeline templates for agent image builds

- ✅ **Container Registry** - `registry.container-registry.svc:5000`
  - Local registry for agent images
  - Used by AgentBuild CRD

- ✅ **Kagenti Operators**
  - **kagenti-operator**: Agent lifecycle management
  - **kagenti-platform-operator**: Platform CRD management (AgentBuild, etc.)

- ✅ **Istio Service Mesh**
  - mTLS for service-to-service encryption (STRICT mode for agents)
  - PERMISSIVE mode for observability backends (OAuth2-Proxy integration)
  - Automatic sidecar injection

#### Authentication (components/01-platform/keycloak/)
- ✅ **Keycloak** - `keycloak.keycloak.svc:8080`
  - SSO and authentication
  - OAuth2/OIDC provider

- ✅ **OAuth2-Proxy** - Multiple instances for service protection
  - Phoenix OAuth2-Proxy
  - Grafana OAuth2-Proxy
  - Kiali OAuth2-Proxy

### 0.2 What's Missing (Needs to be Built)

#### MCP Servers (None exist yet)
- ❌ **Prometheus MCP Server** - Query Prometheus via MCP tools
- ❌ **Tracing MCP Server** - Query Phoenix (LLM) and Tempo (infrastructure)
- ❌ **Loki MCP Server** - Query logs via MCP tools
- ❌ **Korrel8r MCP Server** - Use correlation engine via MCP
- ❌ **GitHub MCP Server** - Create PRs and issues

#### Monitoring Agents (None exist yet)
- ❌ **Metrics Monitoring Agent** - Detect metric anomalies
- ❌ **Trace Analysis Agent** - Analyze traces for errors/latency
- ❌ **Log Analysis Agent** - Detect error patterns in logs
- ❌ **Correlation & RCA Agent** - Correlate signals and identify root causes
- ❌ **Orchestrator Agent** - Coordinate agent workflow
- ❌ **GitHub Remediation Agent** - Create PRs with fixes

#### Agent Build Infrastructure (Partially exists)
- ✅ **AgentBuild CRD** - Kagenti CRD for automated builds (DEPLOYED)
- ✅ **Tekton Pipelines** - Build execution engine (DEPLOYED)
- ❌ **Build scripts** - Helper scripts to generate AgentBuild CRs from any repo
- ❌ **Agent templates** - Reusable agent scaffolds with observability integration

### 0.3 Key Architectural Decisions Already Made

1. **✅ Tracing Split Architecture** (OTEL Collector exclusive routing):
   - Phoenix: LLM traces only (preserves privacy, specialized UI)
   - Tempo: Infrastructure traces only (service mesh, platform)

2. **✅ Correlation via Korrel8r** (already deployed):
   - Purpose-built correlation engine
   - Reusable by agents and humans
   - Reduces agent complexity

3. **✅ GitOps Deployment** (ArgoCD):
   - All manifests in kagenti-demo-deployment
   - Sync waves for dependency ordering
   - Auto-sync enabled

4. **✅ Agent Build via AgentBuild CRD** (Tekton):
   - Production builds via Tekton pipelines
   - Automated image registry push
   - GitOps-friendly workflow

### 0.4 Observability Endpoints Summary

| Service | Internal Endpoint | External Endpoint | Protocol | Purpose |
|---------|------------------|-------------------|----------|---------|
| **Prometheus** | `prometheus.observability.svc:9090` | N/A | HTTP | Metrics query |
| **Grafana** | `grafana.observability.svc:3000` | https://grafana.localtest.me:9443 | HTTP | Dashboards |
| **Tempo (Query)** | `tempo-query-frontend.observability.svc:3200` | N/A | HTTP | Trace query |
| **Tempo (OTLP)** | `tempo-collector.observability.svc:4317` | N/A | gRPC | Trace ingestion |
| **Phoenix (UI)** | `phoenix.observability.svc:6006` | https://phoenix.localtest.me:9443 | HTTP | LLM trace UI |
| **Phoenix (OTLP)** | `phoenix.observability.svc:4317` | N/A | gRPC | LLM trace ingestion |
| **Phoenix (Metrics)** | `phoenix.observability.svc:9090` | N/A | HTTP | Phoenix self-metrics |
| **Loki** | `loki-query-frontend.observability.svc:3100` | N/A | HTTP | Log query |
| **OTEL Collector (gRPC)** | `otel-collector.observability.svc:4317` | N/A | gRPC | OTLP ingestion |
| **OTEL Collector (HTTP)** | `otel-collector.observability.svc:4318` | N/A | HTTP | OTLP ingestion |
| **OTEL Collector (Metrics)** | `otel-collector.observability.svc:8888` | N/A | HTTP | Collector self-metrics |
| **Korrel8r** | `korrel8r.observability.svc:8080` | N/A | HTTP | Correlation API |
| **Kiali** | `kiali.kiali-system.svc:20001` | https://kiali.localtest.me:9443 | HTTP | Service mesh UI |
| **Container Registry** | `registry.container-registry.svc:5000` | N/A | HTTP | Agent image registry |

---

## Phase 1: Architecture & Design

### 1.1 System Architecture Design

#### High-Level Architecture
```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Monitoring Agents System                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐     │
│  │  Metrics Monitor │  │  Trace Analyzer  │  │  Log Analyzer    │     │
│  │     Agent        │  │      Agent       │  │      Agent       │     │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘     │
│           │                     │                      │                │
│           └──────────┬──────────┴──────────────────────┘                │
│                      │                                                   │
│                      ▼                                                   │
│           ┌──────────────────────┐                                      │
│           │  Orchestrator Agent  │ ◄─── Event Queue (Redis Streams)    │
│           └──────────┬───────────┘                                      │
│                      │                                                   │
│                      ▼                                                   │
│         ┌────────────────────────────┐                                  │
│         │ Correlation & RCA Agent    │                                  │
│         │  (Uses Korrel8r + LLM)     │                                  │
│         └────────────┬───────────────┘                                  │
│                      │                                                   │
│                      ▼                                                   │
│          ┌────────────────────────────┐                                 │
│          │  GitHub Remediation Agent  │                                 │
│          │  (Creates PRs with fixes)  │                                 │
│          └────────────┬───────────────┘                                 │
│                       │                                                  │
│                       ▼                                                  │
│              ┌────────────────┐                                         │
│              │  GitHub Repos  │                                         │
│              │  (PRs created) │                                         │
│              └────────────────┘                                         │
│                                                                           │
├─────────────────────────────────────────────────────────────────────────┤
│                          MCP Server Layer                                │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐          │
│  │ Prometheus │ │  Phoenix/  │ │   Loki     │ │  Korrel8r  │ ┌──────┐ │
│  │    MCP     │ │  Tempo MCP │ │    MCP     │ │    MCP     │ │GitHub│ │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ │ MCP  │ │
│        │              │              │              │         └───┬──┘ │
├────────┼──────────────┼──────────────┼──────────────┼─────────────┼────┤
│                     Observability Stack (Already Deployed ✅)           │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐          │
│  │ Prometheus │ │  Phoenix   │ │    Loki    │ │  Korrel8r  │          │
│  │   :9090    │ │  :6006     │ │   :3100    │ │   :8080    │          │
│  └────────────┘ │  (LLM)     │ └────────────┘ └────────────┘          │
│                 │            │                                          │
│                 │   Tempo    │   ┌──────────────────┐                  │
│                 │  :3200     │   │ OTEL Collector   │                  │
│                 │  (Infra)   │   │ (Smart Routing)  │                  │
│                 └────────────┘   └──────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Agent Workflow
```
1. Detection Phase (Scheduled, every 60s)
   ├─ Metrics Monitor Agent → Prometheus MCP → Detects anomaly
   ├─ Trace Analyzer Agent → Phoenix/Tempo MCP → Detects errors/latency
   └─ Log Analyzer Agent → Loki MCP → Detects error patterns
                                    ↓
                       (Events published to queue)
                                    ↓
2. Orchestration Phase (Event-driven)
   └─ Orchestrator Agent receives events
      ├─ Deduplicates events (same issue)
      ├─ Prioritizes by severity
      └─ Triggers correlation
                                    ↓
3. Correlation Phase (On-demand)
   └─ Correlation & RCA Agent
      ├─ Queries Korrel8r MCP → Correlates trace_id ↔ logs ↔ metrics
      ├─ Uses Prometheus MCP → Gets resource usage context
      ├─ Uses Phoenix/Tempo MCP → Gets full trace details
      ├─ Uses Loki MCP → Gets error log details
      └─ LLM reasoning → Root cause analysis
                                    ↓
4. Remediation Phase (On-demand)
   └─ GitHub Remediation Agent
      ├─ Classifies issue (infra vs app vs platform)
      ├─ Identifies target repository
      ├─ Searches codebase for relevant code (if app issue)
      ├─ Generates fix (config change, resource adjustment, code patch)
      ├─ Creates PR via GitHub MCP
      └─ Tracks PR to avoid duplicates
```

### 1.2 Agent Responsibility Boundaries

#### Monitoring Agents (Detection Layer)
- **Metrics Monitor Agent**:
  - Query Prometheus for golden signals (latency, traffic, errors, saturation)
  - Detect threshold breaches, rate changes, anomalies
  - Publish events: `metric_anomaly`

- **Trace Analyzer Agent**:
  - Query Phoenix for LLM trace errors (agent failures, tool errors, high token usage)
  - Query Tempo for infrastructure trace errors (service failures, high latency)
  - Detect error patterns and latency regressions
  - Publish events: `trace_error`, `latency_regression`

- **Log Analyzer Agent**:
  - Query Loki for error/warning logs
  - Detect log patterns (stack traces, exceptions, panics)
  - Correlate log volume spikes with errors
  - Publish events: `log_error_pattern`

#### Orchestration Agent (Coordination Layer)
- **Orchestrator Agent**:
  - Subscribe to all detection events
  - Deduplicate events (same trace_id, same service, same time window)
  - Prioritize by severity (critical → high → medium → low)
  - Group related events (metric + trace + log for same service)
  - Trigger correlation agent with grouped events
  - Track active investigations to avoid duplicate work

#### Analysis Agent (Intelligence Layer)
- **Correlation & RCA Agent**:
  - Receive grouped events from orchestrator
  - Use Korrel8r to correlate signals:
    - Trace ID → Logs (find error logs for failing traces)
    - Trace ID → Metrics (find resource usage during trace)
    - Service name → Cross-signal correlation
  - Query additional context:
    - Prometheus: CPU/memory/network metrics
    - Phoenix: Full LLM trace (prompts, completions, tool calls)
    - Tempo: Full infrastructure trace (service dependencies, timing)
    - Loki: Complete error logs and stack traces
  - LLM-based root cause analysis:
    - Synthesize all correlated data
    - Identify most likely root cause
    - Generate confidence score
    - Classify issue type
  - Publish events: `root_cause_identified`

#### Remediation Agent (Action Layer)
- **GitHub Remediation Agent**:
  - Receive root cause analysis from RCA agent
  - Classify issue and identify target repository:
    - Infrastructure issues → `kagenti-demo-deployment` (resource limits, replicas, HPA)
    - Kagenti platform issues → `kagenti-operator` (operator bugs, CRD issues)
    - Agent framework issues → `agent-examples-local` (MCP errors, agent runtime)
    - Application issues → App-specific repos (service code, business logic)
  - Generate remediation:
    - Infrastructure: YAML patches for deployments, resource adjustments
    - Application: Code patches (if pattern is clear and confident)
    - Otherwise: Detailed issue with investigation data
  - Create PR via GitHub MCP:
    - Detailed PR description with evidence
    - Links to traces, logs, metrics
    - Verification steps
  - Track created PRs in state store (Redis) to avoid duplicates

### 1.3 Communication Patterns

#### Event Queue Design (Redis Streams)
```yaml
Stream: monitoring-events
Events:
  - metric_anomaly:
      timestamp: "2025-11-17T10:30:00Z"
      source_agent: "metrics-monitor"
      severity: "high"
      service: "checkout-service"
      metric_name: "http_request_duration_seconds_p95"
      current_value: 2.5
      threshold: 0.5
      correlation_id: "uuid-12345"

  - trace_error:
      timestamp: "2025-11-17T10:30:01Z"
      source_agent: "trace-analyzer"
      severity: "critical"
      service: "checkout-service"
      trace_id: "abc123def456"
      span_count: 15
      error_spans: 3
      correlation_id: "uuid-12345"  # Same correlation_id!

  - log_error_pattern:
      timestamp: "2025-11-17T10:30:02Z"
      source_agent: "log-analyzer"
      severity: "high"
      service: "checkout-service"
      pattern: "NullPointerException"
      log_count: 47
      correlation_id: "uuid-12345"  # Same correlation_id!

  - root_cause_identified:
      timestamp: "2025-11-17T10:30:15Z"
      source_agent: "correlation-rca"
      severity: "critical"
      service: "checkout-service"
      root_cause: "Database connection pool exhausted"
      confidence: 0.92
      evidence:
        - trace_ids: ["abc123def456", ...]
        - metrics: ["db_connections_active{service=checkout}"]
        - logs: ["connection timeout after 30s"]
      recommended_action: "Increase DB connection pool size"
      target_repo: "kagenti-demo-deployment"
      correlation_id: "uuid-12345"
```

#### Agent Trigger Mechanisms
- **Scheduled (CronJob)**: Monitoring agents (metrics, trace, log)
  - Run every 60 seconds
  - Stateless execution
  - Query observability stack
  - Publish events on anomaly detection

- **Event-Driven (Long-running pods)**: Orchestrator, RCA, remediation
  - Subscribe to Redis streams
  - Process events as they arrive
  - Maintain state in Redis (active investigations, created PRs)

### 1.4 Issue Classification Taxonomy

#### Severity Levels
- **Critical**: Service completely down, data loss, security breach
- **High**: Degraded performance, elevated error rate (>5%), user impact
- **Medium**: Intermittent errors (<5%), slow queries, resource warnings
- **Low**: Info-level patterns, optimization opportunities

#### Issue Types
```python
IssueType = {
    # Infrastructure
    "resource_exhaustion": {
        "repos": ["kagenti-demo-deployment"],
        "actions": ["increase_limits", "add_HPA", "scale_replicas"]
    },
    "deployment_failure": {
        "repos": ["kagenti-demo-deployment"],
        "actions": ["rollback", "fix_manifest", "check_dependencies"]
    },
    "network_issue": {
        "repos": ["kagenti-demo-deployment"],
        "actions": ["check_istio", "check_dns", "check_policies"]
    },

    # Platform (Kagenti)
    "operator_failure": {
        "repos": ["kagenti-operator", "kagenti-platform-operator"],
        "actions": ["create_issue", "check_logs", "restart_operator"]
    },
    "crd_issue": {
        "repos": ["kagenti-operator"],
        "actions": ["validate_crd", "check_schema", "create_issue"]
    },

    # Agent Framework
    "mcp_connection_failure": {
        "repos": ["agent-examples-local"],
        "actions": ["check_mcp_server", "check_network", "create_issue"]
    },
    "agent_runtime_error": {
        "repos": ["agent-examples-local"],
        "actions": ["check_logs", "check_env", "create_issue"]
    },

    # Application
    "service_error": {
        "repos": ["<service-specific>"],
        "actions": ["code_patch", "create_issue", "rollback"]
    },
    "database_issue": {
        "repos": ["<service-specific>"],
        "actions": ["optimize_query", "add_index", "create_issue"]
    },
}
```

### 1.5 Correlation Strategy

#### Korrel8r Integration
Since Korrel8r is already deployed with configured stores and rules, agents will:

1. **Use existing correlation rules**:
   - `trace_to_log`: Given trace_id, find related logs
   - `log_to_trace`: Given log entry with trace_id, find trace
   - Service name correlation: Find all signals for a service

2. **Query Korrel8r REST API** (via Korrel8r MCP):
   ```
   POST http://korrel8r.observability.svc:8080/api/v1/graphs
   {
     "starting_nodes": [
       {
         "class": "trace",
         "id": "abc123def456"
       }
     ],
     "goals": [
       {"class": "log"},
       {"class": "metric"}
     ]
   }
   ```

3. **Correlation workflow**:
   - Start with trace_id from trace_error event
   - Korrel8r finds related logs (via trace_id in log labels)
   - Korrel8r finds related metrics (via service name)
   - RCA agent queries Prometheus/Loki/Tempo for full details
   - LLM synthesizes all data for root cause analysis

#### Temporal Correlation
- Events within ±5 minute window considered related
- Earlier events may be root cause of later events
- Causal chain analysis: metric spike → trace errors → log errors

#### Service Correlation
- Same `service.name` label across all signals
- Service dependency graph from Kiali/Tempo
- Failure propagation detection (service A fails → service B errors)

---

## Phase 1.5: Phoenix Production Hardening

**Note**: Based on research in RESEARCH_Phoenix_Configuration.md, Phoenix is deployed but needs production hardening.

### 1.5.1 Security Implementation (CRITICAL)
- [ ] **Implement Authentication for Phoenix**:
  - [ ] Add `PHOENIX_ADMIN_SECRET` environment variable
  - [ ] Configure OTEL Collector with authentication headers
  - [ ] Document authentication setup for monitoring agents

- [ ] **Secure Database Credentials**:
  - [ ] Create Kubernetes Secret for PostgreSQL credentials:
    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: phoenix-postgres-credentials
      namespace: observability
    type: Opaque
    stringData:
      username: postgres
      password: <generate-strong-password>
      database: postgres
    ```
  - [ ] Update Phoenix StatefulSet to use Secret references
  - [ ] Update PostgreSQL StatefulSet to use Secret references
  - [ ] Remove hardcoded credentials from YAML files

- [ ] **Network Security**:
  - [ ] Create NetworkPolicy to restrict Phoenix API access:
    - Allow: MCP servers, monitoring agents
    - Allow: OTEL Collector
    - Deny: All other pods
  - [ ] Create NetworkPolicy for PostgreSQL (only Phoenix can access)

### 1.5.2 Resource Management (HIGH PRIORITY)
- [ ] **Add Resource Limits**:
  - [ ] Phoenix StatefulSet:
    ```yaml
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2000m
        memory: 4Gi
    ```
  - [ ] OTEL Collector:
    ```yaml
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
    ```
  - [ ] PostgreSQL:
    ```yaml
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
    ```

### 1.5.3 High Availability (MEDIUM PRIORITY)
- [ ] **Scale OTEL Collector**:
  - [ ] Change from Deployment to DaemonSet or increase replicas to 2+
  - [ ] Add pod anti-affinity rules
  - [ ] Configure load balancing

- [ ] **Phoenix Scaling** (optional for initial deployment):
  - [ ] Evaluate if Phoenix supports multiple replicas
  - [ ] If yes, increase to 2-3 replicas
  - [ ] Add pod anti-affinity rules

- [ ] **PostgreSQL HA** (optional, consider managed service):
  - [ ] Evaluate using managed PostgreSQL (RDS, Cloud SQL, etc.)
  - [ ] Or configure PostgreSQL streaming replication
  - [ ] Set up automated backups

### 1.5.4 Monitoring Phoenix Itself
- [ ] **Create ServiceMonitor for Prometheus**:
  ```yaml
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    name: phoenix
    namespace: observability
  spec:
    selector:
      matchLabels:
        app: phoenix
    endpoints:
    - port: prometheus-metrics  # port 9090
      interval: 30s
      path: /metrics
  ```

- [ ] **Add Prometheus Alerts**:
  - [ ] Alert: Phoenix trace ingestion rate drops to 0
  - [ ] Alert: Phoenix database connection failures
  - [ ] Alert: Phoenix memory usage > 80%
  - [ ] Alert: PostgreSQL storage > 80% full
  - [ ] Alert: OTEL Collector trace export failures

- [ ] **Create Grafana Dashboard**:
  - [ ] Phoenix trace ingestion rate
  - [ ] Trace query latency
  - [ ] Database connection pool status
  - [ ] Storage usage trends
  - [ ] Error rate

### 1.5.5 Storage and Retention
- [ ] **Increase Storage Capacity**:
  - [ ] PostgreSQL: Increase from 1Gi to 20-50Gi
  - [ ] Phoenix: Monitor 8Gi usage, increase if needed
  - [ ] Add storage monitoring alerts

- [ ] **Configure Data Retention**:
  - [ ] Research Phoenix data retention configuration
  - [ ] Set retention policy (e.g., 30 days for traces)
  - [ ] Configure automated cleanup jobs if needed

### 1.5.6 TLS/Encryption (OPTIONAL)
- [ ] **Enable TLS for OTEL Collector → Phoenix**:
  - [ ] Generate certificates using cert-manager
  - [ ] Configure OTEL Collector exporter with TLS
  - [ ] Update Phoenix to require TLS

- [ ] **Enable PostgreSQL SSL**:
  - [ ] Configure PostgreSQL for SSL connections
  - [ ] Update Phoenix connection string to use SSL

---

## Phase 2: MCP Tool Development

### 2.1 Prometheus MCP Server
**Location**: `agent-examples-local/mcp/prometheus-mcp/`

**Endpoints**: Prometheus at `http://prometheus.observability.svc:9090`

- [ ] Design Prometheus MCP tool interface:
  ```
  Tools:
  - query_promql: Execute PromQL queries
  - get_metric_range: Fetch metric time series
  - get_current_value: Get latest metric value
  - list_metrics: Discover available metrics
  - get_alerts: Fetch active Prometheus alerts
  - get_recording_rules: List recording rules
  - get_targets: List scrape targets and their status
  ```

- [ ] Implementation tasks:
  - [ ] Create MCP server scaffold (choose Python or TypeScript)
  - [ ] Implement Prometheus HTTP API client (`/api/v1/query`, `/api/v1/query_range`)
  - [ ] Add query validation and sanitization
  - [ ] Implement result pagination for large datasets
  - [ ] Add caching layer for frequently accessed metrics
  - [ ] Error handling and retry logic
  - [ ] Rate limiting to protect Prometheus

- [ ] Configuration design:
  - [ ] Prometheus endpoint URL: `http://prometheus.observability.svc:9090`
  - [ ] Query timeout settings: 30s default
  - [ ] Default time ranges: 5m, 15m, 1h, 24h
  - [ ] Max query results limit: 10000 samples

- [ ] Testing:
  - [ ] Unit tests for each tool
  - [ ] Integration tests against deployed Prometheus
  - [ ] Load testing for concurrent queries

- [ ] Documentation:
  - [ ] Tool usage examples
  - [ ] Common PromQL patterns for agents (golden signals)
  - [ ] Troubleshooting guide

### 2.2 Tracing MCP Server (Phoenix + Tempo)
**Location**: `agent-examples-local/mcp/tracing-mcp/`

**Endpoints**:
- Phoenix (LLM traces): `http://phoenix.observability.svc:6006` (HTTP), `:4317` (gRPC OTLP)
- Tempo (infrastructure traces): `http://tempo-query-frontend.observability.svc:3200`

- [x] **DECISION**: Dual tracing backend support
  - Phoenix: LLM/agent traces (CHAIN, LLM, TOOL, AGENT spans)
  - Tempo: Infrastructure traces (service mesh, platform)
  - MCP server provides unified interface to both

- [x] Research Phoenix API capabilities: **SEE RESEARCH_Phoenix_Configuration.md**
  - [x] Phoenix deployed at `phoenix.observability.svc:6006` (HTTP) and `:4317` (gRPC)
  - [x] GraphQL API available at `/graphql` endpoint
  - [x] REST API at `/v1/` for OTLP and metrics
  - [x] OpenTelemetry-compatible OTLP ingestion via OTEL Collector
  - ⚠️ No authentication currently configured (needs implementation)
  - [x] PostgreSQL backend for trace storage
  - [x] Prometheus metrics exposed on port 9090

- [ ] Design Tracing MCP tool interface:
  ```
  Tools:
  # Phoenix (LLM traces)
  - query_llm_traces: Find LLM agent traces by service, time range
  - get_llm_trace_by_id: Fetch full LLM trace details
  - analyze_llm_spans: Extract LLM-specific data (prompts, completions, tokens)
  - find_llm_errors: Query LLM traces with errors
  - get_token_usage: Aggregate token usage metrics

  # Tempo (infrastructure traces)
  - query_infra_traces: Find infrastructure traces by service, operation
  - get_infra_trace_by_id: Fetch full infrastructure trace
  - analyze_service_graph: Build service dependency graph
  - find_slow_traces: Query traces above latency threshold
  - get_critical_path: Calculate critical path in trace

  # Common
  - get_trace_by_id: Auto-route to Phoenix or Tempo based on span kind
  - find_errors: Query all traces with errors (both backends)
  ```

- [ ] Implementation tasks:
  - [ ] Create MCP server scaffold
  - [ ] **Phoenix Integration**:
    - [ ] Implement Phoenix GraphQL API client:
      - GraphQL endpoint: `http://phoenix.observability.svc:6006/graphql`
      - Query builder for trace retrieval
      - Error handling and retry logic
    - [ ] Build trace query capabilities:
      - Service name filtering
      - Time range queries (start_time, end_time)
      - Status filtering (OK, ERROR)
      - Span attribute filtering (LLM model, token count, etc.)
      - Limit and pagination support
    - [ ] Implement span filtering and aggregation:
      - Filter spans by name pattern (e.g., "llm.*", "tool.*")
      - Aggregate token usage across traces
      - Calculate latency percentiles (p50, p95, p99)
    - [ ] Add LLM-specific trace analysis:
      - Extract `llm.input_messages` and `llm.output_messages`
      - Parse `llm.token_count.prompt`, `llm.token_count.completion`, `llm.token_count.total`
      - Extract `llm.model_name`, `llm.provider`, `llm.invocation_parameters`
      - Detect cost patterns (high token usage)
    - [ ] Error detection and classification:
      - Parse error status from spans
      - Extract error messages and stack traces
      - Classify by error type (LLM errors, tool errors, agent errors)

  - [ ] **Tempo Integration**:
    - [ ] Implement Tempo HTTP API client:
      - Query endpoint: `http://tempo-query-frontend.observability.svc:3200/api/traces/{trace_id}`
      - Search endpoint: `/api/search?tags=...`
    - [ ] Build trace query capabilities:
      - Service name, span name, duration filtering
      - Tag-based search
      - Time range queries
    - [ ] Service graph extraction from traces
    - [ ] Critical path calculation (longest span chain)

  - [ ] **Unified Interface**:
    - [ ] Auto-routing logic:
      - Check `openinference.span.kind` attribute
      - If CHAIN/LLM/TOOL/AGENT → Route to Phoenix
      - Otherwise → Route to Tempo
    - [ ] Implement helper methods:
      - `query_errors()`: Get all error traces from both backends
      - `get_trace_by_id()`: Auto-route based on trace attributes
      - `find_slow_traces()`: Query both backends and merge results
    - [ ] Handle backend-specific data structures:
      - Parse GraphQL response format (Phoenix)
      - Parse JSON response format (Tempo)
      - Convert to unified agent-friendly JSON structure

- [ ] Configuration:
  - [ ] Phoenix HTTP endpoint: `http://phoenix.observability.svc:6006`
  - [ ] Tempo HTTP endpoint: `http://tempo-query-frontend.observability.svc:3200`
  - [ ] Query limits (max traces per query, default: 100)
  - [ ] Sampling strategy for high-volume traces
  - [ ] Timeout settings (30s default)

- [ ] Testing & Documentation:
  - [ ] Test against deployed Phoenix instance (LLM traces)
  - [ ] Test against deployed Tempo instance (infrastructure traces)
  - [ ] Verify auto-routing works correctly
  - [ ] Document Phoenix-specific features (LLM trace attributes)
  - [ ] Create examples for querying both backends

### 2.3 Loki MCP Server
**Location**: `agent-examples-local/mcp/loki-mcp/`

**Endpoints**: Loki at `http://loki-query-frontend.observability.svc:3100`

- [ ] Design Loki MCP tool interface:
  ```
  Tools:
  - query_logs: Execute LogQL queries
  - query_logs_by_trace_id: Find logs for a specific trace_id
  - query_logs_by_service: Get logs for a service in time range
  - find_error_logs: Query logs with level=error or level=warning
  - find_log_patterns: Detect common error patterns (stack traces, exceptions)
  - get_log_volume: Get log volume metrics by service/level
  - stream_logs: Stream live logs (for real-time monitoring)
  ```

- [ ] Implementation tasks:
  - [ ] Create MCP server scaffold
  - [ ] Implement Loki HTTP API client (`/loki/api/v1/query`, `/loki/api/v1/query_range`)
  - [ ] Build LogQL query builders:
    - Label filtering: `{service="checkout", level="error"}`
    - Text filtering: `{service="checkout"} |= "NullPointerException"`
    - Regex filtering: `{service="checkout"} |~ "error|exception"`
    - Trace ID correlation: `{service="checkout"} | json | trace_id="abc123"`
  - [ ] Implement log parsing and extraction:
    - JSON log parsing (`| json`)
    - Pattern extraction (`| pattern "<pattern>"`)
    - Line filtering and formatting
  - [ ] Add aggregation capabilities:
    - Log volume: `count_over_time()`
    - Rate: `rate()`
    - Distinct values: `count_over_time()` with `by (label)`
  - [ ] Error pattern detection:
    - Stack trace extraction
    - Exception classification
    - Error frequency analysis
  - [ ] Implement result pagination and limits
  - [ ] Error handling and retry logic

- [ ] Configuration:
  - [ ] Loki endpoint URL: `http://loki-query-frontend.observability.svc:3100`
  - [ ] Query timeout settings: 30s default
  - [ ] Max log lines per query: 5000
  - [ ] Default time ranges: 5m, 15m, 1h

- [ ] Testing & Documentation:
  - [ ] Test against deployed Loki instance
  - [ ] Verify trace_id correlation works
  - [ ] Document LogQL patterns for common use cases
  - [ ] Create examples for error detection

### 2.4 Korrel8r MCP Server
**Location**: `agent-examples-local/mcp/korrel8r-mcp/`

**Endpoints**: Korrel8r at `http://korrel8r.observability.svc:8080`

**CRITICAL**: Korrel8r is already deployed with configured stores and rules! ✅

- [ ] Research Korrel8r REST API:
  - [ ] Read Korrel8r documentation
  - [ ] Test API endpoints:
    - `GET /api/v1/graphs` - Get correlation graph
    - `POST /api/v1/graphs` - Query correlations
    - `GET /api/v1/stores` - List configured stores
    - `GET /api/v1/rules` - List correlation rules
  - [ ] Understand query format:
    ```json
    {
      "starting_nodes": [
        {"class": "trace", "id": "trace-id-123"}
      ],
      "goals": [
        {"class": "log"},
        {"class": "metric"}
      ]
    }
    ```

- [ ] Design Korrel8r MCP tool interface:
  ```
  Tools:
  - correlate_trace_to_logs: Find logs related to trace_id
  - correlate_trace_to_metrics: Find metrics related to trace
  - correlate_logs_to_trace: Find trace from log entry with trace_id
  - correlate_service_signals: Get all signals (trace+log+metric) for service
  - find_root_cause_signals: Use correlation graph to identify root cause
  - get_correlation_graph: Retrieve full correlation topology
  - query_correlation_path: Find correlation path between two signals
  ```

- [ ] Implementation tasks:
  - [ ] Create MCP server scaffold
  - [ ] Implement Korrel8r REST API client:
    - `POST /api/v1/graphs` for correlation queries
    - `GET /api/v1/stores` to verify store configuration
    - `GET /api/v1/rules` to list available correlation rules
  - [ ] Build correlation query builders:
    - Starting node: trace_id, log entry, metric query
    - Goal classes: trace, log, metric
    - Constraints: time range, service name
  - [ ] Implement correlation result parsing:
    - Extract correlation graph (nodes + edges)
    - Rank correlated signals by relevance
    - Calculate correlation confidence scores
  - [ ] Add helper methods:
    - Auto-detect signal type from input (trace_id, log query, metric)
    - Build correlation queries automatically
    - Filter and sort correlation results
  - [ ] Error handling for missing stores or rules
  - [ ] Retry logic for transient failures

- [ ] Configuration:
  - [ ] Korrel8r endpoint URL: `http://korrel8r.observability.svc:8080`
  - [ ] Timeout settings: 30s default
  - [ ] Max correlation depth: 3 hops
  - [ ] Correlation confidence threshold: 0.7

- [ ] Testing & Documentation:
  - [ ] Verify Korrel8r stores are configured:
    - Tempo: `http://tempo.observability.svc:3200`
    - Loki: `http://loki-query-frontend.observability.svc:3100`
    - Prometheus: `http://prometheus.observability.svc:9090`
  - [ ] Test trace → log correlation
  - [ ] Test trace → metric correlation
  - [ ] Test service-level correlation
  - [ ] Document correlation query patterns
  - [ ] Create examples for common correlation scenarios

### 2.5 GitHub MCP Server
**Location**: `agent-examples-local/mcp/github-mcp/`

- [ ] Design GitHub MCP tool interface:
  ```
  Tools:
  - create_pull_request: Create PR with title, body, branch, files
  - create_issue: Create GitHub issue
  - list_open_prs: Check for existing PRs to avoid duplicates
  - update_pr: Add comments or update PR
  - search_code: Find relevant code sections
  - get_file_content: Read repository files
  - create_branch: Create feature branch for PR
  - list_repositories: Get accessible repositories
  - check_pr_exists: Check if PR already exists for issue
  ```

- [ ] Implementation tasks:
  - [ ] Create MCP server scaffold
  - [ ] Implement GitHub API client (REST API v4 or GraphQL)
  - [ ] Add PR creation logic:
    - Create branch from main/master
    - Commit file changes
    - Create PR with template
  - [ ] Add PR template generation logic:
    - Issue detection section
    - Evidence section (metrics, traces, logs)
    - RCA section
    - Proposed resolution
    - Verification steps
  - [ ] Implement duplicate PR detection:
    - Search for open PRs with same title pattern
    - Check PR body for correlation_id
    - Warn if duplicate found
  - [ ] Add PR labeling and assignment logic:
    - Auto-label by issue type (bug, infrastructure, enhancement)
    - Auto-assign reviewers based on repo config
  - [ ] Implement multi-repo support:
    - Repository discovery and mapping
    - Per-repo configuration (reviewers, labels, branch names)
  - [ ] Add issue creation and updates
  - [ ] Implement code search and file retrieval

- [ ] Configuration:
  - [ ] GitHub token (from k8s secret): `github-api-token`
  - [ ] Repository URLs and access mappings:
    ```yaml
    repositories:
      infrastructure: "redhat-et/kagenti-demo-deployment"
      kagenti: "redhat-et/kagenti-operator"
      agents: "redhat-et/agent-examples-local"
      # Add app repos as needed
    ```
  - [ ] Default PR reviewers by repo:
    ```yaml
    reviewers:
      infrastructure: ["platform-team"]
      kagenti: ["agent-team"]
      agents: ["agent-team"]
    ```
  - [ ] PR template paths: `.github/PULL_REQUEST_TEMPLATE.md`
  - [ ] Branch naming convention: `agent-fix/<issue-type>-<correlation-id>`

- [ ] PR Content Strategy:
  - [ ] Design PR body template:
    ```markdown
    ## Issue Detection
    - **Type**: [Infrastructure/Application/Platform]
    - **Severity**: [Critical/High/Medium/Low]
    - **Detection Time**: [timestamp]
    - **Affected Components**: [list]
    - **Correlation ID**: [uuid]

    ## Evidence
    ### Metrics
    [Prometheus query results, links to Grafana dashboards]

    ### Traces
    [Trace IDs, links to Phoenix/Tempo, error spans, latency data]

    ### Logs
    [Log queries, links to Grafana Loki, error patterns]

    ### Correlation Analysis
    [Korrel8r findings, correlation graph]

    ## Root Cause Analysis
    [Agent's LLM-based analysis, confidence score]

    ## Proposed Resolution
    [Code changes or configuration updates, YAML diffs]

    ## Verification Steps
    - [ ] Check metrics return to normal range
    - [ ] Verify traces show no errors
    - [ ] Monitor for 24h post-deployment
    - [ ] Review alerts in Grafana

    ## Related Links
    - **Grafana Dashboard**: https://grafana.localtest.me:9443/d/...
    - **Phoenix Trace**: https://phoenix.localtest.me:9443/traces/abc123
    - **Loki Logs**: https://grafana.localtest.me:9443/explore?...

    ---
    🤖 Generated by Monitoring Agent
    **Agent**: correlation-rca-agent
    **Correlation ID**: uuid-12345
    **Timestamp**: 2025-11-17T10:30:15Z
    ```

- [ ] Testing & Documentation:
  - [ ] Test PR creation in test repository
  - [ ] Test duplicate detection
  - [ ] Verify PR template rendering
  - [ ] Document GitHub token permissions required
  - [ ] Create examples for different issue types

---

## Phase 3: Agent Build Process using Kagenti AgentBuild CRD

**CRITICAL**: Kagenti provides a production-ready agent build system via `AgentBuild` CRD and Tekton pipelines! ✅

### 3.1 AgentBuild CRD Overview

The `AgentBuild` CRD automates agent image builds using Tekton pipelines and pushes to the local container registry.

**Example AgentBuild CR**:
```yaml
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentBuild
metadata:
  name: metrics-monitor-agent-build
  namespace: monitoring-agents
spec:
  source:
    sourceRepository: "github.com/redhat-et/agent-examples-local.git"
    sourceRevision: "main"
    sourceSubfolder: "agents/metrics-monitor"
    sourceCredentials:
      name: github-token-secret  # k8s secret with GitHub PAT

  pipeline:
    namespace: kagenti-system  # Tekton pipelines run here
    parameters:
      - name: SOURCE_REPO_SECRET
        value: github-token-secret

  buildOutput:
    image: "metrics-monitor-agent"
    imageTag: "v0.1.0"
    imageRegistry: "registry.container-registry.svc.cluster.local:5000"

  cleanupAfterBuild: true
  mode: dev
```

**How it works**:
1. AgentBuild CR is created in cluster
2. Kagenti Platform Operator watches for AgentBuild CRs
3. Operator creates Tekton PipelineRun
4. Tekton clones source repository
5. Tekton builds Docker image from agent code
6. Tekton pushes image to local registry
7. Image is available at: `localhost:5000/metrics-monitor-agent:v0.1.0`
8. Agent deployment can reference this image

### 3.2 Build Scripts for Any Agent Repo

**Location**: `kagenti-demo-deployment/scripts/agent-build/`

- [ ] **Create `generate-agent-build.sh`**:
  ```bash
  #!/usr/bin/env bash
  # Generate AgentBuild CR for any agent repository
  # Usage: ./generate-agent-build.sh <agent-name> <repo-url> <subfolder> <image-tag>

  set -euo pipefail

  AGENT_NAME="${1:?Agent name required}"
  REPO_URL="${2:?Repository URL required}"
  SUBFOLDER="${3:?Subfolder required}"
  IMAGE_TAG="${4:-v0.1.0}"

  NAMESPACE="monitoring-agents"
  REGISTRY="registry.container-registry.svc.cluster.local:5000"

  cat <<EOF > "agent-builds/${AGENT_NAME}-build.yaml"
  apiVersion: agent.kagenti.dev/v1alpha1
  kind: AgentBuild
  metadata:
    name: ${AGENT_NAME}-build
    namespace: ${NAMESPACE}
    labels:
      app: ${AGENT_NAME}
      component: monitoring-agent
  spec:
    source:
      sourceRepository: "${REPO_URL}"
      sourceRevision: "main"
      sourceSubfolder: "${SUBFOLDER}"
      sourceCredentials:
        name: github-token-secret

    pipeline:
      namespace: kagenti-system
      parameters:
        - name: SOURCE_REPO_SECRET
          value: github-token-secret

    buildOutput:
      image: "${AGENT_NAME}"
      imageTag: "${IMAGE_TAG}"
      imageRegistry: "${REGISTRY}"

    cleanupAfterBuild: true
    mode: dev
  EOF

  echo "✅ AgentBuild CR generated: agent-builds/${AGENT_NAME}-build.yaml"
  echo ""
  echo "Next steps:"
  echo "1. Review the generated file"
  echo "2. Apply to cluster: kubectl apply -f agent-builds/${AGENT_NAME}-build.yaml"
  echo "3. Monitor build: kubectl get agentbuild -n ${NAMESPACE} -w"
  echo "4. Check logs: kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=<run-name>"
  ```

- [ ] **Create `build-agent.sh`** (All-in-one build script):
  ```bash
  #!/usr/bin/env bash
  # Build and deploy agent in one command
  # Usage: ./build-agent.sh <agent-name> <repo-url> <subfolder> [image-tag]

  set -euo pipefail

  AGENT_NAME="${1:?Agent name required}"
  REPO_URL="${2:?Repository URL required}"
  SUBFOLDER="${3:?Subfolder required}"
  IMAGE_TAG="${4:-v0.1.0}"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  echo "🔨 Building agent: ${AGENT_NAME}"
  echo "  Repository: ${REPO_URL}"
  echo "  Subfolder: ${SUBFOLDER}"
  echo "  Image tag: ${IMAGE_TAG}"
  echo ""

  # Generate AgentBuild CR
  "${SCRIPT_DIR}/generate-agent-build.sh" "${AGENT_NAME}" "${REPO_URL}" "${SUBFOLDER}" "${IMAGE_TAG}"

  # Apply AgentBuild CR
  echo "📦 Applying AgentBuild CR..."
  kubectl apply -f "${SCRIPT_DIR}/agent-builds/${AGENT_NAME}-build.yaml"

  # Wait for build to complete
  echo "⏳ Waiting for build to complete..."
  kubectl wait --for=condition=Complete --timeout=600s \
    agentbuild/${AGENT_NAME}-build -n monitoring-agents

  # Check build status
  BUILD_STATUS=$(kubectl get agentbuild/${AGENT_NAME}-build -n monitoring-agents \
    -o jsonpath='{.status.phase}')

  if [[ "${BUILD_STATUS}" == "Succeeded" ]]; then
    echo "✅ Build succeeded!"
    echo ""
    echo "Image available at:"
    echo "  localhost:5000/${AGENT_NAME}:${IMAGE_TAG}"
    echo ""
    echo "Next steps:"
    echo "1. Create agent deployment manifest"
    echo "2. Reference image: localhost:5000/${AGENT_NAME}:${IMAGE_TAG}"
    echo "3. Deploy via GitOps"
  else
    echo "❌ Build failed with status: ${BUILD_STATUS}"
    echo ""
    echo "Check logs:"
    PIPELINE_RUN=$(kubectl get agentbuild/${AGENT_NAME}-build -n monitoring-agents \
      -o jsonpath='{.status.pipelineRun}')
    echo "  kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=${PIPELINE_RUN}"
    exit 1
  fi
  ```

- [ ] **Create `build-all-monitoring-agents.sh`**:
  ```bash
  #!/usr/bin/env bash
  # Build all monitoring agents at once

  set -euo pipefail

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_URL="github.com/redhat-et/agent-examples-local.git"
  IMAGE_TAG="${1:-v0.1.0}"

  AGENTS=(
    "metrics-monitor:agents/metrics-monitor"
    "trace-analyzer:agents/trace-analyzer"
    "log-analyzer:agents/log-analyzer"
    "orchestrator:agents/orchestrator"
    "correlation-rca:agents/correlation-rca"
    "github-remediation:agents/github-remediation"
  )

  echo "🔨 Building all monitoring agents..."
  echo "  Image tag: ${IMAGE_TAG}"
  echo ""

  for agent in "${AGENTS[@]}"; do
    IFS=: read -r name subfolder <<< "$agent"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building: ${name}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    "${SCRIPT_DIR}/build-agent.sh" "${name}" "${REPO_URL}" "${subfolder}" "${IMAGE_TAG}"
    echo ""
  done

  echo "✅ All agents built successfully!"
  ```

- [ ] **Create `agent-build-status.sh`** (Monitor builds):
  ```bash
  #!/usr/bin/env bash
  # Monitor agent build status

  kubectl get agentbuilds -n monitoring-agents \
    -o custom-columns=\
  NAME:.metadata.name,\
  STATUS:.status.phase,\
  IMAGE:.spec.buildOutput.image,\
  TAG:.spec.buildOutput.imageTag,\
  AGE:.metadata.creationTimestamp
  ```

### 3.3 Agent Template Structure

**Location**: `agent-examples-local/agents/_template/`

- [ ] Create reusable agent template with observability integration:
  ```
  agent-examples-local/agents/_template/
  ├── Dockerfile
  ├── requirements.txt (or package.json)
  ├── agent.py (or agent.ts)
  ├── config/
  │   ├── mcp-servers.yaml      # MCP server endpoints
  │   └── observability.yaml    # OTEL configuration
  ├── tools/
  │   └── (agent-specific tools)
  └── README.md
  ```

- [ ] **Dockerfile template**:
  ```dockerfile
  FROM python:3.11-slim

  WORKDIR /app

  # Install dependencies
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt

  # Copy agent code
  COPY . .

  # Environment variables for observability
  ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.observability.svc.cluster.local:4317"
  ENV OTEL_SERVICE_NAME="<agent-name>"
  ENV OTEL_RESOURCE_ATTRIBUTES="service.namespace=monitoring-agents"

  # Health check
  HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import sys; sys.exit(0)"

  # Run agent
  CMD ["python", "agent.py"]
  ```

- [ ] **requirements.txt template**:
  ```
  # Agent framework
  opentelemetry-sdk>=1.20.0
  opentelemetry-exporter-otlp>=1.20.0
  opentelemetry-instrumentation>=0.41b0

  # MCP client
  mcp-client>=0.1.0

  # LLM provider (if using LLM reasoning)
  openai>=1.0.0

  # Utilities
  pyyaml>=6.0
  requests>=2.31.0
  tenacity>=8.2.0  # Retry logic
  redis>=5.0.0  # For event queue
  ```

- [ ] **config/mcp-servers.yaml template**:
  ```yaml
  mcp_servers:
    prometheus:
      url: "http://prometheus-mcp.monitoring-agents.svc:8080"
      timeout: 30

    phoenix:
      url: "http://phoenix-mcp.monitoring-agents.svc:8080"
      timeout: 30

    tempo:
      url: "http://tempo-mcp.monitoring-agents.svc:8080"
      timeout: 30

    loki:
      url: "http://loki-mcp.monitoring-agents.svc:8080"
      timeout: 30

    korrel8r:
      url: "http://korrel8r-mcp.monitoring-agents.svc:8080"
      timeout: 30

    github:
      url: "http://github-mcp.monitoring-agents.svc:8080"
      timeout: 60

  # Service discovery fallback
  use_kubernetes_dns: true
  namespace: "monitoring-agents"
  ```

- [ ] **config/observability.yaml template**:
  ```yaml
  opentelemetry:
    endpoint: "http://otel-collector.observability.svc.cluster.local:4317"
    protocol: "grpc"

    service:
      name: "<agent-name>"  # Override via env var
      namespace: "monitoring-agents"
      version: "v0.1.0"

    # Span attributes for ALL agent operations
    resource_attributes:
      service.namespace: "monitoring-agents"
      deployment.environment: "production"
      openinference.span.kind: "AGENT"  # Route to Phoenix

    # Trace sampling (1.0 = sample everything)
    trace_sampling_ratio: 1.0

    # Export interval
    batch_span_processor:
      max_export_batch_size: 512
      schedule_delay_millis: 5000

  # Prometheus metrics (if agent exposes metrics)
  prometheus:
    enabled: true
    port: 9090
    path: "/metrics"
  ```

- [ ] **agent.py template** (Python):
  ```python
  #!/usr/bin/env python3
  import os
  import logging
  from opentelemetry import trace
  from opentelemetry.sdk.trace import TracerProvider
  from opentelemetry.sdk.trace.export import BatchSpanProcessor
  from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
  from opentelemetry.sdk.resources import Resource

  # Configure logging
  logging.basicConfig(level=logging.INFO)
  logger = logging.getLogger(__name__)

  # Configure OpenTelemetry
  resource = Resource.create({
      "service.name": os.getenv("OTEL_SERVICE_NAME", "monitoring-agent"),
      "service.namespace": "monitoring-agents",
      "openinference.span.kind": "AGENT",  # Route to Phoenix
  })

  tracer_provider = TracerProvider(resource=resource)
  otlp_exporter = OTLPSpanExporter(
      endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
      insecure=True
  )
  tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
  trace.set_tracer_provider(tracer_provider)

  tracer = trace.get_tracer(__name__)

  class MonitoringAgent:
      def __init__(self):
          self.logger = logger
          self.tracer = tracer

      @tracer.start_as_current_span("agent.run")
      def run(self):
          """Main agent loop"""
          self.logger.info("Agent started")

          # TODO: Implement agent logic
          # - Query MCP servers
          # - Detect issues
          # - Publish events

          pass

  if __name__ == "__main__":
      agent = MonitoringAgent()
      agent.run()
  ```

### 3.4 GitOps Workflow for Agent Building

Following CLAUDE.md patterns:

```bash
# 1. Develop agent code locally
cd agent-examples-local/agents/metrics-monitor/
vim agent.py

# 2. Test locally (if possible)
python agent.py

# 3. Commit agent code
git add agents/metrics-monitor/
git commit -m ":sparkles: Add metrics monitoring agent"
git push origin main

# 4. Generate AgentBuild CR
cd kagenti-demo-deployment
./scripts/agent-build/generate-agent-build.sh \
  metrics-monitor \
  github.com/redhat-et/agent-examples-local.git \
  agents/metrics-monitor \
  v0.1.0

# 5. Commit AgentBuild CR (GitOps)
git add components/03-applications/agents/monitoring/agent-builds/
git commit -m ":rocket: Add AgentBuild for metrics-monitor"
git push origin main

# 6. ArgoCD syncs AgentBuild CR to cluster
argocd app sync monitoring-agents \
  --port-forward --port-forward-namespace argocd --grpc-web

# 7. Monitor build
kubectl get agentbuilds -n monitoring-agents -w

# 8. Check build logs if needed
kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=<run-name>

# 9. Verify image in registry
curl http://registry.container-registry.svc:5000/v2/metrics-monitor/tags/list

# 10. Create agent deployment manifest
cat <<EOF > components/03-applications/agents/monitoring/metrics-monitor.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-monitor-agent
  namespace: monitoring-agents
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: agent
          image: localhost:5000/metrics-monitor:v0.1.0
          env:
            - name: OTEL_SERVICE_NAME
              value: "metrics-monitor"
EOF

# 11. Commit deployment manifest
git add components/03-applications/agents/monitoring/metrics-monitor.yaml
git commit -m ":rocket: Deploy metrics-monitor agent"
git push origin main

# 12. Sync deployment
argocd app sync monitoring-agents \
  --port-forward --port-forward-namespace argocd --grpc-web

# 13. Validate deployment
./scripts/platform-status.sh
kubectl get pods -n monitoring-agents
```

---

## Phase 3.5: Agent Development

### 3.5.1 Metrics Monitoring Agent
**Location**: `agent-examples-local/agents/metrics-monitor/`

- [ ] Define agent purpose and scope:
  - Monitor key metrics for anomalies
  - Detect threshold breaches, spikes, drops
  - Generate alerts for further investigation

- [ ] Design agent logic:
  - [ ] Define monitored metrics list (golden signals: latency, traffic, errors, saturation)
  - [ ] Implement anomaly detection algorithms:
    - Static thresholds (> threshold)
    - Dynamic thresholds (> historical baseline * multiplier)
    - Rate of change detection (delta > X per minute)
    - Seasonality-aware detection (if needed)
  - [ ] Design alert generation logic
  - [ ] Implement alert deduplication (same metric, same time window)

- [ ] Agent configuration:
  ```yaml
  agent_name: "metrics-monitor"

  mcp_servers:
    - prometheus-mcp

  metrics_to_monitor:
    # Latency (Golden Signal 1)
    - name: http_request_duration_seconds
      labels: {quantile: "0.95"}
      aggregation: "avg by (service)"
      threshold: 0.5  # 500ms
      threshold_type: static
      window: 5m
      severity: high

    # Traffic (Golden Signal 2)
    - name: http_requests_total
      aggregation: "rate(5m)"
      threshold_type: dynamic
      baseline_multiplier: 2.0  # 2x normal traffic
      window: 5m
      severity: medium

    # Errors (Golden Signal 3)
    - name: http_requests_total
      labels: {status: "~5.."}  # 5xx errors
      aggregation: "rate(5m)"
      threshold: 0.05  # 5% error rate
      threshold_type: static
      window: 5m
      severity: critical

    # Saturation (Golden Signal 4)
    - name: container_cpu_usage_seconds_total
      aggregation: "avg by (pod)"
      threshold: 0.8  # 80% CPU
      threshold_type: static
      window: 5m
      severity: high

    - name: container_memory_working_set_bytes
      aggregation: "avg by (pod)"
      threshold_type: dynamic  # Based on limits
      window: 5m
      severity: high

  check_interval: 60s  # Run every minute
  event_queue:
    redis_url: "redis://redis.monitoring-agents.svc:6379"
    stream: "monitoring-events"
  ```

- [ ] Implementation:
  - [ ] Agent runtime scaffold (use template from 3.3)
  - [ ] MCP client integration (Prometheus MCP)
  - [ ] Metrics query logic:
    ```python
    async def query_metric(self, metric_config):
        query = f"{metric_config['name']}{{{metric_config.get('labels', '')}}}"
        if metric_config.get('aggregation'):
            query = f"{metric_config['aggregation']}({query})"

        result = await self.prometheus_mcp.query_promql(
            query=query,
            time_range=metric_config['window']
        )
        return result
    ```
  - [ ] Anomaly detection implementation:
    ```python
    def detect_anomaly(self, current_value, metric_config):
        if metric_config['threshold_type'] == 'static':
            return current_value > metric_config['threshold']

        elif metric_config['threshold_type'] == 'dynamic':
            baseline = self.get_historical_baseline(metric_config)
            threshold = baseline * metric_config['baseline_multiplier']
            return current_value > threshold

        return False
    ```
  - [ ] Alert formatting and routing (publish to Redis stream)
  - [ ] OpenTelemetry tracing for agent execution

### 3.5.2 Trace Analysis Agent
**Location**: `agent-examples-local/agents/trace-analyzer/`

- [ ] Define agent purpose:
  - Continuously analyze traces for errors
  - Detect latency regressions
  - Identify service dependency issues

- [ ] Design agent logic:
  - [ ] Error trace detection and classification:
    - LLM errors (Phoenix): Tool failures, prompt errors, high token usage
    - Infrastructure errors (Tempo): Service failures, timeouts, network errors
  - [ ] Latency analysis (p50, p95, p99 tracking)
  - [ ] Service graph analysis (which service is failing)
  - [ ] Critical path analysis (where is time spent)

- [ ] Agent configuration:
  ```yaml
  agent_name: "trace-analyzer"

  mcp_servers:
    - phoenix-mcp  # LLM traces
    - tempo-mcp    # Infrastructure traces

  analysis_rules:
    # LLM trace errors (Phoenix)
    - type: llm_error_detection
      backend: phoenix
      services: ["*"]  # All agent services
      sample_rate: 1.0  # Sample all error traces
      error_patterns:
        - "tool execution failed"
        - "LLM API error"
        - "token limit exceeded"
      severity: high

    # LLM latency regression (Phoenix)
    - type: llm_latency_regression
      backend: phoenix
      services: ["correlation-rca-agent", "github-remediation-agent"]
      baseline_window: 24h
      threshold: 1.5  # 50% increase from baseline
      severity: medium

    # Infrastructure errors (Tempo)
    - type: infra_error_detection
      backend: tempo
      services: ["*"]
      sample_rate: 1.0
      error_patterns:
        - "connection refused"
        - "timeout"
        - "503 Service Unavailable"
      severity: critical

    # Infrastructure latency (Tempo)
    - type: infra_latency_regression
      backend: tempo
      services: ["checkout-service", "api-gateway"]
      baseline_window: 24h
      threshold: 2.0  # 100% increase (2x slower)
      severity: high

  check_interval: 60s
  event_queue:
    redis_url: "redis://redis.monitoring-agents.svc:6379"
    stream: "monitoring-events"
  ```

- [ ] Implementation tasks:
  - [ ] Agent runtime scaffold
  - [ ] MCP client integration (Phoenix MCP + Tempo MCP)
  - [ ] Trace query logic:
    ```python
    async def query_llm_errors(self):
        # Query Phoenix for LLM errors
        traces = await self.phoenix_mcp.find_llm_errors(
            time_range="5m",
            services=self.config['services']
        )
        return traces

    async def query_infra_errors(self):
        # Query Tempo for infrastructure errors
        traces = await self.tempo_mcp.find_errors(
            time_range="5m",
            services=self.config['services']
        )
        return traces
    ```
  - [ ] Error classification:
    ```python
    def classify_error(self, trace):
        if trace.get('openinference.span.kind') in ['CHAIN', 'LLM', 'TOOL', 'AGENT']:
            return 'llm_error'
        else:
            return 'infrastructure_error'
    ```
  - [ ] Latency baseline calculation (p95 over 24h)
  - [ ] Critical path analysis (longest span chain)
  - [ ] Event publishing to Redis stream

### 3.5.3 Log Analysis Agent
**Location**: `agent-examples-local/agents/log-analyzer/`

- [ ] Define agent purpose:
  - Query Loki for error/warning logs
  - Detect log patterns (stack traces, exceptions, panics)
  - Correlate log volume spikes with errors

- [ ] Agent configuration:
  ```yaml
  agent_name: "log-analyzer"

  mcp_servers:
    - loki-mcp

  analysis_rules:
    # Error log detection
    - type: error_log_detection
      query_template: '{namespace="monitoring-agents"} |= "ERROR" or "error"'
      time_range: 5m
      threshold: 10  # > 10 error logs in 5m
      severity: high

    # Exception patterns
    - type: exception_detection
      query_template: '{namespace="monitoring-agents"} |~ "Exception|Traceback|panic"'
      time_range: 5m
      threshold: 1  # Any exception is noteworthy
      severity: critical

    # Log volume spike
    - type: log_volume_spike
      query_template: 'count_over_time({namespace="monitoring-agents"}[5m])'
      baseline_multiplier: 3.0  # 3x normal volume
      severity: medium

  check_interval: 60s
  event_queue:
    redis_url: "redis://redis.monitoring-agents.svc:6379"
    stream: "monitoring-events"
  ```

- [ ] Implementation:
  - [ ] Agent runtime scaffold
  - [ ] MCP client integration (Loki MCP)
  - [ ] Log query and pattern detection
  - [ ] Stack trace extraction
  - [ ] Event publishing

### 3.5.4 Orchestrator Agent
**Location**: `agent-examples-local/agents/orchestrator/`

- [ ] Define agent purpose:
  - Subscribe to all detection events from monitoring agents
  - Deduplicate events (same issue, multiple detections)
  - Group related events (metric + trace + log for same service)
  - Prioritize by severity
  - Trigger correlation agent

- [ ] Agent configuration:
  ```yaml
  agent_name: "orchestrator"

  event_queue:
    redis_url: "redis://redis.monitoring-agents.svc:6379"
    input_stream: "monitoring-events"
    output_stream: "correlation-requests"
    consumer_group: "orchestrator-group"

  deduplication:
    time_window: 5m  # Events within 5m are considered same incident
    correlation_keys:
      - service_name
      - trace_id
      - metric_name

  grouping:
    time_window: 2m  # Group events within 2 minutes
    min_signals: 2   # At least 2 signals (metric+trace, trace+log, etc.)

  prioritization:
    severity_order: [critical, high, medium, low]
    deduplication_enabled: true
  ```

- [ ] Implementation:
  - [ ] Subscribe to Redis stream `monitoring-events`
  - [ ] Event deduplication logic (by correlation_id or service+time)
  - [ ] Event grouping logic (collect metric+trace+log for same service)
  - [ ] Priority queue implementation
  - [ ] Trigger correlation agent by publishing to `correlation-requests`
  - [ ] State tracking in Redis (active investigations)

### 3.5.5 Correlation & RCA Agent
**Location**: `agent-examples-local/agents/correlation-rca/`

- [ ] Define agent purpose:
  - Receive grouped events from orchestrator
  - Use Korrel8r to correlate signals
  - Query additional context from Prometheus/Phoenix/Tempo/Loki
  - LLM-based root cause analysis
  - Generate comprehensive issue reports

- [ ] Agent configuration:
  ```yaml
  agent_name: "correlation-rca"

  mcp_servers:
    - korrel8r-mcp
    - prometheus-mcp
    - phoenix-mcp
    - tempo-mcp
    - loki-mcp

  event_queue:
    redis_url: "redis://redis.monitoring-agents.svc:6379"
    input_stream: "correlation-requests"
    output_stream: "remediation-requests"
    consumer_group: "correlation-group"

  correlation:
    max_depth: 3  # Max correlation hops
    confidence_threshold: 0.7  # Min correlation confidence

  rca:
    llm_model: "gpt-4"
    llm_api_base: "http://ollama.kagenti-system.svc:11434/v1"
    llm_temperature: 0.2  # Low temperature for factual analysis
    max_tokens: 2000
  ```

- [ ] Implementation:
  - [ ] Subscribe to Redis stream `correlation-requests`
  - [ ] Correlation workflow:
    ```python
    async def correlate_signals(self, events):
        # 1. Extract trace_id from trace event
        trace_id = events['trace_error']['trace_id']

        # 2. Use Korrel8r to find related signals
        correlation_graph = await self.korrel8r_mcp.correlate_trace_to_logs(trace_id)

        # 3. Query additional context
        logs = await self.loki_mcp.query_logs_by_trace_id(trace_id)
        metrics = await self.prometheus_mcp.get_metric_range(
            metric="container_cpu_usage_seconds_total",
            filters={"pod": events['trace_error']['service']}
        )
        full_trace = await self.phoenix_mcp.get_llm_trace_by_id(trace_id)

        return {
            'trace': full_trace,
            'logs': logs,
            'metrics': metrics,
            'correlation_graph': correlation_graph
        }
    ```
  - [ ] LLM-based root cause analysis:
    ```python
    async def analyze_root_cause(self, correlated_data):
        prompt = f"""
        Analyze the following observability data to identify the root cause of an issue.

        **Trace Data**:
        {correlated_data['trace']}

        **Logs**:
        {correlated_data['logs']}

        **Metrics**:
        {correlated_data['metrics']}

        **Correlation Graph**:
        {correlated_data['correlation_graph']}

        Identify:
        1. The most likely root cause (with confidence 0-1)
        2. Issue type (infrastructure, application, platform)
        3. Affected components
        4. Recommended action

        Output JSON:
        {{
          "root_cause": "...",
          "confidence": 0.0-1.0,
          "issue_type": "infrastructure|application|platform",
          "affected_components": [...],
          "recommended_action": "..."
        }}
        """

        response = await self.llm_client.complete(prompt)
        return json.loads(response)
    ```
  - [ ] Publish to `remediation-requests` stream
  - [ ] OpenTelemetry tracing with full RCA context

### 3.5.6 GitHub Remediation Agent
**Location**: `agent-examples-local/agents/github-remediation/`

- [ ] Define agent purpose:
  - Receive root cause analysis from RCA agent
  - Classify issue and identify target repository
  - Generate remediation (YAML patch, code fix, or issue)
  - Create PR via GitHub MCP
  - Track created PRs to avoid duplicates

- [ ] Agent configuration:
  ```yaml
  agent_name: "github-remediation"

  mcp_servers:
    - github-mcp

  event_queue:
    redis_url: "redis://redis.monitoring-agents.svc:6379"
    input_stream: "remediation-requests"
    consumer_group: "remediation-group"

  repository_mapping:
    infrastructure:
      repo: "redhat-et/kagenti-demo-deployment"
      default_reviewers: ["platform-team"]
      branch_prefix: "agent-fix/infra"

    kagenti:
      repo: "redhat-et/kagenti-operator"
      default_reviewers: ["agent-team"]
      branch_prefix: "agent-fix/platform"

    agents:
      repo: "redhat-et/agent-examples-local"
      default_reviewers: ["agent-team"]
      branch_prefix: "agent-fix/agents"

  duplicate_detection:
    enabled: true
    lookback_window: 7d
    redis_key_prefix: "pr-tracking:"

  auto_merge: false  # Always require human review
  ```

- [ ] Implementation:
  - [ ] Subscribe to Redis stream `remediation-requests`
  - [ ] Issue classification:
    ```python
    def classify_issue(self, rca_result):
        if rca_result['issue_type'] == 'infrastructure':
            if 'resource' in rca_result['recommended_action'].lower():
                return 'infrastructure', 'resource_adjustment'
            elif 'deployment' in rca_result['recommended_action'].lower():
                return 'infrastructure', 'deployment_fix'

        elif rca_result['issue_type'] == 'platform':
            return 'kagenti', 'platform_issue'

        elif rca_result['issue_type'] == 'application':
            # Determine app repo from affected_components
            service = rca_result['affected_components'][0]
            return self.get_app_repo(service), 'application_fix'

        return None, None
    ```
  - [ ] Remediation generation:
    ```python
    async def generate_remediation(self, rca_result, issue_type, issue_subtype):
        if issue_subtype == 'resource_adjustment':
            # Generate YAML patch for resource limits
            yaml_patch = self.generate_resource_patch(rca_result)
            return yaml_patch

        elif issue_subtype == 'application_fix':
            # Use LLM to suggest code fix (if confident)
            code_fix = await self.generate_code_fix(rca_result)
            return code_fix

        else:
            # Create detailed issue for manual investigation
            return None
    ```
  - [ ] PR creation via GitHub MCP:
    ```python
    async def create_pr(self, repo, remediation, rca_result):
        # Check for duplicates
        if await self.pr_exists(repo, rca_result['correlation_id']):
            logger.info("PR already exists for this issue")
            return

        # Create branch
        branch_name = f"{self.config['branch_prefix']}-{rca_result['correlation_id']}"
        await self.github_mcp.create_branch(repo, branch_name)

        # Generate PR body
        pr_body = self.generate_pr_body(rca_result, remediation)

        # Create PR
        pr = await self.github_mcp.create_pull_request(
            repo=repo,
            title=f"Fix: {rca_result['root_cause']}",
            body=pr_body,
            branch=branch_name,
            files=remediation['files'],
            reviewers=self.config['repository_mapping'][repo]['default_reviewers']
        )

        # Track PR in Redis
        await self.track_pr(repo, rca_result['correlation_id'], pr['url'])

        logger.info(f"PR created: {pr['url']}")
    ```
  - [ ] Duplicate detection in Redis
  - [ ] PR tracking and state management

---

## Phase 4: Agent-Orchestration Deployment Considerations

**Status**: agent-orchestration is a POC project, NOT production-ready ⚠️

### 4.1 agent-orchestration Assessment

**Repository**: `/Users/ladas/Projects/OCTO/research/agent-orchestration`
**Latest Branch**: `main` (remote branches: `crd`, `kagent-integration`)

**What it provides**:
- Agent CRD for Kubernetes-native agent lifecycle
- Kubernetes-based service discovery for agents
- A2A protocol integration (agent cards at `/.well-known/agent.json`)
- Agent discovery via labels and annotations

**Example Agent CRD**:
```yaml
apiVersion: ai.openshift.io/v1
kind: Agent
metadata:
  name: metrics-monitor
  namespace: monitoring-agents
  labels:
    ai.openshift.io/agent.class: "a2a"
    ai.openshift.io/agent.name: "metrics-monitor"
  annotations:
    ai.openshift.io/agent.endpoint: "/.well-known/agent.json"
spec:
  class: "a2a"
  endpoint: "/.well-known/agent.json"
  sourceRef:
    kind: Deployment
    name: metrics-monitor-agent
    namespace: monitoring-agents
```

**Discovery Pattern**:
- Agents are labeled with `ai.openshift.io/agent.class: "a2a"`
- Agent Card exposed at `http://<agent-service>/.well-known/agent.json`
- Orchestrator queries Kubernetes API for all agents with label

### 4.2 Integration Decision

**Options**:

**Option A: Use agent-orchestration CRD** (NOT RECOMMENDED)
- ❌ POC-only project, not production-ready
- ❌ Additional CRD management overhead
- ❌ May conflict with Kagenti's agent system
- ✅ Kubernetes-native discovery

**Option B: Use Kagenti's native agent system** (RECOMMENDED ✅)
- ✅ Production-ready AgentBuild CRD
- ✅ Already integrated with Tekton
- ✅ ArgoCD GitOps workflow
- ✅ Platform operator manages lifecycle
- ❌ May not have built-in discovery (use ConfigMap)

**Option C: Hybrid approach**
- Use Kagenti AgentBuild for image builds
- Use agent-orchestration's discovery pattern (labels + agent cards)
- Deploy Agent CRDs via GitOps alongside Deployments
- Best of both worlds

**RECOMMENDATION**: **Option B** (Kagenti native) with manual discovery via ConfigMap
- Simpler, fewer moving parts
- Production-ready infrastructure
- Agent discovery via ConfigMap is explicit and traceable in Git
- Can adopt agent-orchestration later if it matures

### 4.3 Agent Discovery Strategy (Recommended)

Instead of agent-orchestration's Kubernetes API discovery, use **ConfigMap-based discovery**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: agent-discovery
  namespace: monitoring-agents
data:
  agents.yaml: |
    agents:
      - name: metrics-monitor
        service: metrics-monitor-agent.monitoring-agents.svc:8080
        type: monitoring
        capabilities: [query_metrics, detect_anomalies]

      - name: trace-analyzer
        service: trace-analyzer-agent.monitoring-agents.svc:8080
        type: monitoring
        capabilities: [query_traces, analyze_errors]

      - name: log-analyzer
        service: log-analyzer-agent.monitoring-agents.svc:8080
        type: monitoring
        capabilities: [query_logs, detect_patterns]

      - name: orchestrator
        service: orchestrator-agent.monitoring-agents.svc:8080
        type: orchestration
        capabilities: [coordinate, deduplicate, prioritize]

      - name: correlation-rca
        service: correlation-rca-agent.monitoring-agents.svc:8080
        type: analysis
        capabilities: [correlate, analyze_root_cause]

      - name: github-remediation
        service: github-remediation-agent.monitoring-agents.svc:8080
        type: remediation
        capabilities: [create_pr, create_issue, classify_issue]
```

**Benefits**:
- ✅ GitOps-friendly (ConfigMap in repo)
- ✅ Explicit and traceable
- ✅ No additional CRDs
- ✅ Easy to update (commit + sync)
- ✅ Works with any orchestration logic

### 4.4 Optional: agent-orchestration for Future

If agent-orchestration matures, can migrate to it later:

- [ ] Monitor agent-orchestration project for production readiness
- [ ] Test CRD installation in dev environment
- [ ] Evaluate benefits vs ConfigMap approach
- [ ] If adopting:
  - [ ] Deploy agent-orchestration operator
  - [ ] Create Agent CRs for all monitoring agents
  - [ ] Update discovery logic in orchestrator agent
  - [ ] Migrate from ConfigMap to Kubernetes API discovery

**For now**: Skip agent-orchestration, use Kagenti + ConfigMap ✅

---

## Phase 5: GitOps Deployment Setup

### 5.1 GitOps Integration (kagenti-demo-deployment)
**Location**: `kagenti-demo-deployment/components/03-applications/agents/monitoring/`

Following CLAUDE.md patterns and existing component structure.

- [ ] Study existing kagenti-demo-deployment structure:
  - [ ] Review `components/03-applications/agents/` (existing agent deployments)
  - [ ] Review sync waves (Wave 30 for agents)
  - [ ] Review Kustomize patterns
  - [ ] Review ArgoCD application structure in `argocd/applications/base/`

- [ ] Create monitoring agents component structure:
  ```
  components/03-applications/agents/monitoring/
  ├── kustomization.yaml
  ├── namespace.yaml
  ├── configmaps/
  │   ├── agent-discovery.yaml
  │   ├── mcp-server-endpoints.yaml
  │   └── observability-config.yaml
  ├── secrets/
  │   └── github-token.yaml  # Sealed secret or external secret
  ├── mcp-servers/
  │   ├── prometheus-mcp.yaml
  │   ├── phoenix-mcp.yaml
  │   ├── tempo-mcp.yaml
  │   ├── loki-mcp.yaml
  │   ├── korrel8r-mcp.yaml
  │   └── github-mcp.yaml
  ├── agent-builds/
  │   ├── metrics-monitor-build.yaml
  │   ├── trace-analyzer-build.yaml
  │   ├── log-analyzer-build.yaml
  │   ├── orchestrator-build.yaml
  │   ├── correlation-rca-build.yaml
  │   └── github-remediation-build.yaml
  ├── agents/
  │   ├── metrics-monitor.yaml
  │   ├── trace-analyzer.yaml
  │   ├── log-analyzer.yaml
  │   ├── orchestrator.yaml
  │   ├── correlation-rca.yaml
  │   └── github-remediation.yaml
  └── redis/
      ├── deployment.yaml
      ├── service.yaml
      └── pvc.yaml
  ```

- [ ] Create namespace with Istio injection:
  ```yaml
  # namespace.yaml
  apiVersion: v1
  kind: Namespace
  metadata:
    name: monitoring-agents
    labels:
      istio-injection: enabled
      component: monitoring
  ```

- [ ] Create ArgoCD application:
  ```yaml
  # argocd/applications/base/monitoring-agents.yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: monitoring-agents
    namespace: argocd
    annotations:
      argocd.argoproj.io/sync-wave: "30"  # After observability (wave 20)
  spec:
    project: default
    source:
      repoURL: https://github.com/redhat-et/kagenti-demo-deployment
      targetRevision: main
      path: components/03-applications/agents/monitoring
    destination:
      server: https://kubernetes.default.svc
      namespace: monitoring-agents
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
  ```

### 5.2 Automatic Infrastructure Connection

**Strategy**: ConfigMap + Kubernetes Service Discovery

- [ ] Create MCP server endpoints ConfigMap:
  ```yaml
  # configmaps/mcp-server-endpoints.yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: mcp-server-endpoints
    namespace: monitoring-agents
  data:
    prometheus.url: "http://prometheus-mcp.monitoring-agents.svc:8080"
    phoenix.url: "http://phoenix-mcp.monitoring-agents.svc:8080"
    tempo.url: "http://tempo-mcp.monitoring-agents.svc:8080"
    loki.url: "http://loki-mcp.monitoring-agents.svc:8080"
    korrel8r.url: "http://korrel8r-mcp.monitoring-agents.svc:8080"
    github.url: "http://github-mcp.monitoring-agents.svc:8080"
  ```

- [ ] Create observability endpoints ConfigMap:
  ```yaml
  # configmaps/observability-config.yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: observability-config
    namespace: monitoring-agents
  data:
    otel_collector.endpoint: "http://otel-collector.observability.svc.cluster.local:4317"
    prometheus.endpoint: "http://prometheus.observability.svc:9090"
    phoenix.endpoint: "http://phoenix.observability.svc:6006"
    tempo.endpoint: "http://tempo-query-frontend.observability.svc:3200"
    loki.endpoint: "http://loki-query-frontend.observability.svc:3100"
    korrel8r.endpoint: "http://korrel8r.observability.svc:8080"
    redis.endpoint: "redis://redis.monitoring-agents.svc:6379"
  ```

- [ ] Inject ConfigMaps into agent pods:
  ```yaml
  # Example agent deployment
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: metrics-monitor-agent
    namespace: monitoring-agents
  spec:
    template:
      spec:
        containers:
          - name: agent
            image: localhost:5000/metrics-monitor:v0.1.0
            envFrom:
              - configMapRef:
                  name: mcp-server-endpoints
              - configMapRef:
                  name: observability-config
            env:
              - name: OTEL_SERVICE_NAME
                value: "metrics-monitor"
              - name: AGENT_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: metadata.name
  ```

### 5.3 Secrets Management

- [ ] Create GitHub token secret (Sealed Secret or External Secret):
  ```yaml
  # secrets/github-token.yaml (use SealedSecret in production)
  apiVersion: v1
  kind: Secret
  metadata:
    name: github-api-token
    namespace: monitoring-agents
  type: Opaque
  stringData:
    token: "<github-personal-access-token>"
  ```

- [ ] Mount secrets into agents:
  ```yaml
  containers:
    - name: agent
      volumeMounts:
        - name: github-token
          mountPath: /etc/secrets/github
          readOnly: true
  volumes:
    - name: github-token
      secret:
        secretName: github-api-token
  ```

- [ ] Add RBAC for secret access (if needed):
  ```yaml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: monitoring-agent
    namespace: monitoring-agents
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    name: secret-reader
    namespace: monitoring-agents
  rules:
    - apiGroups: [""]
      resources: ["secrets"]
      resourceNames: ["github-api-token"]
      verbs: ["get"]
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
  metadata:
    name: agent-secret-reader
    namespace: monitoring-agents
  subjects:
    - kind: ServiceAccount
      name: monitoring-agent
  roleRef:
    kind: Role
    name: secret-reader
    apiGroup: rbac.authorization.k8s.io
  ```

### 5.4 GitOps Workflow

Following CLAUDE.md GitOps patterns:

```bash
# 1. Make changes to monitoring agents in Git
vim components/03-applications/agents/monitoring/agents/metrics-monitor.yaml

# 2. Validate syntax BEFORE committing
kustomize build components/03-applications/agents/monitoring/ > /dev/null

# 3. Commit and push
git add components/03-applications/agents/monitoring/
git commit -m ":rocket: Update metrics-monitor agent configuration"
git push origin main

# 4. Sync from Git (ArgoCD auto-syncs, but can trigger manually)
argocd app sync monitoring-agents \
  --port-forward --port-forward-namespace argocd --grpc-web

# 5. Validate deployment
./scripts/platform-status.sh

# 6. Check agent pods
kubectl get pods -n monitoring-agents

# 7. Check agent logs
kubectl logs -n monitoring-agents deployment/metrics-monitor-agent --tail=100

# 8. Check agent traces in Phoenix
open https://phoenix.localtest.me:9443
```

### 5.5 Deployment Order (Sync Waves)

ArgoCD sync wave annotations ensure correct deployment order:

```
Wave 0:  Infrastructure (Gateway API, cert-manager)
Wave 5:  Istio (base, istiod, config)
Wave 10: Platform (Keycloak, operators, UI)
Wave 15: Tekton (pipelines for AgentBuild)
Wave 20: Observability (Prometheus, Tempo, Phoenix, Loki, Korrel8r) ✅ ALREADY EXISTS
Wave 25: MCP Servers (Prometheus MCP, Phoenix MCP, etc.) ← NEW
Wave 30: Agents (Monitoring agents, orchestrator, etc.) ← NEW
```

- [ ] Add sync wave annotations to MCP servers:
  ```yaml
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "25"
  ```

- [ ] Add sync wave annotations to agents:
  ```yaml
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "30"
  ```

---

## Phase 6: Testing & Validation

### 6.1 MCP Server Testing
- [ ] Unit tests for each MCP tool
- [ ] Integration tests against real backends (Prometheus, Phoenix, Tempo, Loki, Korrel8r, GitHub)
- [ ] Load testing for concurrent agent requests
- [ ] Error handling and retry logic testing

### 6.2 Agent Testing
- [ ] Unit tests for agent logic
- [ ] Integration tests with MCP servers
- [ ] End-to-end tests:
  - [ ] Inject synthetic issue (e.g., increase error rate in test service)
  - [ ] Verify metrics agent detects it
  - [ ] Verify trace analyzer detects errors
  - [ ] Verify log analyzer finds error logs
  - [ ] Verify orchestrator groups events
  - [ ] Verify correlation agent uses Korrel8r correctly
  - [ ] Verify GitHub agent creates PR in test repo
  - [ ] Validate PR content accuracy (evidence, RCA, fix)

### 6.3 Chaos Testing
- [ ] Test agent behavior during infrastructure failures:
  - [ ] Prometheus unavailable
  - [ ] Phoenix/Tempo slow or unavailable
  - [ ] Loki query timeout
  - [ ] Korrel8r down
  - [ ] GitHub API rate limited
  - [ ] Redis stream unavailable
- [ ] Verify graceful degradation and recovery
- [ ] Verify retry logic works correctly
- [ ] Verify event queue durability (Redis stream persistence)

### 6.4 Accuracy Validation
- [ ] Run agents on historical incidents (use past traces/metrics/logs)
- [ ] Measure:
  - [ ] Detection rate (did agent catch the issue?)
  - [ ] False positive rate (alerts for non-issues)
  - [ ] Time to detection (how fast did agent detect?)
  - [ ] Root cause accuracy (was LLM analysis correct?)
  - [ ] PR quality (human review of generated PRs)
  - [ ] Correlation accuracy (did Korrel8r find correct signals?)

---

## Phase 7: Documentation & Runbooks

### 7.1 Architecture Documentation
- [ ] Create system architecture diagram (monitoring agents + MCP servers + observability stack)
- [ ] Document agent communication flow (scheduled → events → correlation → remediation)
- [ ] Document MCP server APIs (tools, endpoints, authentication)
- [ ] Document deployment architecture (GitOps, sync waves, namespaces)
- [ ] Document RCA workflow (detection → orchestration → correlation → analysis → PR)

### 7.2 Operational Runbooks
- [ ] Agent deployment guide (using AgentBuild CRD)
- [ ] MCP server deployment guide
- [ ] Troubleshooting guide:
  - Agent not detecting issues (check queries, check MCP server connectivity)
  - MCP server connection failures (check service discovery, check endpoints)
  - GitHub PR creation failures (check API token, check permissions)
  - Korrel8r integration issues (check stores, check correlation rules)
  - Event queue issues (check Redis, check stream existence)
- [ ] Monitoring the monitors (Prometheus alerts for agent failures)
- [ ] Recovery procedures (restart agents, clear Redis streams, rollback deployments)

### 7.3 Development Guides
- [ ] How to add new MCP tools (extend existing MCP servers)
- [ ] How to create new agents (use template from Phase 3.3)
- [ ] How to update correlation rules (modify Korrel8r config)
- [ ] How to add new repository mappings (update GitHub remediation agent config)
- [ ] How to build agents from external repos (use build scripts from Phase 3.2)

---

## Phase 8: Rollout Strategy

### 8.1 Phased Rollout

- [ ] **Phase 0: Prerequisites** (DONE ✅)
  - Observability stack deployed (Prometheus, Tempo, Phoenix, Loki, Korrel8r)
  - AgentBuild CRD and Tekton pipelines deployed
  - Container registry available

- [ ] **Phase 1: MCP Server Development** (4 weeks)
  - Build Prometheus MCP server
  - Build Phoenix/Tempo MCP server (dual backend)
  - Build Loki MCP server
  - Build Korrel8r MCP server
  - Build GitHub MCP server
  - Test all MCP servers against deployed backends

- [ ] **Phase 2: MCP Server Deployment** (1 week)
  - Deploy MCP servers to monitoring-agents namespace (Wave 25)
  - Verify connectivity to observability stack
  - Test MCP tools via CLI/Postman

- [ ] **Phase 3: Build Monitoring Agents** (4 weeks)
  - Build metrics monitor agent (use AgentBuild CRD)
  - Build trace analyzer agent
  - Build log analyzer agent
  - Build orchestrator agent
  - Build correlation RCA agent
  - Build GitHub remediation agent

- [ ] **Phase 4: Deploy Monitoring Agents (Read-Only)** (1 week)
  - Deploy agents to monitoring-agents namespace (Wave 30)
  - **Read-only mode**: Agents detect issues but DON'T create PRs
  - Agents log what PRs would be created
  - Verify detection accuracy
  - Tune thresholds and correlation rules

- [ ] **Phase 5: Enable GitHub Agent (Dry-Run)** (1 week)
  - Enable GitHub remediation agent in **dry-run mode**
  - Agent logs PR details but doesn't create them
  - Review logged PRs for quality
  - Identify false positives
  - Tune issue classification logic

- [ ] **Phase 6: Enable GitHub Agent (Issue Creation)** (1 week)
  - Enable GitHub agent to create **issues only** (not PRs)
  - Issues created in test repository
  - Human reviews issues for accuracy
  - Measure issue quality and relevance

- [ ] **Phase 7: Enable GitHub Agent (PR Creation with Review)** (2 weeks)
  - Enable GitHub agent to create PRs (requires human review before merge)
  - PRs created in kagenti-demo-deployment (infrastructure fixes)
  - Team reviews PRs, provides feedback
  - Measure PR quality, time saved

- [ ] **Phase 8: Full Production Rollout** (Ongoing)
  - Monitoring agents running 24/7
  - Full monitoring and alerting enabled
  - Continuous tuning based on feedback
  - Expand to more repositories (application repos)

### 8.2 Observability for Agents
- [ ] Add Prometheus metrics for agent performance:
  - Detection latency (time from issue occurrence to detection)
  - Query success rate (% of successful MCP queries)
  - PR creation success rate (% of successful PR creations)
  - Agent execution time (duration of each agent run)
  - Event queue depth (Redis stream backlog)
  - Correlation accuracy (manual validation)

- [ ] Add logging for agent decisions:
  - Structured logging (JSON format)
  - Log all detections with correlation_id
  - Log correlation results
  - Log RCA reasoning (LLM responses)
  - Log PR creation attempts

- [ ] Create Grafana dashboards for agent health:
  - Agent execution rate
  - Detection rate (issues found per hour)
  - Correlation success rate
  - PR creation rate
  - Agent error rate
  - Event queue metrics

- [ ] Set up Prometheus alerts for agent failures:
  - Alert: Agent pod CrashLoopBackOff
  - Alert: Agent not running scheduled checks
  - Alert: MCP server connection failures
  - Alert: Event queue backlog growing
  - Alert: Correlation agent timeout
  - Alert: GitHub API rate limit exceeded

---

## Open Questions & Decisions

### Critical Decisions ✅ ALL RESOLVED

1. ~~**Korrel8r Deployment**: Deploy correl8r or implement correlation in agents?~~
   - ✅ **DECIDED**: Korrel8r is ALREADY DEPLOYED at `:8080` ✅
   - No need to deploy, just integrate via Korrel8r MCP

2. ~~**Tracing Backend**: Which tracing system?~~
   - ✅ **DECIDED**: Dual backend (Phoenix + Tempo)
   - Phoenix for LLM traces (CHAIN, LLM, TOOL, AGENT)
   - Tempo for infrastructure traces
   - OTEL Collector handles exclusive routing

3. ~~**Agent Orchestration**: Event-driven, scheduled, or hybrid?~~
   - ✅ **DECIDED**: Hybrid approach
   - Scheduled agents for monitoring (metrics, traces, logs)
   - Event-driven for correlation and remediation
   - Redis streams for event queue

4. ~~**Infrastructure Discovery**: Service discovery method?~~
   - ✅ **DECIDED**: Kubernetes Service Discovery + ConfigMap
   - MCP servers as k8s services
   - ConfigMap for endpoint configuration
   - Simple, GitOps-friendly, no additional CRDs

5. ~~**Kubernetes Access**: Do agents need direct k8s API access?~~
   - ✅ **DECIDED**: NO direct k8s access
   - Agents query only monitoring tools (Prometheus, Phoenix, Tempo, Loki, Korrel8r)
   - Infrastructure changes via PRs to kagenti-demo-deployment

6. ~~**Agent Build System**: How to build agent images?~~
   - ✅ **DECIDED**: AgentBuild CRD (Kagenti platform)
   - Production-ready, Tekton-based builds
   - Local container registry
   - GitOps workflow

7. ~~**agent-orchestration Integration**: Use agent-orchestration CRDs?~~
   - ✅ **DECIDED**: NO (POC-only, not production-ready)
   - Use Kagenti native agent system
   - ConfigMap-based discovery
   - Can adopt agent-orchestration later if it matures

---

## Success Metrics

### Operational Metrics
- [ ] Mean time to detection (MTTD): How fast do agents detect issues?
  - **Target**: < 2 minutes from issue occurrence
- [ ] Mean time to PR creation (MTTPR): How fast is PR created after detection?
  - **Target**: < 5 minutes from detection
- [ ] Detection accuracy: Percentage of real issues caught
  - **Target**: > 95% of critical issues detected
- [ ] False positive rate: Percentage of false alarms
  - **Target**: < 10% false positive rate
- [ ] PR quality score: Human review ratings of agent-generated PRs
  - **Target**: > 80% of PRs approved after review
- [ ] Auto-remediation rate: Percentage of issues fixed without human intervention
  - **Target**: > 30% of infrastructure issues auto-fixed (after mature phase)
- [ ] Correlation accuracy: Correctness of Korrel8r-based correlations
  - **Target**: > 90% correlation accuracy

### Business Metrics
- [ ] Reduction in manual incident investigation time
  - **Target**: 50% reduction in time spent manually correlating signals
- [ ] Reduction in mean time to resolution (MTTR)
  - **Target**: 30% reduction in MTTR for infrastructure issues
- [ ] Increase in proactive issue detection (caught before user impact)
  - **Target**: 40% of issues caught proactively
- [ ] Developer satisfaction with agent-generated PRs
  - **Target**: > 4.0/5.0 satisfaction score

---

## Timeline Estimate

### Phase Durations
- **Phase 0 (Infrastructure Assessment)**: ✅ DONE (infrastructure already deployed)
- **Phase 1 (Architecture & Design)**: 1-2 weeks (design complete, update with latest research)
- **Phase 1.5 (Phoenix Hardening)**: 1 week (security, resources, monitoring)
- **Phase 2 (MCP Development)**: 4-5 weeks (5 MCP servers in parallel)
- **Phase 3 (Agent Development)**: 4-6 weeks (6 agents, can parallelize)
- **Phase 3.5 (Agent Build Process)**: 1 week (scripts, templates, documentation)
- **Phase 4 (agent-orchestration)**: SKIPPED (using Kagenti native)
- **Phase 5 (GitOps Setup)**: 2 weeks (manifests, ArgoCD apps, testing)
- **Phase 6 (Testing)**: 2-3 weeks (integration tests, chaos tests, accuracy validation)
- **Phase 7 (Documentation)**: 1-2 weeks (architecture docs, runbooks, dev guides)
- **Phase 8 (Rollout)**: 6-8 weeks (phased rollout, read-only → dry-run → issues → PRs)

**Total**: 22-30 weeks (5.5-7.5 months)

### Parallelization Opportunities
- MCP servers can be developed in parallel (5 developers = 1 week per MCP)
- Agents can be developed in parallel (6 developers = 1 week per agent)
- Documentation can be written alongside development
- Testing can start during development (integration tests for each MCP/agent)

### Fast Track (With full team)
- **Week 1-2**: Architecture design + Phoenix hardening
- **Week 3-6**: MCP server development (parallel) + Build scripts
- **Week 7-8**: MCP server deployment + testing
- **Week 9-14**: Agent development (parallel)
- **Week 15-16**: Agent deployment + GitOps setup
- **Week 17-19**: Integration testing + chaos testing
- **Week 20**: Documentation
- **Week 21-28**: Phased rollout (read-only → dry-run → issues → PRs)

**Fast Track Total**: 28 weeks (7 months) with 8-10 developers

---

## Next Steps

### Immediate Actions (Week 1)
1. ✅ **Complete infrastructure assessment** (DONE - Korrel8r discovered!)
2. ✅ **Make key architectural decisions** (ALL DECIDED)
3. [ ] **Set up project structure** in agent-examples-local:
   ```bash
   mkdir -p agent-examples-local/{mcp,agents}/{prometheus-mcp,phoenix-mcp,tempo-mcp,loki-mcp,korrel8r-mcp,github-mcp}
   mkdir -p agent-examples-local/agents/{metrics-monitor,trace-analyzer,log-analyzer,orchestrator,correlation-rca,github-remediation}
   mkdir -p agent-examples-local/agents/_template
   ```
4. [ ] **Choose technology stack** for MCP servers:
   - Recommendation: **Python** (better LLM/AI library support, simpler for prototyping)
   - Alternative: TypeScript (if team prefers, better for web services)
5. [ ] **Identify team members** for each workstream:
   - MCP servers: 5 developers (1 per MCP server)
   - Agents: 6 developers (1 per agent)
   - DevOps/GitOps: 1-2 engineers
   - Testing: 1-2 QA engineers
6. [ ] **Set up development environment** and CI/CD:
   - Local Kind cluster for testing
   - GitHub Actions for MCP/agent image builds
   - Pre-commit hooks for linting

### Week 1 Tasks
1. [ ] Finalize architecture design (update diagrams with latest research)
2. [ ] Create project scaffolding (directories, templates, Dockerfile)
3. [ ] Set up development environment (local cluster, OTEL Collector, MCP test harness)
4. [ ] Begin Prometheus MCP server development (highest priority)
5. [ ] Begin GitHub MCP server development (for early PR testing)
6. [ ] Create build scripts for AgentBuild CRD generation
7. [ ] Harden Phoenix deployment (secrets, resource limits, monitoring)

### Quick Win (MVP in 6 weeks)
Minimal viable system:
- **Week 1-2**: Prometheus MCP server + GitHub MCP server
- **Week 3-4**: Simple metrics monitoring agent (static thresholds only)
- **Week 4-5**: Simple GitHub remediation agent (creates issues, not PRs)
- **Week 5-6**: Deploy to monitoring-agents namespace, test end-to-end

**Value**: Proves the concept, provides immediate value (automated issue creation), builds confidence

---

## Notes
- This is a complex, multi-month project - plan for iterations ✅
- Start simple, add sophistication over time ✅
- Prioritize reliability over features ✅
- Get human feedback early and often on PR quality ✅
- Consider gradual rollout to build confidence ✅
- Monitor agent performance closely in early stages ✅
- **CRITICAL**: Korrel8r is already deployed - simplifies correlation! ✅
- **CRITICAL**: Phoenix + Tempo dual backend already configured - use both! ✅
- **CRITICAL**: AgentBuild CRD exists - use for production builds! ✅
- **CRITICAL**: agent-orchestration is POC - skip for now, use Kagenti native ✅
- **Follow CLAUDE.md GitOps patterns** for all infrastructure changes ✅
