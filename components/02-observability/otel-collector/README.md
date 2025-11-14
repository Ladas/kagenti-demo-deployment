# OpenTelemetry Collector - Trace Routing Component

## Overview

The OpenTelemetry Collector is the **central hub** for all telemetry data in the Kagenti platform. It receives traces from instrumented services and **routes them to the appropriate backend**:

- **OpenInference traces** (agent/LLM) → **Phoenix**
- **Standard OTLP traces** (infrastructure) → **Jaeger**

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│          Instrumented Services                            │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐         │
│  │ Agents │  │  Istio │  │  Redis │  │Services│         │
│  └───┬────┘  └───┬────┘  └───┬────┘  └───┬────┘         │
│      │           │           │           │               │
│      └───────────┴───────────┴───────────┘               │
│                       │                                   │
│              Send traces (OTLP)                          │
└───────────────────────┬──────────────────────────────────┘
                        ↓
        ┌───────────────────────────────┐
        │   OpenTelemetry Collector     │
        │                               │
        │  ┌─────────────────────────┐ │
        │  │  Routing Processor      │ │
        │  │                         │ │
        │  │  Check attribute:       │ │
        │  │  "openinference.span.   │ │
        │  │   kind"                 │ │
        │  │                         │ │
        │  │  ✓ Has attribute?       │ │
        │  │    → Phoenix            │ │
        │  │  ✗ No attribute?        │ │
        │  │    → Jaeger             │ │
        │  └─────────────────────────┘ │
        └───┬────────────────┬──────────┘
            │                │
            ↓                ↓
    ┌───────────┐    ┌───────────┐
    │  Phoenix  │    │  Jaeger   │
    │           │    │           │
    │Agent/LLM  │    │   Infra   │
    │  Traces   │    │  Traces   │
    └───────────┘    └───────────┘
```

## Routing Logic

### OpenInference Detection

The collector checks for the `openinference.span.kind` attribute:

| Attribute Value | Backend | Trace Type |
|----------------|---------|------------|
| `CHAIN` | Phoenix | Agent workflow/chain |
| `LLM` | Phoenix | LLM request/response |
| `TOOL` | Phoenix | MCP tool call |
| `AGENT` | Phoenix | Agent execution |
| `EMBEDDING` | Phoenix | Embedding generation |
| `RETRIEVER` | Phoenix | RAG retrieval |
| **None** (absent) | Jaeger | Infrastructure (Istio, Redis, etc.) |

### Example Routing Decisions

```yaml
# Agent calling LLM
span:
  name: "chat_completion"
  attributes:
    openinference.span.kind: LLM
    llm.model_name: "gpt-4"
→ Routed to Phoenix ✓

# Redis query from service
span:
  name: "redis.get"
  attributes:
    db.system: redis
    # No openinference.span.kind
→ Routed to Jaeger ✓

# Agent calling MCP tool
span:
  name: "prometheus_query"
  attributes:
    openinference.span.kind: TOOL
    tool.name: "prometheus-mcp"
→ Routed to Phoenix ✓

# Istio sidecar HTTP request
span:
  name: "HTTP GET"
  attributes:
    http.method: GET
    # No openinference.span.kind
→ Routed to Jaeger ✓
```

## Configuration

### Processors

```yaml
processors:
  # Routing by OpenInference attribute
  routing:
    from_attribute: openinference.span.kind
    table:
      - value: CHAIN
        exporters: [otlp/phoenix]
      - value: LLM
        exporters: [otlp/phoenix]
      - value: TOOL
        exporters: [otlp/phoenix]
      # ... other OpenInference kinds
    default_exporters: [otlp/jaeger]  # No attribute → Jaeger
```

### Exporters

```yaml
exporters:
  # Phoenix (agent/LLM traces)
  otlp/phoenix:
    endpoint: phoenix.observability.svc.cluster.local:4317
    retry_on_failure:
      enabled: true
      max_interval: 30s

  # Jaeger (infrastructure traces)
  otlp/jaeger:
    endpoint: jaeger-collector.observability.svc.cluster.local:4317
    retry_on_failure:
      enabled: true
      max_interval: 30s
```

## Instrumentation

### How to Send Traces

Services send traces to the OTEL Collector using the **OTLP protocol**:

```python
# Python example (OpenTelemetry SDK)
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Configure exporter to send to OTEL Collector
exporter = OTLPSpanExporter(
    endpoint="otel-collector.observability.svc.cluster.local:4317",
    insecure=True
)

# Set up tracing
provider = TracerProvider()
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

# Create spans
tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("my-operation"):
    # Your code here
    pass
```

### OpenInference Instrumentation (for Agents)

Agents should use OpenInference instrumentation:

```python
# Python example (OpenInference)
from openinference.instrumentation import using_attributes

# This span will be routed to Phoenix
with using_attributes(
    span_kind="LLM",
    llm={
        "model_name": "gpt-4",
        "provider": "openai",
    }
):
    response = openai.ChatCompletion.create(...)
```

### Istio Service Mesh (Automatic)

Istio automatically sends traces to the OTEL Collector:

```yaml
# Istio config (no code changes needed in services)
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio
  namespace: istio-system
data:
  mesh: |
    defaultConfig:
      tracing:
        openCensusAgent:
          address: otel-collector.observability.svc.cluster.local:4317
          context: [W3C_TRACE_CONTEXT]
```

## Monitoring

### Collector Metrics

The collector exposes Prometheus metrics on port `8888`:

```bash
# Port-forward to metrics endpoint
kubectl port-forward -n observability svc/otel-collector 8888:8888

# View metrics
curl http://localhost:8888/metrics
```

**Key metrics**:
- `otelcol_receiver_accepted_spans` - Spans received
- `otelcol_processor_batch_batch_send_size` - Batch sizes sent to exporters
- `otelcol_exporter_sent_spans` - Spans sent to backends (by exporter)
- `otelcol_exporter_send_failed_spans` - Failed exports (by exporter)
- `otelcol_processor_refused_spans` - Spans refused (memory pressure)

### Health Check

```bash
# Check collector health
kubectl port-forward -n observability svc/otel-collector 13133:13133
curl http://localhost:13133/

# Should return 200 OK
```

### zPages (Diagnostics)

zPages provide detailed diagnostics:

```bash
# Port-forward to zPages
kubectl port-forward -n observability svc/otel-collector 55679:55679

# View in browser
open http://localhost:55679/debug/tracez
```

**Available pages**:
- `/debug/tracez` - Sample traces passing through collector
- `/debug/pipelinez` - Pipeline statistics
- `/debug/servicez` - Service info

## Troubleshooting

### Traces Not Reaching Phoenix

1. **Check if collector is routing to Phoenix**:
   ```bash
   kubectl logs -n observability -l app=otel-collector | grep "otlp/phoenix"
   ```

2. **Verify OpenInference attribute exists**:
   - Ensure agent instrumentation sets `openinference.span.kind`
   - Check sample traces in zPages: http://localhost:55679/debug/tracez

3. **Check Phoenix exporter metrics**:
   ```bash
   curl http://localhost:8888/metrics | grep otelcol_exporter_sent_spans | grep phoenix
   ```

### Traces Not Reaching Jaeger

1. **Check if collector is routing to Jaeger**:
   ```bash
   kubectl logs -n observability -l app=otel-collector | grep "otlp/jaeger"
   ```

2. **Verify traces DON'T have OpenInference attribute**:
   - Infrastructure traces should NOT have `openinference.span.kind`
   - Check Istio traces: should route to Jaeger by default

3. **Check Jaeger exporter metrics**:
   ```bash
   curl http://localhost:8888/metrics | grep otelcol_exporter_sent_spans | grep jaeger
   ```

### High Memory Usage

1. **Check memory limiter processor**:
   ```bash
   kubectl logs -n observability -l app=otel-collector | grep "memory_limiter"
   ```

2. **Adjust memory limits** in ConfigMap:
   ```yaml
   processors:
     memory_limiter:
       limit_mib: 1024  # Increase from 512
   ```

3. **Increase pod resources**:
   ```yaml
   # In environment-specific patch
   resources:
     limits:
       memory: 4Gi
   ```

### Export Failures

1. **Check backend availability**:
   ```bash
   # Test Phoenix
   kubectl exec -n observability deploy/otel-collector -- \
     nc -zv phoenix.observability.svc.cluster.local 4317

   # Test Jaeger
   kubectl exec -n observability deploy/otel-collector -- \
     nc -zv jaeger-collector.observability.svc.cluster.local 4317
   ```

2. **Check retry metrics**:
   ```bash
   curl http://localhost:8888/metrics | grep otelcol_exporter_send_failed_spans
   ```

3. **Increase retry limits** in ConfigMap:
   ```yaml
   exporters:
     otlp/phoenix:
       retry_on_failure:
         max_interval: 60s  # Increase from 30s
         max_elapsed_time: 600s  # Increase from 300s
   ```

## Performance Tuning

### Batch Processing

Adjust batch size for better throughput:

```yaml
processors:
  batch:
    timeout: 5s        # Send batch every 5s (faster)
    send_batch_size: 2048  # Or when 2048 spans collected
```

### Queue Size

Increase queue size for high-volume environments:

```yaml
exporters:
  otlp/phoenix:
    sending_queue:
      queue_size: 5000  # Increase from 1000
      num_consumers: 20  # Increase from 10
```

### Replicas

Scale collector horizontally:

```yaml
# In environment-specific patch
spec:
  replicas: 3  # Increase from 2
```

## Environment-Specific Configuration

Different environments can override settings:

### Kind (Local)
- Single replica
- Debug logging enabled
- Small queue sizes

### OpenShift (Production)
- Multiple replicas (3+)
- Info logging
- Large queue sizes
- Higher resource limits

**Example patch** (`environments/openshift-prod/patches/otel-collector.yaml`):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: observability
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: otel-collector
        env:
        - name: ENVIRONMENT
          value: "production"
        - name: CLUSTER_NAME
          value: "openshift-prod"
        resources:
          requests:
            cpu: 500m
            memory: 2Gi
          limits:
            cpu: 2000m
            memory: 8Gi
```

## References

- **OpenTelemetry Collector**: https://opentelemetry.io/docs/collector/
- **Routing Processor**: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/routingprocessor
- **OTLP Exporter**: https://github.com/open-telemetry/opentelemetry-collector/tree/main/exporter/otlpexporter
- **OpenInference Specification**: https://github.com/Arize-ai/openinference

---

## Quick Commands

```bash
# View collector logs
kubectl logs -n observability -l app=otel-collector -f

# Check health
kubectl port-forward -n observability svc/otel-collector 13133:13133 &
curl http://localhost:13133/

# View metrics
kubectl port-forward -n observability svc/otel-collector 8888:8888 &
curl http://localhost:8888/metrics

# View zPages diagnostics
kubectl port-forward -n observability svc/otel-collector 55679:55679 &
open http://localhost:55679/debug/tracez

# Test trace routing
kubectl port-forward -n observability svc/otel-collector 4317:4317 &
# Send test trace with openinference.span.kind → should route to Phoenix

# Update configuration
kubectl edit configmap otel-collector-config -n observability
kubectl rollout restart deployment/otel-collector -n observability
```
