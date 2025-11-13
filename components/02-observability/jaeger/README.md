# Jaeger - Infrastructure Tracing Component

## Overview

Jaeger provides **infrastructure-level distributed tracing** for the Kagenti platform. It works alongside Phoenix to provide complete observability:

| Backend | Scope | Traces | Users |
|---------|-------|--------|-------|
| **Jaeger** | Infrastructure | Istio service mesh<br>Redis, PostgreSQL<br>HTTP requests<br>Kubernetes services | Platform team<br>SREs<br>DevOps |
| **Phoenix** | Application/Agents | Agent execution<br>LLM calls<br>MCP tool usage<br>OpenInference traces | Data scientists<br>Developers<br>Users |

## Architecture

### Two-Tier Tracing System

```
┌─────────────────────────────────────────────────┐
│         Instrumented Services                    │
│  (Istio, Redis, PostgreSQL, Agents, etc.)       │
└────────────────┬────────────────────────────────┘
                 │
                 ↓
         OTEL Collector (Routing)
                 │
    ┌────────────┴────────────┐
    │                         │
    ↓                         ↓
┌─────────┐           ┌──────────────┐
│ Jaeger  │           │   Phoenix    │
│         │           │              │
│ Standard│           │ OpenInference│
│ OTLP    │           │ traces       │
│ traces  │           │              │
└─────────┘           └──────────────┘
```

### Trace Routing Logic

The OTEL Collector routes traces based on instrumentation type:

```yaml
# Simplified routing logic
if span has "openinference.span.kind" attribute:
  → Send to Phoenix (agent/LLM traces)
else:
  → Send to Jaeger (infrastructure traces)
```

## Deployment

### Current Deployment: All-in-One

For development and staging environments, Jaeger is deployed as an **all-in-one** image containing:
- Collector (trace ingestion)
- Query service (UI and API)
- In-memory storage

**Limitations**:
- ⚠️ In-memory storage (traces lost on restart)
- ⚠️ Limited to 50,000 traces
- ⚠️ Single replica (no HA)

### Production Deployment: Separate Components

For production, consider deploying Jaeger with:
- **Storage**: Elasticsearch, Cassandra, or Kafka
- **Collector**: Scaled independently (2+ replicas)
- **Query**: Scaled independently (2+ replicas)
- **Ingester**: (if using Kafka)

See [Production Deployment](#production-deployment-guide) section below.

## Configuration

### Sampling Strategy

Defined in `jaeger-sampling-config` ConfigMap:

```json
{
  "service_strategies": [
    {
      "service": "istio-ingressgateway",
      "type": "probabilistic",
      "param": 0.5  // 50% of ingress traces
    },
    {
      "service": "redis",
      "type": "probabilistic",
      "param": 1.0  // 100% of Redis traces (always trace)
    },
    {
      "service": "postgres",
      "type": "probabilistic",
      "param": 1.0  // 100% of PostgreSQL traces
    }
  ],
  "default_strategy": {
    "type": "probabilistic",
    "param": 0.1  // 10% default sampling for other services
  }
}
```

**Adjust sampling based on**:
- Trace volume (lower param if too many traces)
- Storage capacity
- Query performance

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 4317 | gRPC | OTLP gRPC (recommended for OTEL Collector) |
| 4318 | HTTP | OTLP HTTP |
| 9411 | HTTP | Zipkin compatible endpoint |
| 14250 | gRPC | Jaeger native gRPC |
| 14268 | HTTP | Jaeger native Thrift |
| 16686 | HTTP | UI and Query API |
| 14269 | HTTP | Admin, health, metrics |

## Access

### Local (Kind)

```bash
# Access Jaeger UI
open http://jaeger.localtest.me:8080

# Or port-forward
kubectl port-forward -n observability svc/jaeger-query 16686:16686
open http://localhost:16686
```

### Production

Access via configured ingress/route with **Keycloak authentication** (see [Authentication](#authentication) section).

## Usage

### Query Traces

#### Via UI

1. Open Jaeger UI
2. Select service from dropdown (e.g., `istio-ingressgateway`, `redis`)
3. Click "Find Traces"
4. Click trace ID to view detailed trace

#### Via API

```bash
# Search traces for a service
curl "http://jaeger-query.observability.svc:16686/api/traces?service=redis&limit=10"

# Get specific trace by ID
curl "http://jaeger-query.observability.svc:16686/api/traces/<trace-id>"
```

### Integration with Monitoring Agents

The monitoring agents will use a **Jaeger MCP Server** to query traces:

```python
# Example: Query Jaeger for error traces
from jaeger_mcp import JaegerMCP

jaeger = JaegerMCP(endpoint="http://jaeger-query.observability.svc:16686")

# Find traces with errors in last 5 minutes
error_traces = jaeger.query_traces(
    service="redis",
    tags={"error": "true"},
    lookback="5m"
)

for trace in error_traces:
    print(f"Trace ID: {trace.trace_id}")
    print(f"Error: {trace.error_message}")
```

## Monitoring

### Prometheus Metrics

Jaeger exposes metrics on port `14269`:

```bash
# View metrics
kubectl port-forward -n observability svc/jaeger-query 14269:14269
curl http://localhost:14269/metrics
```

**Key metrics**:
- `jaeger_collector_traces_received_total` - Traces received by collector
- `jaeger_collector_traces_saved_total` - Traces successfully saved
- `jaeger_collector_traces_rejected_total` - Traces rejected (invalid)
- `jaeger_query_requests_total` - Query API requests
- `jaeger_storage_queries_total` - Storage backend queries

### Alerts

Recommended Prometheus alerts:

```yaml
groups:
- name: jaeger
  rules:
  - alert: JaegerCollectorDown
    expr: up{job="jaeger-collector"} == 0
    for: 5m
    annotations:
      summary: "Jaeger collector is down"

  - alert: JaegerHighTraceRejectionRate
    expr: rate(jaeger_collector_traces_rejected_total[5m]) > 0.05
    for: 5m
    annotations:
      summary: "Jaeger is rejecting >5% of traces"

  - alert: JaegerStorageFull
    expr: jaeger_storage_utilization > 0.9
    for: 10m
    annotations:
      summary: "Jaeger storage is >90% full"
```

## Authentication

### Development (Kind/K3s)

No authentication - direct access via HTTPRoute.

### Production (OpenShift)

Jaeger UI should be protected with **Keycloak OIDC** via **OAuth2 Proxy**:

1. **Create Keycloak client** in `kubernetes` realm:
   - Client ID: `jaeger`
   - Access Type: `confidential`
   - Valid Redirect URIs: `https://jaeger.your-domain.com/oauth2/callback`

2. **Deploy OAuth2 Proxy** in front of Jaeger:
   ```yaml
   # See components/infrastructure/oauth2-proxy/jaeger-oauth2-proxy.yaml
   ```

3. **Update HTTPRoute** to point to OAuth2 Proxy instead of Jaeger directly

## Troubleshooting

### No Traces Appearing

1. **Check OTEL Collector is sending to Jaeger**:
   ```bash
   kubectl logs -n observability -l app=otel-collector | grep jaeger
   ```

2. **Check Jaeger collector is receiving traces**:
   ```bash
   kubectl logs -n observability -l app=jaeger | grep "spans received"
   ```

3. **Verify sampling rate**:
   - Check `jaeger-sampling-config` ConfigMap
   - Ensure sampling param > 0

4. **Check service instrumentation**:
   ```bash
   # Ensure services are instrumented with OpenTelemetry
   kubectl get pod -n <namespace> -o yaml | grep -i otel
   ```

### Jaeger Pod Crashes

1. **Check memory limits**:
   ```bash
   kubectl describe pod -n observability -l app=jaeger
   # Look for OOMKilled
   ```

2. **Increase memory limit** if needed:
   ```yaml
   # In environment-specific patch
   resources:
     limits:
       memory: 4Gi
   ```

3. **Reduce trace retention** (in-memory mode):
   ```yaml
   env:
   - name: MEMORY_MAX_TRACES
     value: "25000"  # Reduce from 50000
   ```

### High Latency in Queries

1. **Check storage backend** (if using external storage)

2. **Reduce lookback window**:
   - Query last 1 hour instead of 24 hours

3. **Add indexes** (if using Elasticsearch):
   ```bash
   # Check Elasticsearch index size
   curl "http://elasticsearch:9200/_cat/indices/jaeger*?v"
   ```

## Production Deployment Guide

### Option 1: Jaeger Operator (Recommended)

Deploy using Jaeger Operator for automated management:

```bash
# Install Jaeger Operator
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/latest/download/jaeger-operator.yaml

# Create Jaeger instance with Elasticsearch
kubectl apply -f - <<EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: jaeger-prod
  namespace: observability
spec:
  strategy: production
  storage:
    type: elasticsearch
    options:
      es:
        server-urls: http://elasticsearch:9200
  query:
    replicas: 2
  collector:
    replicas: 3
  ingress:
    enabled: true
    hosts:
    - jaeger.your-domain.com
EOF
```

### Option 2: Helm Chart

```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm install jaeger jaegertracing/jaeger \
  --namespace observability \
  --set provisionDataStore.cassandra=true \
  --set collector.replicaCount=3 \
  --set query.replicaCount=2
```

### Storage Backend Comparison

| Backend | Pros | Cons | Recommended For |
|---------|------|------|-----------------|
| **Elasticsearch** | Full-text search<br>Grafana integration<br>Mature | Complex setup<br>Resource heavy | Large deployments<br>Long retention |
| **Cassandra** | High write throughput<br>Scalable | Complex ops<br>No full-text search | Very high volume |
| **Kafka** | Stream processing<br>Replay capability | Requires Kafka cluster | Real-time processing |
| **Badger** | Simple<br>No dependencies | Limited scaling | Small deployments |

## Integration with Phoenix

### Clear Separation

| Question | Jaeger | Phoenix |
|----------|--------|---------|
| "Why is Redis slow?" | ✅ Check here | ❌ |
| "Why did agent timeout?" | ✅ Check infra traces | ✅ Check agent traces |
| "How many tokens did LLM use?" | ❌ | ✅ Check here |
| "Which service called Redis?" | ✅ Service graph | ❌ |
| "What tools did agent call?" | ❌ | ✅ Tool trace |

### Correlation Workflow

For monitoring agents to correlate infrastructure and application traces:

1. **Agent detects timeout** in Phoenix trace
2. **Query Jaeger** for infrastructure traces in same time window
3. **Find root cause**: Redis trace shows 5s latency
4. **Create GitHub issue** with evidence from both backends

## Data Retention

### Current (In-Memory)

- Retention: Until pod restart or 50,000 traces reached
- Oldest traces evicted when limit reached

### Production (External Storage)

Configure retention based on storage backend:

**Elasticsearch**:
```yaml
storage:
  options:
    es:
      max-span-age: 168h  # 7 days
```

**Cassandra**:
```yaml
storage:
  options:
    cassandra:
      span-store-ttl: 604800  # 7 days in seconds
```

## Cost Optimization

### Sampling

Aggressive sampling reduces costs:

```json
{
  "default_strategy": {
    "type": "probabilistic",
    "param": 0.01  // Sample only 1% of traces
  }
}
```

### Retention

Short retention for infrastructure traces (7-14 days):
- Infrastructure traces are high volume
- Recent traces are most valuable
- Use Phoenix for long-term agent trace retention

### Storage

- **Development**: In-memory (free)
- **Staging**: Badger (local disk, cheap)
- **Production**: Elasticsearch with lifecycle policies (archive old data to S3)

## References

- **Jaeger Documentation**: https://www.jaegertracing.io/docs/
- **Jaeger Operator**: https://github.com/jaegertracing/jaeger-operator
- **OpenTelemetry Collector**: https://opentelemetry.io/docs/collector/
- **Jaeger Performance Tuning**: https://www.jaegertracing.io/docs/latest/performance-tuning/
- **Sampling Strategies**: https://www.jaegertracing.io/docs/latest/sampling/

---

## Quick Commands

```bash
# View Jaeger UI (kind-local)
open http://jaeger.localtest.me:8080

# Port-forward to Jaeger UI
kubectl port-forward -n observability svc/jaeger-query 16686:16686

# Check Jaeger logs
kubectl logs -n observability -l app=jaeger

# Query traces via API
kubectl port-forward -n observability svc/jaeger-query 16686:16686 &
curl "http://localhost:16686/api/traces?service=redis&limit=10" | jq

# Check metrics
kubectl port-forward -n observability svc/jaeger-query 14269:14269 &
curl http://localhost:14269/metrics | grep jaeger_collector

# Update sampling config
kubectl edit configmap jaeger-sampling-config -n observability
kubectl rollout restart deployment/jaeger -n observability
```
