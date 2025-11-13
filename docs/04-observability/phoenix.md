# Phoenix: LLM and AI Agent Observability

**Version**: 1.0
**Last Updated**: 2025-11-12
**Status**: Production Ready
**Audience**: Data Scientists, AI Engineers, Platform Engineers

Complete guide to Arize Phoenix for LLM and AI agent observability in the Kagenti platform, with comprehensive integration patterns for instrumentation and trace collection.

---

## Table of Contents

- [Overview](#overview)
- [What is Phoenix?](#what-is-phoenix)
- [Why Use Phoenix?](#why-use-phoenix)
- [Architecture](#architecture)
- [Installation](#installation)
- [Kagenti Integration](#kagenti-integration)
- [Agent Instrumentation](#agent-instrumentation)
- [OpenTelemetry Integration](#opentelemetry-integration)
- [Viewing Traces](#viewing-traces)
- [Integration Patterns](#integration-patterns)
- [Production Deployment](#production-deployment)
- [Troubleshooting](#troubleshooting)
- [Alternatives](#alternatives)
- [Next Steps](#next-steps)
- [References](#references)

---

## Overview

**Purpose**: Provide specialized observability for LLM applications and AI agents with trace collection, evaluation, and cost tracking.

**What You Get**:
- ✅ LLM call tracing with prompt and response inspection
- ✅ Token usage and cost tracking per request
- ✅ Agent workflow visualization (chains, tools, reasoning)
- ✅ OpenTelemetry-native trace collection
- ✅ Integration with LangChain, LlamaIndex, CrewAI, OpenAI SDK
- ✅ Evaluation framework for LLM outputs
- ✅ Prompt versioning and experimentation
- ✅ Long retention for valuable agent traces (30-90 days)

**Key Benefit**: Phoenix provides **LLM-specific observability** that generic tracing tools lack - prompts, tokens, costs, embeddings, and agent reasoning steps all in one place.

**Source**: Based on [Arize Phoenix Documentation](https://arize.com/docs/phoenix/)

---

## What is Phoenix?

**Arize Phoenix** is an open-source AI observability and evaluation platform designed specifically for LLM applications and AI agents.

### Core Features

```mermaid
graph TB
    subgraph "Phoenix Capabilities"
        T[Tracing<br/>LLM calls, chains, agents]
        E[Evaluation<br/>Quality metrics, annotations]
        P[Prompt Engineering<br/>Version tracking, playground]
        D[Datasets<br/>Trace collection, experiments]
    end

    subgraph "Integration Points"
        OT[OpenTelemetry<br/>OTLP traces]
        SDK[AI Frameworks<br/>LangChain, LlamaIndex, CrewAI]
        LLM[LLM Providers<br/>OpenAI, Bedrock, Mistral, Vertex]
    end

    subgraph "Insights"
        TOK[Token Usage]
        COST[Cost Tracking]
        LAT[Latency Analysis]
        ERR[Error Detection]
    end

    T --> TOK
    T --> COST
    T --> LAT
    T --> ERR

    OT --> T
    SDK --> T
    LLM --> T

    style T fill:#4caf50
    style E fill:#2196f3
    style P fill:#ff9800
    style D fill:#9c27b0
```

**Key Characteristics**:
1. **LLM-Native**: Understands prompts, tokens, embeddings, tool calls
2. **OpenTelemetry-Based**: Uses OpenInference semantic conventions for LLM traces
3. **Framework-Agnostic**: Works with any Python LLM framework
4. **Self-Hosted**: No data sent to external vendors (privacy-friendly)
5. **Vendor-Neutral**: Supports multiple LLM providers (OpenAI, Anthropic, etc.)

**Source**: [Phoenix Overview](https://arize.com/docs/phoenix/)

---

## Why Use Phoenix?

### Without Phoenix

**Limited visibility into LLM calls**:
```
Agent failed!
❓ What was the prompt?
❓ What did the LLM respond?
❓ How many tokens were used?
❓ What was the cost?
❓ Which tool did the agent call?
```

**Manual debugging**:
- Print statements in agent code
- Log files scattered across services
- No cost tracking
- No prompt history
- Difficult to reproduce issues

---

### With Phoenix

**Complete LLM observability**:
```
Agent Execution [trace_id: abc123]
├─ Agent: ResearchAgent
│  ├─ Prompt: "Analyze Kubernetes metrics and suggest optimizations"
│  ├─ Model: gpt-4
│  ├─ Tokens: 150 prompt, 75 completion
│  ├─ Cost: $0.003
│  ├─ Latency: 5.2s
│  └─ Response: "Based on CPU metrics, recommend HPA with target 70%..."
│
├─ Tool Call: PrometheusQuery
│  ├─ Tool: prometheus-mcp
│  ├─ Query: "container_cpu_usage_seconds_total"
│  ├─ Result: [metrics data]
│  └─ Duration: 120ms
│
└─ LLM Call: Final Answer
   ├─ Prompt: "Summarize findings..."
   ├─ Tokens: 50 prompt, 200 completion
   ├─ Cost: $0.0025
   └─ Response: "Recommended HPA configuration:\n  min: 2\n  max: 10..."

Total Cost: $0.0055 ✅
Total Latency: 6.5s ✅
```

**Benefits**:
- ✅ Full prompt and response inspection
- ✅ Automatic token and cost tracking
- ✅ Agent workflow visualization
- ✅ Tool call inspection
- ✅ Latency breakdown
- ✅ Error attribution
- ✅ Evaluation and annotation

**Source**: [Why Phoenix?](https://arize.com/docs/phoenix/)

---

## Architecture

### Phoenix in Kagenti Platform

Phoenix integrates with the Kagenti observability stack via OpenTelemetry:

```mermaid
graph TB
    subgraph "Kagenti Agents"
        RA[Research Agent<br/>OpenInference instrumentation]
        CA[Code Agent<br/>OpenInference instrumentation]
        OA[Orchestrator Agent<br/>OpenInference instrumentation]
    end

    subgraph "Trace Collection"
        OC[OTEL Collector<br/>Routing Processor]
    end

    subgraph "Trace Storage"
        PH[Phoenix<br/>observability namespace]
        PHDB[(Phoenix PostgreSQL<br/>Trace storage)]
    end

    subgraph "Access"
        PHUI[Phoenix Web UI<br/>https://phoenix.localtest.me:9443]
        PHAPI[Phoenix GraphQL API<br/>http://phoenix:6006/graphql]
    end

    RA -->|OTLP traces| OC
    CA -->|OTLP traces| OC
    OA -->|OTLP traces| OC

    OC -->|openinference.span.kind exists| PH
    PH --> PHDB
    PH --> PHUI
    PH --> PHAPI

    style PH fill:#4caf50
    style OC fill:#2196f3
    style PHDB fill:#9c27b0
```

**Source**: [Kagenti OTEL Collector Configuration](../../components/02-observability/otel-collector/configmap.yaml)

### Trace Routing Logic

The OTEL Collector routes traces to Phoenix when they contain the `openinference.span.kind` attribute:

| Attribute Value | Trace Type | Backend |
|----------------|------------|---------|
| `LLM` | LLM API call | Phoenix |
| `CHAIN` | Agent workflow/chain | Phoenix |
| `TOOL` | MCP tool call | Phoenix |
| `AGENT` | Agent execution | Phoenix |
| `EMBEDDING` | Embedding generation | Phoenix |
| `RETRIEVER` | RAG retrieval | Phoenix |
| **None** (absent) | Infrastructure (HTTP, DB, Redis) | Tempo |

**Source**: [OpenInference Semantic Conventions](https://github.com/Arize-ai/openinference)

---

## Installation

### Deploy Phoenix in Kubernetes

Phoenix is deployed as part of the Kagenti observability stack:

**File**: `components/02-observability/phoenix/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phoenix
  template:
    metadata:
      labels:
        app: phoenix
    spec:
      containers:
      - name: phoenix
        image: arizephoenix/phoenix:latest
        ports:
        - containerPort: 6006
          name: http
        - containerPort: 4317
          name: otlp-grpc
        env:
        - name: PHOENIX_PORT
          value: "6006"
        - name: PHOENIX_HOST
          value: "0.0.0.0"
        # Optional: PostgreSQL backend for persistence
        # - name: PHOENIX_SQL_DATABASE_URL
        #   value: "postgresql://user:password@postgres:5432/phoenix"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
```

**Deploy**:
```bash
# Deploy Phoenix
kubectl apply -k components/02-observability/phoenix/

# Verify deployment
kubectl get pods -n observability -l app=phoenix

# Expected:
# NAME                       READY   STATUS    RESTARTS   AGE
# phoenix-7d4b5d7d9c-xxxxx   1/1     Running   0          1m
```

**Source**: [Phoenix Deployment Guide](https://arize.com/docs/phoenix/deployment)

---

### Access Phoenix UI

Phoenix UI is accessible via HTTPRoute:

```bash
# Local Kind deployment
open https://phoenix.localtest.me:9443

# Port-forward for direct access
kubectl port-forward -n observability svc/phoenix 6006:6006
open http://localhost:6006
```

**Default credentials**: None (no authentication by default)

**Production**: Enable authentication via OAuth2-Proxy (see [Keycloak Integration](../03-authentication/keycloak.md))

---

## Kagenti Integration

### Current Phoenix Deployment

Phoenix is deployed in Kagenti with the following configuration:

**Deployment Details**:
- **Namespace**: `observability`
- **Replicas**: 1 (single instance)
- **Image**: `arizephoenix/phoenix:latest`
- **Ports**:
  - `6006`: HTTP (Web UI, GraphQL API)
  - `4317`: OTLP gRPC (trace ingestion)
- **Storage**: SQLite (default, ephemeral)
- **Access**: HTTPRoute via `https://phoenix.localtest.me:9443`

**File Locations**:
```
components/02-observability/phoenix/
├── deployment.yaml       # Phoenix pods
├── service.yaml          # ClusterIP service (6006, 4317)
├── httproute.yaml        # HTTPS access via Gateway API
└── kustomization.yaml    # Kustomize manifest
```

**Verify Deployment**:
```bash
# Check Phoenix pod
kubectl get pods -n observability -l app=phoenix

# Check Phoenix service
kubectl get svc -n observability phoenix

# Check OTLP endpoint
kubectl exec -n observability deploy/phoenix -- nc -zv localhost 4317

# Should output: Connection to localhost 4317 port [tcp/*] succeeded!
```

---

### Integration Gaps (Current State)

**Note**: As you mentioned, the current Kagenti repository does not have **full Phoenix integration** for agents. Here are the gaps:

**Missing**:
1. ❌ Agent instrumentation code (no OpenInference SDK in agents)
2. ❌ Environment variables for OTLP endpoint configuration
3. ❌ PostgreSQL backend for persistent trace storage
4. ❌ Authentication (OAuth2-Proxy) for Phoenix UI
5. ❌ Agent deployment manifests with OTEL environment variables

**Present**:
1. ✅ Phoenix deployment in `observability` namespace
2. ✅ OTEL Collector routing configuration (routes to Phoenix OTLP endpoint)
3. ✅ HTTPRoute for Phoenix UI access
4. ✅ Service for Phoenix (6006, 4317)

---

## Agent Instrumentation

To fully integrate agents with Phoenix, add OpenInference instrumentation to your Python agents.

### Prerequisites

Install OpenTelemetry and OpenInference SDK:

```bash
# Core OpenTelemetry packages
pip install \
  opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-exporter-otlp \
  opentelemetry-instrumentation

# OpenInference instrumentation (Phoenix-compatible)
pip install \
  openinference-instrumentation \
  openinference-instrumentation-openai \
  openinference-instrumentation-langchain \
  openinference-instrumentation-llama-index
```

**Source**: [Phoenix Tracing Quickstart](https://arize.com/docs/phoenix/quickstart)

---

### Basic Agent Instrumentation

#### Example 1: OpenAI Auto-Instrumentation

Automatically instrument OpenAI SDK calls:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from openinference.instrumentation.openai import OpenAIInstrumentor
import openai

# Configure OTLP exporter (sends to OTEL Collector)
exporter = OTLPSpanExporter(
    endpoint="otel-collector.observability.svc.cluster.local:4317",
    insecure=True  # Use TLS in production
)

# Set up tracing provider
provider = TracerProvider()
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

# Auto-instrument OpenAI SDK
OpenAIInstrumentor().instrument()

# Now all OpenAI calls are automatically traced
client = openai.OpenAI()
response = client.chat.completions.create(
    model="gpt-4",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Analyze Kubernetes metrics"}
    ]
)

# Traces automatically sent to Phoenix via OTEL Collector!
```

**What Gets Traced**:
- Prompt content
- Model name (gpt-4)
- Token counts (prompt tokens, completion tokens)
- Cost estimation
- Latency
- Response content
- Error messages (if any)

**Source**: [OpenAI Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/openai)

---

#### Example 2: LangChain Auto-Instrumentation

Automatically instrument LangChain chains and agents:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from openinference.instrumentation.langchain import LangChainInstrumentor
from langchain.chains import LLMChain
from langchain.llms import OpenAI
from langchain.prompts import PromptTemplate

# Configure OTLP exporter
exporter = OTLPSpanExporter(
    endpoint="otel-collector.observability.svc.cluster.local:4317",
    insecure=True
)

# Set up tracing
provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Auto-instrument LangChain
LangChainInstrumentor().instrument()

# Create LangChain components (automatically instrumented)
llm = OpenAI(model_name="gpt-4")
prompt = PromptTemplate(
    input_variables=["task"],
    template="Complete this task: {task}"
)
chain = LLMChain(llm=llm, prompt=prompt)

# Run chain (traces sent to Phoenix)
result = chain.run(task="Analyze Prometheus metrics and suggest optimizations")
```

**What Gets Traced**:
- Chain execution flow
- Prompt template expansion
- LLM calls with prompts and responses
- Token usage per LLM call
- Chain inputs and outputs
- Intermediate steps
- Error traces

**Source**: [LangChain Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/langchain)

---

#### Example 3: LlamaIndex Auto-Instrumentation

Instrument LlamaIndex queries and agents:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from openinference.instrumentation.llama_index import LlamaIndexInstrumentor
from llama_index import VectorStoreIndex, SimpleDirectoryReader
from llama_index.llms import OpenAI

# Configure OTLP exporter
exporter = OTLPSpanExporter(
    endpoint="otel-collector.observability.svc.cluster.local:4317",
    insecure=True
)

# Set up tracing
provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Auto-instrument LlamaIndex
LlamaIndexInstrumentor().instrument()

# Create LlamaIndex components (automatically instrumented)
documents = SimpleDirectoryReader("./docs").load_data()
index = VectorStoreIndex.from_documents(documents)
query_engine = index.as_query_engine()

# Query (traces sent to Phoenix)
response = query_engine.query("What is the ArgoCD deployment strategy?")
```

**What Gets Traced**:
- Query execution
- Document retrieval (RAG)
- Embedding generation
- LLM calls for answer synthesis
- Retrieved document chunks
- Similarity scores
- Token usage and costs

**Source**: [LlamaIndex Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/llamaindex)

---

#### Example 4: CrewAI Multi-Agent Instrumentation

Instrument CrewAI multi-agent workflows:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from openinference.instrumentation.crewai import CrewAIInstrumentor
from crewai import Agent, Task, Crew
from langchain.llms import OpenAI

# Configure OTLP exporter
exporter = OTLPSpanExporter(
    endpoint="otel-collector.observability.svc.cluster.local:4317",
    insecure=True
)

# Set up tracing
provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Auto-instrument CrewAI
CrewAIInstrumentor().instrument()

# Create CrewAI agents
researcher = Agent(
    role="Researcher",
    goal="Research Kubernetes best practices",
    llm=OpenAI(model_name="gpt-4")
)

writer = Agent(
    role="Technical Writer",
    goal="Write documentation based on research",
    llm=OpenAI(model_name="gpt-4")
)

# Create tasks
research_task = Task(
    description="Research ArgoCD ApplicationSets migration strategies",
    agent=researcher
)

writing_task = Task(
    description="Write migration guide based on research",
    agent=writer
)

# Create crew and execute
crew = Crew(agents=[researcher, writer], tasks=[research_task, writing_task])
result = crew.kickoff()
```

**What Gets Traced**:
- Crew execution flow
- Agent role assignments
- Task delegation
- LLM calls per agent
- Inter-agent communication
- Task completion order
- Full execution timeline

**Source**: [CrewAI Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/crewai)

---

### Manual Instrumentation

For custom agent logic not covered by auto-instrumentation:

```python
from opentelemetry import trace
from opentelemetry.trace import SpanKind, Status, StatusCode

tracer = trace.get_tracer(__name__)

# Custom agent span with OpenInference attributes
with tracer.start_as_current_span(
    "custom_agent_task",
    kind=SpanKind.INTERNAL,
    attributes={
        "openinference.span.kind": "AGENT",  # Routes to Phoenix
        "agent.name": "custom-research-agent",
        "agent.task": "analyze_metrics"
    }
) as span:
    try:
        # Agent logic here
        result = perform_analysis()

        # Add custom attributes
        span.set_attribute("agent.result.success", True)
        span.set_attribute("agent.result.findings_count", len(result.findings))
        span.set_status(Status(StatusCode.OK))

    except Exception as e:
        # Record errors
        span.set_status(Status(StatusCode.ERROR, str(e)))
        span.record_exception(e)
        raise
```

**Key Attributes**:
- `openinference.span.kind`: Routes trace to Phoenix (required)
- `agent.name`: Agent identifier
- `llm.model_name`: LLM model used
- `llm.token_count.prompt`: Prompt tokens
- `llm.token_count.completion`: Completion tokens
- `tool.name`: Tool/MCP server called
- `retrieval.documents`: Retrieved document IDs

**Source**: [Manual Instrumentation Guide](https://arize.com/docs/phoenix/tracing/how-to-tracing/instrumentation)

---

## OpenTelemetry Integration

### Environment Variables for Agents

Configure agents to send traces to the OTEL Collector:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: research-agent
  namespace: team1
spec:
  template:
    spec:
      containers:
      - name: agent
        image: kagenti/research-agent:latest
        env:
        # OTLP exporter configuration
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.observability.svc.cluster.local:4317"
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: "grpc"
        - name: OTEL_EXPORTER_OTLP_INSECURE
          value: "true"  # Use TLS in production

        # Service identification
        - name: OTEL_SERVICE_NAME
          value: "research-agent"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "service.namespace=team1,deployment.environment=kind-local"

        # Tracing configuration
        - name: OTEL_TRACES_SAMPLER
          value: "always_on"  # Or "parentbased_traceidratio" with sampling
        - name: OTEL_TRACES_EXPORTER
          value: "otlp"
```

**Alternative**: Use ConfigMap for centralized OTEL configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-agent-config
  namespace: team1
data:
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector.observability.svc.cluster.local:4317"
  OTEL_SERVICE_NAME: "research-agent"
```

**Source**: [OpenTelemetry Environment Variables](https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/)

---

### Verify Trace Flow

Test that traces reach Phoenix:

```bash
# 1. Check OTEL Collector is receiving traces
kubectl port-forward -n observability svc/otel-collector 8888:8888
curl http://localhost:8888/metrics | grep otelcol_receiver_accepted_spans

# 2. Check OTEL Collector is routing to Phoenix
kubectl logs -n observability -l app=otel-collector | grep "otlp/phoenix"

# Expected: Logs showing successful exports to Phoenix exporter

# 3. Check Phoenix is receiving traces
kubectl port-forward -n observability svc/phoenix 6006:6006
open http://localhost:6006

# Navigate to "Traces" tab - should see agent traces!
```

---

## Viewing Traces

### Phoenix Web UI

Access Phoenix UI to view traces:

**Local (Kind)**:
```bash
# Via HTTPRoute (HTTPS)
open https://phoenix.localtest.me:9443

# Via port-forward (HTTP)
kubectl port-forward -n observability svc/phoenix 6006:6006
open http://localhost:6006
```

**UI Features**:

1. **Traces Tab**:
   - List of all LLM traces
   - Filter by service, time range, status
   - Search by trace ID
   - View trace timeline

2. **Trace Details**:
   - Span hierarchy (parent-child relationships)
   - Prompt and response content
   - Token counts and costs
   - Latency breakdown
   - Error messages and stack traces

3. **Projects**:
   - Group traces by project
   - Compare experiments
   - Track costs per project

4. **Evaluations**:
   - Annotate traces (quality ratings)
   - Run evaluations on datasets
   - Track evaluation metrics

---

### Phoenix GraphQL API

Query traces programmatically:

```bash
# Port-forward to Phoenix
kubectl port-forward -n observability svc/phoenix 6006:6006

# Query traces via GraphQL
curl http://localhost:6006/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{ spans(first: 10) { edges { node { name context { traceId spanId } attributes } } } }"
  }'
```

**Example Queries**:

```graphql
# Get traces for specific agent
query GetAgentTraces {
  spans(filter: {attribute: {key: "agent.name", value: "research-agent"}}) {
    edges {
      node {
        name
        context {
          traceId
          spanId
        }
        attributes
        startTime
        endTime
      }
    }
  }
}

# Get LLM token usage
query GetTokenUsage {
  spans(filter: {attribute: {key: "openinference.span.kind", value: "LLM"}}) {
    edges {
      node {
        attributes
      }
    }
  }
}
```

**Source**: [Phoenix GraphQL API](https://arize.com/docs/phoenix/)

---

## Integration Patterns

### Pattern 1: Simple Agent (Single LLM Call)

**Use Case**: Agent makes one LLM call to answer a question.

**Instrumentation**:
```python
from openinference.instrumentation.openai import OpenAIInstrumentor

# Auto-instrument once at startup
OpenAIInstrumentor().instrument()

# Agent code
def answer_question(question: str) -> str:
    response = openai.chat.completions.create(
        model="gpt-4",
        messages=[{"role": "user", "content": question}]
    )
    return response.choices[0].message.content
```

**Phoenix Trace**:
```
Trace: answer_question
└─ LLM: gpt-4
   ├─ Prompt: "What is Kubernetes?"
   ├─ Tokens: 10 prompt, 50 completion
   ├─ Cost: $0.0006
   └─ Response: "Kubernetes is a container orchestration platform..."
```

---

### Pattern 2: RAG Agent (Retrieval + LLM)

**Use Case**: Agent retrieves documents, then calls LLM to synthesize answer.

**Instrumentation**:
```python
from openinference.instrumentation.llama_index import LlamaIndexInstrumentor

# Auto-instrument LlamaIndex
LlamaIndexInstrumentor().instrument()

# RAG agent
index = VectorStoreIndex.from_documents(documents)
query_engine = index.as_query_engine()
response = query_engine.query("Explain ArgoCD ApplicationSets")
```

**Phoenix Trace**:
```
Trace: RAG Query
├─ RETRIEVER: VectorStoreRetriever
│  ├─ Query: "Explain ArgoCD ApplicationSets"
│  ├─ Retrieved Documents: 3
│  └─ Top Result: "ApplicationSets enable..."
│
├─ EMBEDDING: OpenAI text-embedding-ada-002
│  ├─ Input: "Explain ArgoCD ApplicationSets"
│  ├─ Tokens: 5
│  └─ Cost: $0.00001
│
└─ LLM: gpt-4
   ├─ Prompt: "Context: [documents...]\nQuestion: Explain ArgoCD ApplicationSets"
   ├─ Tokens: 500 prompt, 200 completion
   ├─ Cost: $0.007
   └─ Response: "ApplicationSets are a declarative way..."
```

---

### Pattern 3: Multi-Agent Workflow (CrewAI)

**Use Case**: Multiple agents collaborate on a task (researcher + writer).

**Instrumentation**:
```python
from openinference.instrumentation.crewai import CrewAIInstrumentor

# Auto-instrument CrewAI
CrewAIInstrumentor().instrument()

# Multi-agent crew
researcher = Agent(role="Researcher", goal="Research topic", llm=llm)
writer = Agent(role="Writer", goal="Write documentation", llm=llm)

crew = Crew(agents=[researcher, writer], tasks=[research_task, write_task])
result = crew.kickoff()
```

**Phoenix Trace**:
```
Trace: CrewAI Execution
├─ AGENT: Researcher
│  ├─ Task: "Research ArgoCD ApplicationSets"
│  └─ LLM: gpt-4
│     ├─ Prompt: "Research ArgoCD ApplicationSets migration strategies"
│     ├─ Tokens: 100 prompt, 300 completion
│     └─ Response: "ApplicationSets provide..."
│
└─ AGENT: Writer
   ├─ Task: "Write migration guide"
   ├─ Input: [Research results from Researcher]
   └─ LLM: gpt-4
      ├─ Prompt: "Write guide based on: [research]..."
      ├─ Tokens: 400 prompt, 600 completion
      └─ Response: "# ApplicationSets Migration Guide..."
```

---

### Pattern 4: Agent with MCP Tool Calls

**Use Case**: Agent calls MCP tools (Prometheus, GitHub, etc.) and uses results in LLM prompt.

**Instrumentation**:
```python
from opentelemetry import trace
from openinference.instrumentation.openai import OpenAIInstrumentor

OpenAIInstrumentor().instrument()
tracer = trace.get_tracer(__name__)

# Agent with tool call
def analyze_metrics() -> str:
    # MCP tool call (manual span)
    with tracer.start_as_current_span(
        "prometheus_query",
        attributes={
            "openinference.span.kind": "TOOL",
            "tool.name": "prometheus-mcp",
            "tool.query": "container_cpu_usage_seconds_total"
        }
    ) as tool_span:
        metrics = call_prometheus_mcp("container_cpu_usage_seconds_total")
        tool_span.set_attribute("tool.result.count", len(metrics))

    # LLM call (auto-instrumented)
    response = openai.chat.completions.create(
        model="gpt-4",
        messages=[
            {"role": "system", "content": "You analyze Prometheus metrics."},
            {"role": "user", "content": f"Analyze these metrics: {metrics}"}
        ]
    )

    return response.choices[0].message.content
```

**Phoenix Trace**:
```
Trace: analyze_metrics
├─ TOOL: prometheus_query
│  ├─ Tool: prometheus-mcp
│  ├─ Query: "container_cpu_usage_seconds_total"
│  ├─ Result Count: 15
│  └─ Duration: 120ms
│
└─ LLM: gpt-4
   ├─ Prompt: "Analyze these metrics: [metrics data]..."
   ├─ Tokens: 200 prompt, 150 completion
   ├─ Cost: $0.0035
   └─ Response: "CPU usage is high. Recommend scaling..."
```

---

## Production Deployment

### Persistent Storage (PostgreSQL)

For production, use PostgreSQL instead of SQLite:

**Deploy PostgreSQL**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix-postgres
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phoenix-postgres
  template:
    metadata:
      labels:
        app: phoenix-postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_DB
          value: "phoenix"
        - name: POSTGRES_USER
          value: "phoenix"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: phoenix-postgres-secret
              key: password
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: phoenix-postgres-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: phoenix-postgres-pvc
  namespace: observability
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

**Configure Phoenix to use PostgreSQL**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix
  namespace: observability
spec:
  template:
    spec:
      containers:
      - name: phoenix
        env:
        - name: PHOENIX_SQL_DATABASE_URL
          value: "postgresql://phoenix:password@phoenix-postgres:5432/phoenix"
```

---

### Authentication (OAuth2-Proxy)

Secure Phoenix UI with OAuth2-Proxy and Keycloak:

**File**: `components/00-infrastructure/oauth2-proxy/phoenix-proxy.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix-oauth2-proxy
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phoenix-oauth2-proxy
  template:
    metadata:
      labels:
        app: phoenix-oauth2-proxy
    spec:
      containers:
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:latest
        args:
        - --provider=oidc
        - --oidc-issuer-url=https://keycloak.localtest.me:9443/realms/kagenti
        - --client-id=phoenix
        - --client-secret=$(OAUTH2_PROXY_CLIENT_SECRET)
        - --upstream=http://phoenix:6006
        - --http-address=0.0.0.0:4180
        - --cookie-secret=$(OAUTH2_PROXY_COOKIE_SECRET)
        - --email-domain=*
        env:
        - name: OAUTH2_PROXY_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: phoenix-oauth2-secret
              key: client-secret
        - name: OAUTH2_PROXY_COOKIE_SECRET
          valueFrom:
            secretKeyRef:
              name: phoenix-oauth2-secret
              key: cookie-secret
        ports:
        - containerPort: 4180
```

**Update HTTPRoute**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: phoenix
  namespace: observability
spec:
  parentRefs:
  - name: http
    namespace: kagenti-system
    sectionName: https
  hostnames:
  - "phoenix.localtest.me"
  rules:
  - backendRefs:
    - name: phoenix-oauth2-proxy  # Route to OAuth2-Proxy instead of Phoenix directly
      port: 4180
```

**Source**: [OAuth2-Proxy Configuration](../03-authentication/oauth2-proxy.md) *(coming soon)*

---

### Resource Configuration

Production resource limits:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix
  namespace: observability
spec:
  replicas: 2  # HA mode
  template:
    spec:
      containers:
      - name: phoenix
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi
```

**Source**: [Phoenix Deployment Recommendations](https://arize.com/docs/phoenix/deployment)

---

## Troubleshooting

### Issue: No Traces in Phoenix UI

**Symptoms**: Phoenix UI shows no traces even though agents are running.

**Diagnosis**:

1. **Check Phoenix is receiving OTLP traces**:
   ```bash
   # Check Phoenix logs
   kubectl logs -n observability -l app=phoenix | grep "otlp"

   # Expected: Logs showing OTLP receiver accepting spans
   ```

2. **Check OTEL Collector is routing to Phoenix**:
   ```bash
   # Check collector logs
   kubectl logs -n observability -l app=otel-collector | grep "phoenix"

   # Check routing metrics
   kubectl port-forward -n observability svc/otel-collector 8888:8888
   curl http://localhost:8888/metrics | grep otelcol_exporter_sent_spans | grep phoenix
   ```

3. **Verify agent instrumentation**:
   ```bash
   # Check agent has OpenInference SDK
   kubectl exec -n team1 deploy/research-agent -- pip list | grep openinference

   # Expected: openinference-instrumentation packages installed
   ```

4. **Check traces have `openinference.span.kind`**:
   ```bash
   # View sample traces in OTEL Collector zPages
   kubectl port-forward -n observability svc/otel-collector 55679:55679
   open http://localhost:55679/debug/tracez

   # Look for "openinference.span.kind" attribute in spans
   ```

**Fix**:
```bash
# If missing instrumentation, add to agent Dockerfile:
RUN pip install \
  openinference-instrumentation \
  openinference-instrumentation-openai \
  opentelemetry-exporter-otlp

# Rebuild and redeploy agent
```

---

### Issue: Phoenix Pod CrashLoopBackOff

**Symptoms**: Phoenix pod restarts repeatedly.

**Diagnosis**:
```bash
# Check Phoenix pod logs
kubectl logs -n observability -l app=phoenix --previous

# Common errors:
# - "database connection failed" (PostgreSQL issue)
# - "port already in use" (port conflict)
# - "out of memory" (resource limits too low)
```

**Fix**:

1. **PostgreSQL connection issue**:
   ```bash
   # Check PostgreSQL is running
   kubectl get pods -n observability -l app=phoenix-postgres

   # Test connection
   kubectl exec -n observability deploy/phoenix -- \
     psql postgresql://phoenix:password@phoenix-postgres:5432/phoenix -c "SELECT 1"
   ```

2. **Resource limits**:
   ```yaml
   # Increase memory limit
   resources:
     limits:
       memory: 2Gi  # Increase from 1Gi
   ```

---

### Issue: High Phoenix Memory Usage

**Symptoms**: Phoenix pod using excessive memory (>4GB).

**Diagnosis**:
```bash
# Check memory usage
kubectl top pod -n observability -l app=phoenix

# Check trace volume
curl http://localhost:6006/graphql -d '{"query": "{ spans { totalCount } }"}'
```

**Fix**:

1. **Enable trace sampling** in agents:
   ```python
   from opentelemetry.sdk.trace.sampling import TraceIdRatioBased

   # Sample 10% of traces
   sampler = TraceIdRatioBased(0.1)
   provider = TracerProvider(sampler=sampler)
   ```

2. **Configure Phoenix retention**:
   ```yaml
   env:
   - name: PHOENIX_TRACE_RETENTION_DAYS
     value: "30"  # Delete traces older than 30 days
   ```

3. **Scale Phoenix horizontally**:
   ```yaml
   spec:
     replicas: 2  # Add more Phoenix instances
   ```

---

## Alternatives

### Alternative 1: Grafana Tempo Only

**Process**:
- Use Grafana Tempo for all traces (infrastructure + agents)
- View traces in Grafana Explore with TraceQL

**Pros**:
- ✅ Simpler architecture (single backend)
- ✅ Unified trace storage
- ✅ Grafana integration

**Cons**:
- ❌ No LLM-specific features (prompts, tokens, costs)
- ❌ Generic trace UI (not optimized for agents)
- ❌ No evaluation framework
- ❌ No prompt versioning

**When to Use**: Simple deployments without LLM-specific observability needs

**Source**: [Grafana Tempo](https://grafana.com/docs/tempo/)

---

### Alternative 2: Langfuse

**Process**:
- Deploy Langfuse for LLM observability
- Use Langfuse SDK for instrumentation

**Pros**:
- ✅ LLM-specific observability
- ✅ Prompt management
- ✅ Evaluation framework
- ✅ User feedback collection

**Cons**:
- ❌ Not OpenTelemetry-native (custom SDK)
- ❌ Commercial product (self-hosted version available)
- ❌ Less mature ecosystem

**When to Use**: Need prompt management and user feedback features

**Source**: [Langfuse](https://langfuse.com/)

---

### Alternative 3: Datadog APM

**Process**:
- Use Datadog APM for all traces
- LLM Observability add-on for agent traces

**Pros**:
- ✅ Fully managed
- ✅ LLM observability features
- ✅ Deep integration with infrastructure monitoring

**Cons**:
- ❌ Expensive (per-span pricing)
- ❌ Vendor lock-in
- ❌ Data sent to external service

**When to Use**: Already using Datadog, budget not a concern

**Source**: [Datadog LLM Observability](https://www.datadoghq.com/product/llm-observability/)

---

### Alternative 4: LangSmith

**Process**:
- Use LangSmith for LangChain application observability
- LangSmith cloud or self-hosted

**Pros**:
- ✅ Built by LangChain team (best LangChain integration)
- ✅ Prompt management and versioning
- ✅ Evaluation framework
- ✅ Dataset management

**Cons**:
- ❌ LangChain-specific (not framework-agnostic)
- ❌ Commercial product
- ❌ Not OpenTelemetry-based

**When to Use**: Using LangChain exclusively

**Source**: [LangSmith](https://www.langchain.com/langsmith)

---

## Next Steps

### For Development

1. **Add Phoenix instrumentation to your agent**:
   ```python
   from openinference.instrumentation.openai import OpenAIInstrumentor
   OpenAIInstrumentor().instrument()
   ```

2. **Set OTLP environment variables**:
   ```yaml
   env:
   - name: OTEL_EXPORTER_OTLP_ENDPOINT
     value: "http://otel-collector.observability.svc.cluster.local:4317"
   ```

3. **Deploy agent and view traces**:
   ```bash
   kubectl apply -f agent-deployment.yaml
   open https://phoenix.localtest.me:9443
   ```

### For Production

1. **Deploy PostgreSQL backend** for persistent trace storage
2. **Enable OAuth2-Proxy authentication** for Phoenix UI
3. **Configure trace sampling** to reduce volume
4. **Set up retention policies** (30-90 days for agent traces)
5. **Monitor Phoenix resource usage** and scale as needed

### Learn More

- [Distributed Tracing Architecture](./distributed-tracing.md) - Complete tracing system
- [OTEL Collector Configuration](../../components/02-observability/otel-collector/configmap.yaml) - Routing logic
- [Keycloak SSO](../03-authentication/keycloak.md) - OAuth2 authentication
- [GenAI Semantic Conventions](./genai-semantic-conventions.md) - MANDATORY compliance for agents

---

## References

### Official Documentation

- **Arize Phoenix**: [arize.com/docs/phoenix](https://arize.com/docs/phoenix/)
- **Phoenix Deployment**: [arize.com/docs/phoenix/deployment](https://arize.com/docs/phoenix/deployment)
- **Phoenix Tracing**: [arize.com/docs/phoenix/tracing](https://arize.com/docs/phoenix/tracing)
- **Phoenix Quickstart**: [arize.com/docs/phoenix/quickstart](https://arize.com/docs/phoenix/quickstart)

### Instrumentation Guides

- **OpenAI**: [OpenAI Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/openai)
- **LangChain**: [LangChain Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/langchain)
- **LlamaIndex**: [LlamaIndex Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/llamaindex)
- **CrewAI**: [CrewAI Instrumentation](https://arize.com/docs/phoenix/tracing/integrations-tracing/crewai)

### OpenTelemetry

- **OpenTelemetry**: [opentelemetry.io](https://opentelemetry.io/)
- **OpenInference Specification**: [github.com/Arize-ai/openinference](https://github.com/Arize-ai/openinference)
- **OTLP Specification**: [opentelemetry.io/docs/specs/otlp](https://opentelemetry.io/docs/specs/otlp/)

### Internal Documentation

- **Main README**: [../../README.md](../../README.md)
- **Quick Start Guide**: [../00-getting-started/quick-start.md](../00-getting-started/quick-start.md)
- **Distributed Tracing**: [./distributed-tracing.md](./distributed-tracing.md)
- **Grafana Dashboards**: [./grafana.md](./grafana.md)
- **Prometheus Metrics**: [./prometheus.md](./prometheus.md)

### Repository

- **GitHub**: [Ladas/kagenti-demo-deployment](https://github.com/Ladas/kagenti-demo-deployment)
- **Phoenix Configuration**: `components/02-observability/phoenix/`
- **OTEL Collector Configuration**: `components/02-observability/otel-collector/`
- **Agent Tests**: `tests/integration/test_observability.py`

---

**Last Updated**: 2025-11-12
**Document Version**: 1.0
**Maintained By**: Platform Engineering Team
**License**: Apache 2.0
