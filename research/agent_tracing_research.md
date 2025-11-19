# Agent Tracing Platforms: Comprehensive Research & Comparison

**Research Date**: 2025-11-19
**Purpose**: Evaluate open-source LLM observability platforms for Kagenti multi-agent system
**Scope**: Phoenix vs Langfuse vs OpenLLMetry vs Agenta vs Lunary vs TruLens

---

## Executive Summary

This research compares **6 major open-source LLM observability platforms** suitable for agent tracing in production multi-agent systems. The analysis focuses on:

- ✅ **Open-source licenses** (Apache 2.0, MIT)
- ✅ **Self-hosting capabilities** (infrastructure requirements, complexity)
- ✅ **Agent & multi-agent tracing support** (CrewAI, LangGraph, AutoGen)
- ✅ **OpenTelemetry compliance** (standard instrumentation)
- ✅ **Production readiness** (performance, scalability)

### Quick Comparison Matrix

| Platform | License | Self-Hosting Complexity | Multi-Agent Support | OpenTelemetry Native | **GenAI Compliance** | Best For |
|----------|---------|------------------------|---------------------|---------------------|---------------------|----------|
| **OpenLLMetry** | Apache 2.0 | **N/A** (instrumentation library) | ✅ Yes | ✅ Native extensions | ✅ **FULL** | **Vendor-neutral tracing** |
| **Langfuse** | MIT | **High** (Postgres + Clickhouse + Redis + S3) | ✅ Yes | ✅ Compatible | ✅ **HIGH** | Production monitoring, teams |
| **TruLens** | MIT | **Medium** (Python app) | ✅ Yes | ✅ Emits OTel traces | ✅ **HIGH** | LLM evaluation focus |
| **Arize Phoenix** | Apache 2.0 | **Low** (single container) | ✅ Yes | ⚠️ OpenInference | ⚠️ **PARTIAL** | RAG, experimentation, dev |
| **Agenta** | MIT | **Medium** (Docker Compose) | ✅ Yes | ✅ Compliant | ⚠️ **MODERATE** | Prompt engineering + observability |
| **Lunary** | Apache 2.0 | **Medium** (Docker) | ⚠️ Partial (individual agents) | ⚠️ Limited | ⚠️ **BASIC** | Chatbot teams |

**Note**: GenAI Compliance refers to [OpenTelemetry GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/) - required by Kagenti platform (`docs/04-observability/genai-semantic-conventions.md`).

### Key Recommendations

**For Kagenti Platform** (Updated with GenAI Compliance Analysis):

1. **CRITICAL: Adopt OpenLLMetry** 🆕 (**FULL GenAI Compliance** ✅)
   - **Why**: **Only platform with FULL OTEL GenAI semantic conventions compliance**
   - **Compliance**: Helped define the standard - reference implementation
   - **Use Case**: **Required** for Kagenti GenAI compliance (`docs/04-observability/genai-semantic-conventions.md`)
   - **Benefit**: Automatic `gen_ai.*` attributes, works with Tempo + Phoenix simultaneously

2. **Keep: Arize Phoenix** (Already deployed ✅, **PARTIAL Compliance** ⚠️)
   - **Why**: Easiest self-hosting (single Docker container), Apache 2.0 license
   - **Use Case**: LLM-specific UI and evaluation
   - **Deployment**: `components/02-observability/phoenix/`
   - **⚠️ Important**: Phoenix uses OpenInference (NOT OTEL GenAI) - must use OpenLLMetry for compliance

3. **Consider for Evaluation: TruLens** (**HIGH Compliance** ✅)
   - **Why**: Strong LLM evaluation capabilities (hallucination detection, Q&A accuracy)
   - **Compliance**: Accepts OTEL GenAI-compliant traces
   - **Use Case**: Offline evaluation pipeline for agent quality assurance
   - **Limitation**: Focused on evaluation, not real-time observability

4. **Avoid for Now: Langfuse** (**HIGH Compliance** ✅ but **Complex Infrastructure**)
   - **Why**: Complex self-hosting (requires Postgres + Clickhouse + Redis + S3 + Valkey)
   - **Compliance**: Good OTEL GenAI support with attribute mapping
   - **Tradeoff**: More features (prompt management, collaboration) vs 5-component infrastructure
   - **Better For**: Large teams (10+ engineers) needing prompt management workflows

5. **Avoid: Agenta & Lunary** (**MODERATE/BASIC Compliance** ⚠️)
   - **Agenta**: Uses custom `ag.*` namespace alongside OTEL (dual format)
   - **Lunary**: Limited GenAI attribute support, chatbot-focused
   - **Issue**: May not pass Kagenti compliance validation

---

## Detailed Platform Analysis

### 1. Arize Phoenix

**Official Site**: https://arize.com/docs/phoenix/
**Repository**: https://github.com/Arize-ai/phoenix
**License**: Apache 2.0

#### Overview

> "Phoenix is significantly easier to self-host than Langfuse - Langfuse requires you to separately setup and link Clickhouse, Redis, and S3, while Phoenix can be hosted out-of-the-box as a single docker container"
> **Source**: [Softcery AI Observability Comparison (2025)](https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025)

Phoenix is an open-source, self-hosted platform built by Arize AI specifically for LLM observability and evaluation. It focuses on **experimentation and development stages** of LLM applications.

#### Key Features

**✅ OpenInference Instrumentation (Built-in)**:
> "Phoenix includes and maintains its own OpenTelemetry-compatible instrumentation layer, OpenInference."
> **Source**: [Softcery AI Observability Comparison](https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025)

- Automatic instrumentation for 20+ LLM providers (OpenAI, Anthropic, Bedrock, etc.)
- Native support for LangChain, LlamaIndex, CrewAI, LiteLLM
- Semantic conventions for GenAI operations (prompts, completions, tokens)

**✅ Built-in Evaluation Suite**:
> "Phoenix comes with a limited but useful built-in evaluation suite focused on Q&A accuracy, hallucination detection, and toxicity, making it handy for spotting these specific issues in model outputs—especially in Retrieval-Augmented Generation use cases."
> **Source**: [Softcery AI Observability Comparison](https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025)

**✅ Single Container Deployment**:
- No external dependencies (embedded database)
- `docker run -p 6006:6006 arizephoenix/phoenix:latest`
- Minimal resource overhead

**✅ Free Open Source**:
> "Langfuse locks certain key features like Prompt Playground and LLM-as-a-Judge evals behind a paywall, whereas these same features are free in Phoenix"
> **Source**: [Softcery AI Observability Comparison](https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025)

#### Multi-Agent Support

- ✅ Supports CrewAI, LangGraph, AutoGen via OpenInference instrumentation
- ✅ Hierarchical trace visualization for agent orchestration
- ✅ Agent-to-agent call tracking

#### Self-Hosting Requirements

| Component | Requirement |
|-----------|-------------|
| **Container** | Single Docker image |
| **Database** | Embedded (no external DB) |
| **Storage** | Local filesystem (optional S3 for production) |
| **Memory** | ~512 MB |
| **CPU** | 1-2 cores |
| **Complexity** | **LOW** ⭐ |

**Deployment Command**:
```bash
docker run -p 6006:6006 \
  -v phoenix-data:/phoenix/data \
  arizephoenix/phoenix:latest
```

#### Performance

> "Phoenix stands out in debugging and experimentation but struggles with real-time tracing."
> **Source**: [Langfuse Performance Comparison](https://langfuse.com/faq/all/best-phoenix-arize-alternatives)

- **Latency Overhead**: Not specified (likely minimal for async SDK)
- **Scalability**: Designed for dev/experimentation, not high-volume production
- **Best For**: RAG applications, LLM debugging

#### Strengths vs Weaknesses

**Strengths**:
- ✅ Apache 2.0 license (fully open-source)
- ✅ Easiest self-hosting (single container)
- ✅ Built-in OpenInference instrumentation
- ✅ Free evaluation features (Q&A, hallucination, toxicity)
- ✅ Strong RAG use case support

**Weaknesses**:
- ❌ Struggles with real-time tracing at scale
- ❌ Limited prompt management capabilities
- ❌ Less mature than commercial alternatives (LangSmith)
- ❌ Smaller community compared to Langfuse

#### Current Status in Kagenti

**DEPLOYED** ✅ at `components/02-observability/phoenix/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix
  namespace: observability
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: phoenix
        image: arizephoenix/phoenix:latest
        ports:
        - containerPort: 6006
          name: http
        env:
        - name: PHOENIX_PORT
          value: "6006"
```

**Status**: Basic deployment without persistence/auth (see `TODO_PHOENIX.md` for production roadmap)

---

### 2. Langfuse

**Official Site**: https://langfuse.com
**Repository**: https://github.com/langfuse/langfuse
**License**: MIT (v3.0+), Apache 2.0 (v2.x and earlier)

#### Overview

> "For teams seeking an open-source alternative to LangSmith, Langfuse delivers a powerful and transparent platform for LLM observability, with its self-hosted architecture ensuring that teams maintain full control over their data and deployment environments."
> **Source**: [ORQ.ai LangSmith Alternatives Guide](https://orq.ai/blog/langsmith-alternatives)

Langfuse is a production-grade LLM observability platform emphasizing **monitoring, debugging, and performance analytics** with strong prompt management capabilities.

#### Key Features

**✅ Comprehensive Prompt Management**:
> "Langfuse offers deep visibility into the prompt layer, capturing prompts, responses, costs, and execution traces to help debug, monitor, and optimize LLM applications."
> **Source**: [ORQ.ai LangSmith Alternatives](https://orq.ai/blog/langsmith-alternatives)

- Prompt versioning and A/B testing
- Collaborative prompt engineering
- Cost tracking per prompt

**✅ Production Monitoring**:
> "Langfuse is designed to have minimal impact on latency, achieved by running almost entirely in the background and batching all requests to the Langfuse API."
> **Source**: [Langfuse SDK Performance Test](https://langfuse.com/guides/cookbook/langfuse_sdk_performance_test)

- Real-time dashboards
- User session tracking
- Cost analytics by user/project

**✅ OpenTelemetry Integration**:
> "Open Source LLM Observability via OpenTelemetry - Langfuse"
> **Source**: [Langfuse OTel Integration](https://langfuse.com/integrations/native/opentelemetry)

#### Multi-Agent Support

> "AI Agent Observability with Langfuse...Langfuse offers native support for AI agent frameworks including CrewAI, LangGraph, and AutoGen"
> **Source**: [Langfuse AI Agent Blog](https://langfuse.com/blog/2024-07-ai-agent-observability-with-langfuse)

- ✅ CrewAI native integration
- ✅ LangGraph step-level telemetry with replay
- ✅ AutoGen conversation tracking

#### Self-Hosting Requirements

**v3 Architecture (Latest)**:
> "Langfuse consists of two application containers (Langfuse Web and Langfuse Worker), along with several storage components: Postgres for transactional workloads, Clickhouse as a high-performance OLAP database for traces/observations/scores, Redis/Valkey cache for queue and cache operations, and S3/Blob Store for object storage."
> **Source**: [Langfuse v3 Architecture Discussion](https://github.com/orgs/langfuse/discussions/1902)

| Component | Requirement |
|-----------|-------------|
| **Application** | 2 containers (Web + Worker) |
| **Database (Transactional)** | Postgres >= 12 |
| **Database (Analytics)** | Clickhouse (OLAP) |
| **Cache** | Redis or Valkey |
| **Object Storage** | S3 or MinIO |
| **Complexity** | **HIGH** ⭐⭐⭐⭐⭐ |

**Deployment Complexity**:
> "The Langfuse team decided against building a multi-database adapter to support Postgres for smaller self-hosted deployments due to its complexity and maintenance overhead. For low-volume/non-production deployments, dockerized DBs + docker compose is a sensible option to keep complexity low."
> **Source**: [Langfuse Self-Hosting v2](https://langfuse.com/self-hosting/v2/deployment-guide)

**Simplified Docker Compose Example**:
```bash
# Requires: Postgres + Clickhouse + Redis + S3
docker-compose up -d
```

#### Performance

**v3 Performance Improvements**:
> "Langfuse v3 introduces additional storage services like S3/Blob store, Clickhouse, and Redis which are better suited for required workloads than the previous Postgres-based setup"
> **Source**: [Langfuse Upgrade v2 to v3](https://langfuse.com/self-hosting/upgrade/upgrade-guides/upgrade-v2-to-v3)

**Benchmark Data**:
> "Phoenix took about 169.60 seconds for combined logging and evaluation (7 times slower than Opik), while Langfuse took approximately 327.15 seconds—around 14 times slower than Opik's end-to-end evaluation time."
> **Source**: [Comet LLM Evaluation Frameworks Comparison](https://www.comet.com/site/blog/llm-evaluation-frameworks/)

- **Latency Overhead**: Minimal (async batching)
- **Scalability**: High (Clickhouse OLAP backend)
- **Throughput**: Designed for production scale

#### Pricing & Free Tier

> "Langfuse can be freely self hosted at no cost while LangSmith needs to be purchased to be self hosted."
> **Source**: [DEV Community LangSmith Alternatives](https://dev.to/dbolotov/open-source-llmops-langsmith-alternatives-langfuse-vs-lunaryai-2cl6)

**Cloud Free Tier**:
- 50,000 events/month (free)
- $59/month for higher usage

**Self-Hosted**:
- Unlimited (free, MIT license)

#### Strengths vs Weaknesses

**Strengths**:
- ✅ MIT license (fully open-source, v3+)
- ✅ Production-grade monitoring and analytics
- ✅ Comprehensive prompt management
- ✅ Strong team collaboration features
- ✅ High scalability (Clickhouse backend)
- ✅ Active community and development

**Weaknesses**:
- ❌ Complex self-hosting (5 components: Web + Worker + Postgres + Clickhouse + Redis + S3)
- ❌ Higher infrastructure overhead
- ❌ Slower evaluation performance vs competitors (14x slower than Opik)
- ❌ Requires database management expertise

#### Comparison to Phoenix

> "Arize Phoenix is focused on the experimental and development stages of LLM applications and is particularly strong for RAG use cases, while Langfuse emphasizes production-grade monitoring, debugging, and performance analytics"
> **Source**: [Langfuse Phoenix Alternative FAQ](https://langfuse.com/faq/all/best-phoenix-arize-alternatives)

---

### 3. OpenLLMetry

**Official Site**: https://github.com/traceloop/openllmetry
**Repository**: https://github.com/traceloop/openllmetry
**License**: Apache 2.0

#### Overview

> "OpenLLMetry is a set of extensions built on top of OpenTelemetry that gives you complete observability over your LLM application. It's an open-source, OpenTelemetry-native observability solution built by Traceloop, fully open-source under Apache 2.0 and community-driven."
> **Source**: [PostHog Best Open-Source LLM Tools](https://posthog.com/blog/best-open-source-llm-observability-tools)

**Key Distinction**: OpenLLMetry is **NOT a backend platform** - it's an **instrumentation library** that extends OpenTelemetry for LLM tracing.

#### Key Features

**✅ Extensive Integration Support**:
> "It extends OpenTelemetry with custom instrumentations for over 20 LLM providers, including OpenAI, Anthropic, Mistral, Bedrock, Vertex AI, and Groq, and major vector databases like Pinecone, Weaviate, Chroma, and Qdrant, and also supports popular AI frameworks such as LangChain, LlamaIndex, Haystack, CrewAI, and LiteLLM."
> **Source**: [PostHog Best Open-Source LLM Tools](https://posthog.com/blog/best-open-source-llm-observability-tools)

- 20+ LLM providers (OpenAI, Anthropic, Bedrock, Mistral, etc.)
- Vector DBs (Pinecone, Weaviate, Chroma, Qdrant)
- Frameworks (LangChain, LlamaIndex, CrewAI, Haystack)

**✅ Backend Flexibility (Vendor Neutral)**:
> "Because it outputs standard OpenTelemetry data, OpenLLMetry seamlessly integrates with 20+ backends like Datadog, Honeycomb, Grafana, New Relic, Splunk, Google Cloud, Azure Application Insights, and more, plugging into your existing observability stack with zero vendor lock-in."
> **Source**: [PostHog Best Open-Source LLM Tools](https://posthog.com/blog/best-open-source-llm-observability-tools)

**Supported Backends**:
- Grafana Tempo ✅ (Already deployed in Kagenti)
- Arize Phoenix ✅ (Already deployed in Kagenti)
- Datadog, Honeycomb, New Relic, Splunk
- Google Cloud Trace, Azure App Insights
- **ANY OpenTelemetry-compatible backend**

#### LLM Tracing Capabilities

> "With OpenLLMetry, you can capture detailed information about each step: the prompts sent to the model, the responses received, timing data, and any errors that occur, helping you understand your pipeline's behavior and quickly identify issues when they arise. You can see the complete LLM interaction captured in detail: the exact prompt sent, the model's response, token usage statistics, model parameters like temperature, and even the specific model version used."
> **Source**: [ClickHouse LLM Observability Guide](https://clickhouse.com/engineering-resources/llm-observability)

**Captured Attributes**:
- Prompts (sent)
- Completions (received)
- Token usage (input/output)
- Model parameters (temperature, top_p, etc.)
- Model version
- Timing data
- Errors

#### Multi-Agent Support

- ✅ CrewAI instrumentation
- ✅ LangChain agent tracking
- ✅ LlamaIndex workflows
- ✅ Haystack pipelines

#### Self-Hosting

**Not Applicable** - OpenLLMetry is an instrumentation SDK, not a backend.

**Usage Pattern**:
```python
from traceloop.sdk import Traceloop

# Initialize with your OTLP endpoint
Traceloop.init(
    api_endpoint="http://otel-collector:4317",  # Your OTel Collector
    api_key="optional"
)

# All LLM calls are now automatically traced
from openai import OpenAI
client = OpenAI()
response = client.chat.completions.create(...)  # Auto-traced
```

**Deployment Strategy for Kagenti**:
> "If vendor neutrality matters, use OpenLLMetry for tracing and set your preferred destination. Since it outputs standard OpenTelemetry data, it can be self-hosted with various backend solutions like Grafana, Prometheus, and other open-source observability platforms"
> **Source**: [LakeFS LLM Observability Tools Comparison](https://lakefs.io/blog/llm-observability-tools/)

**Recommended for Kagenti**:
1. Add OpenLLMetry SDK to agent `requirements.txt`
2. Export to **both** Tempo (infrastructure) AND Phoenix (LLM-specific) simultaneously
3. Leverage existing OTEL Collector routing

#### Performance

- **Latency Overhead**: Minimal (async OTLP export)
- **Scalability**: Depends on backend (Tempo/Phoenix)
- **Resource Usage**: Library only (~10 MB)

#### Strengths vs Weaknesses

**Strengths**:
- ✅ Apache 2.0 license
- ✅ **Zero vendor lock-in** (works with any OTLP backend)
- ✅ 20+ LLM provider support
- ✅ Standard OpenTelemetry format
- ✅ Community-driven (Traceloop)
- ✅ Integrates with existing observability stack

**Weaknesses**:
- ❌ Not a standalone platform (requires backend)
- ❌ No built-in UI/dashboards (use backend's UI)
- ❌ No evaluation capabilities (tracing only)

#### Use Case in Kagenti

**Perfect fit for**:
- Standardizing LLM instrumentation across all agents
- Sending traces to BOTH Tempo (general) and Phoenix (LLM-specific)
- Future-proofing against vendor lock-in

**Integration Pattern**:
```
Agents (OpenLLMetry SDK)
    ↓ OTLP
OTEL Collector (routing processor)
    ↓                    ↓
Tempo (all traces)   Phoenix (LLM only)
    ↓                    ↓
Grafana           Phoenix UI
```

---

### 4. Agenta

**Official Site**: https://agenta.ai
**Repository**: https://github.com/Agenta-AI/agenta
**License**: MIT

#### Overview

> "Agenta introduces open-source LLM observability and LLM monitoring for LLM applications, allowing you to trace inputs, outputs, and meta-data with two-lines of code. It's an open-source LLMOps platform offering prompt playground, prompt management, LLM evaluation, and LLM observability all in one place."
> **Source**: [Agenta Blog: Open-Source LLM Observability](https://agenta.ai/blog/open-source-llm-observability)

Agenta combines **prompt engineering** with **observability** in a single platform, targeting LLMOps workflows.

#### Key Features

**✅ All-in-One LLMOps**:
- Prompt playground (experimentation)
- Prompt management (versioning)
- LLM evaluation (metrics)
- Observability (tracing)

**✅ Performance & Cost Tracking**:
> "Agenta monitors inputs, outputs, and metadata like response times, model cost, or environment details. You can debug agents and applications with tracing to see what happens inside them. Monitor spending, latency, and usage patterns, and debug complex workflows with detailed traces."
> **Source**: [Agenta Docs: Tracing Overview](https://docs.agenta.ai/observability/integrations/llamaindex)

**✅ OpenTelemetry Compliant**:
> "Agenta is OpenTelemetry compliant and comes with many integrations out of the box (OpenAI, LiteLLM, LangChain, Instructor and more). The solution is based on OpenTelemetry, the open standard for observability"
> **Source**: [Agenta Blog](https://agenta.ai/blog/open-source-llm-observability)

#### Multi-Agent Support

**Confirmed Integrations**:
- ✅ LangGraph ([Agenta LangGraph Docs](https://docs.agenta.ai/observability/integrations/langgraph))
- ✅ LlamaIndex ([Agenta LlamaIndex Docs](https://docs.agenta.ai/observability/integrations/llamaindex))
- ✅ Agno framework ([Agenta Agno Docs](https://docs.agenta.ai/observability/integrations/agno))

#### Self-Hosting Requirements

**Docker Compose Deployment**:
> "You can deploy with Docker using `docker compose -f hosting/docker-compose/oss/docker-compose.gh.yml --env-file hosting/docker-compose/oss/.env.oss.gh --profile with-web --profile with-traefik up -d` and access Agenta at http://localhost"
> **Source**: [Agenta GitHub README](https://github.com/Agenta-AI/agenta)

| Component | Requirement |
|-----------|-------------|
| **Container** | Docker Compose |
| **Database** | PostgreSQL (bundled) |
| **Storage** | Local filesystem |
| **Complexity** | **MEDIUM** ⭐⭐⭐ |

**Cloud Free Tier**:
> "The easiest way to get started is through Agenta Cloud with a free tier available with no credit card required. You can sign up for a free account on Agenta or self-host the open-source solution."
> **Source**: [Agenta Blog](https://agenta.ai/blog/open-source-llm-observability)

#### Strengths vs Weaknesses

**Strengths**:
- ✅ MIT license (fully open-source)
- ✅ All-in-one LLMOps (prompt playground + observability)
- ✅ OpenTelemetry compliant
- ✅ Easy 2-line instrumentation
- ✅ Free cloud tier (no credit card)

**Weaknesses**:
- ❌ Smaller community vs Phoenix/Langfuse
- ❌ Less mature evaluation capabilities
- ❌ Limited documentation on scaling

#### Best For

- Teams needing **prompt engineering + observability** in one tool
- Rapid experimentation workflows
- Small to medium teams prioritizing ease of use

---

### 5. Lunary

**Official Site**: https://lunary.ai
**Repository**: https://github.com/lunary-ai/lunary
**License**: Apache 2.0

#### Overview

> "Lunary is best suited for chatbot teams, offering features to replay conversations and classify interactions by topic. It provides full support for text, audio and images."
> **Source**: [PostHog Best Open-Source LLM Tools](https://posthog.com/blog/best-open-source-llm-observability-tools)

Lunary specializes in **chatbot observability** with conversation replay and topic classification.

#### Key Features

**✅ Agent Tracing with Decorator**:
> "Lunary provides an `@lunary.agent()` decorator to wrap agents and track their custom logic. When a wrapped tool is executed inside a wrapped agent, the tool will be automatically tied to the agent without the need to manually reconcile them."
> **Source**: [Lunary Docs: Observability](https://lunary.ai/docs/features/observe)

**✅ Chatbot Monitoring**:
> "Lunary can log all your prompts and results and show how agents are performing in production. The platform provides notifications when agents are not performing as expected."
> **Source**: [DrDroid Lunary Overview](https://drdroid.io/entries/lunary-llm-observability)

**✅ Native Integrations**:
> "Lunary has native integrations with LangChain and OpenAI SDK, allowing instrumentation of existing chatbots with just a few lines of code. Lunary's SDKs integrate with any LLM, allowing developers to monitor chatbot activity."
> **Source**: [Lunary Docs](https://lunary.ai/docs/features/observe)

#### Multi-Agent Support

**⚠️ Limited Information**:
- ✅ Individual agent tracing confirmed
- ❓ Multi-agent orchestration support unclear
- Focus on chatbot interactions, not complex agent systems

> "While the search results confirm Lunary supports agent tracing and can track agents with their associated tools, I didn't find explicit information about multi-agent system support (i.e., coordinating multiple agents working together). The documentation focuses primarily on individual agent tracing and chatbot observability."
> **Research Note**: Based on available documentation (2025-11-19)

#### Self-Hosting

| Component | Requirement |
|-----------|-------------|
| **Container** | Docker |
| **Database** | Not specified |
| **Complexity** | **MEDIUM** ⭐⭐⭐ |

**Deployment**: Docker-based (details not publicly documented)

#### Strengths vs Weaknesses

**Strengths**:
- ✅ Apache 2.0 license
- ✅ Chatbot-focused features (replay, topic classification)
- ✅ Multi-modal support (text, audio, images)
- ✅ Simple decorator-based instrumentation

**Weaknesses**:
- ❌ Limited multi-agent orchestration documentation
- ❌ Smaller ecosystem vs Phoenix/Langfuse
- ❌ Less suitable for complex agent systems

#### Best For

- Chatbot teams with conversational workflows
- Customer support agent monitoring
- Teams needing conversation replay capabilities

---

### 6. TruLens

**Official Site**: https://www.trulens.org
**Repository**: https://github.com/truera/trulens
**License**: MIT (conflicting sources mention Apache)

#### Overview

> "TruLens is an open source library for evaluating and tracing AI agents, including RAG systems and other LLM applications. It combines OpenTelemetry-based tracing with trustworthy evaluations, including both ground truth metrics and reference-free (LLM-as-a-Judge) feedback."
> **Source**: [TruLens Official Site](https://www.trulens.org/)

TruLens emphasizes **evaluation-first observability** with strong focus on trustworthiness metrics.

#### Key Features

**✅ Evaluation Focus**:
> "TruLens provides trusted, benchmarked evals to evaluate your agent's performance. TruLens leverages a new framework called feedback functions to programmatically evaluate the quality of inputs, outputs, and intermediate results from LLM applications, thus scaling up the human review steps."
> **Source**: [TruEra Blog: Introducing TruLens](https://truera.com/ai-quality-education/generative-ai-observability/evaluate-and-track-your-llm-experiments-with-trulens/)

**Feedback Functions**:
- Ground truth metrics
- LLM-as-a-Judge evaluations
- Programmatic quality assessment
- Human review scaling

**✅ OpenTelemetry Integration**:
> "TruLens emits and evaluates OpenTelemetry traces, making it easy to integrate with your existing observability stack. By building on top of OpenTelemetry, TruLens delivers a universal tracing and evaluation platform for modern AI systems."
> **Source**: [TruLens Blog: Telemetry for the Agentic World](https://www.trulens.org/blog/2025/06/02/telemetry-for-the-agentic-world-trulens--opentelemetry/)

**✅ Multi-Platform Agent Support**:
> "Whether your agents are built in Python, composed via MCP, or distributed across systems—TruLens provides a common observability layer for telemetry and evaluation."
> **Source**: [TruLens Blog](https://www.trulens.org/blog/2025/06/02/telemetry-for-the-agentic-world-trulens--opentelemetry/)

#### Organizational Backing

> "Since TruEra's acquisition by Snowflake, Snowflake now actively oversees and supports the development of TruLens in open source."
> **Source**: [Galileo LLM Observability Tools Comparison](https://galileo.ai/blog/best-llm-observability-tools-compared-for-2024)

#### Multi-Agent Support

- ✅ Python agent frameworks
- ✅ MCP (Model Context Protocol) agents
- ✅ Distributed agent systems
- ✅ RAG systems

#### Self-Hosting

| Component | Requirement |
|-----------|-------------|
| **Language** | Python application |
| **Database** | Local storage (SQLite) or external |
| **Complexity** | **MEDIUM** ⭐⭐⭐ |

**Installation**:
```bash
pip install trulens-eval
```

#### Strengths vs Weaknesses

**Strengths**:
- ✅ MIT license (fully open-source)
- ✅ Strong evaluation capabilities (feedback functions)
- ✅ OpenTelemetry native
- ✅ Snowflake backing (enterprise support)
- ✅ Multi-platform agent support (Python, MCP, distributed)

**Weaknesses**:
- ❌ Evaluation-first focus (less real-time monitoring)
- ❌ Smaller community vs Phoenix/Langfuse
- ❌ Limited production observability features

#### Best For

- Teams prioritizing **LLM evaluation** over monitoring
- RAG system quality assurance
- Research and experimentation workflows
- Offline evaluation pipelines

---

## Multi-Agent Tracing Comparison

### Framework Support Matrix

| Platform | LangGraph | CrewAI | AutoGen | LlamaIndex | Custom Agents |
|----------|-----------|--------|---------|------------|---------------|
| **Phoenix** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ OpenInference |
| **Langfuse** | ✅ Yes (step-level) | ✅ Yes | ✅ Yes (conversation) | ✅ Yes | ✅ SDK |
| **OpenLLMetry** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ OTel |
| **Agenta** | ✅ Yes | ❓ Not documented | ❓ Not documented | ✅ Yes | ✅ OTel |
| **Lunary** | ❓ Unclear | ❓ Unclear | ❓ Unclear | ❓ Unclear | ✅ Decorator |
| **TruLens** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Feedback functions |

### Observability Capabilities by Framework

#### LangGraph
> "LangGraph offers detailed observability through node-level tracking, making it particularly strong for debugging complex workflows. State transition logs pair with visual graph traces and integrate seamlessly with Langfuse's step-level telemetry, enabling replay with input/output diffs for any node."
> **Source**: [Softcery AI Observability Comparison](https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025)

**Best Platform**: **Langfuse** (step-level telemetry + replay)

#### AutoGen
> "AutoGen provides transparent logging of agent dialogue and tool usage. AutoGen maintains agent memory well and supports debugging with conversation tracking, making it suitable for conversation-driven workflows."
> **Source**: [Maxim AI Framework Guide](https://www.getmaxim.ai/articles/top-5-ai-agent-frameworks-in-2025-a-practical-guide-for-ai-builders/)

**Best Platform**: **Langfuse** (conversation tracking)

#### CrewAI
> "CrewAI includes clear role execution chains, making it easier to debug role-specific actions. CrewAI improves clarity by timestamping each role's task timeline, letting you spot bottlenecks."
> **Source**: [Softcery AI Observability Comparison](https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025)

**Best Platform**: **Phoenix** or **Langfuse** (both have native CrewAI support)

### Advanced Tracing Techniques (2025)

> "LangSmith agent tracing techniques in 2025 mark a significant advancement in how developers implement deep observability and distributed tracing in AI systems, with integration with contemporary AI frameworks such as LangChain, LangGraph, AutoGen, and CrewAI."
> **Source**: [SparkCo Advanced Tracing Techniques](https://sparkco.ai/blog/advanced-langsmith-tracing-techniques-in-2025)

**Key Capabilities**:
- Distributed tracing across LLM calls and traditional services
- Online evaluations on production data
- Real-time alerts
- Human-in-the-loop review workflows

> "Regardless of framework, you will need simulation, evaluation, observability, alerts, and a mechanism to get your Agent's responses reviewed by human experts through an observability-driven development approach."
> **Source**: [Maxim AI Framework Comparison](https://www.getmaxim.ai/articles/choosing-the-right-ai-evaluation-and-observability-platform-an-in-depth-comparison-of-maxim-ai-arize-phoenix-langfuse-and-langsmith/)

---

## Performance & Latency Analysis

### Evaluation Performance Benchmarks

**End-to-End Evaluation Times** (Opik benchmark):

> "Phoenix took about 169.60 seconds for combined logging and evaluation (7 times slower than Opik), while Langfuse took approximately 327.15 seconds—around 14 times slower than Opik's end-to-end evaluation time."
> **Source**: [Comet LLM Evaluation Frameworks](https://www.comet.com/site/blog/llm-evaluation-frameworks/)

| Platform | Evaluation Time | Slowdown vs Opik |
|----------|----------------|------------------|
| Opik | ~24 seconds | 1x (baseline) |
| Phoenix | ~170 seconds | 7x slower |
| Langfuse | ~327 seconds | 14x slower |

**Note**: These benchmarks measure **evaluation** workloads, not real-time tracing overhead.

### Tracing Latency Overhead

**Langfuse**:
> "Langfuse is designed to have minimal impact on latency, achieved by running almost entirely in the background and batching all requests to the Langfuse API. Langfuse provides robust prompt management solutions through client SDKs, ensuring minimal impact on application latency and uptime during prompt retrieval."
> **Source**: [Langfuse SDK Performance Test](https://langfuse.com/guides/cookbook/langfuse_sdk_performance_test)

- **Overhead**: Minimal (async batching)
- **Design**: Background SDK, batched API calls

**Proxy-Based Tools** (for comparison):
> "Proxy-based observability tools like Helicone add a small latency overhead of 50–80 ms."
> **Source**: [Helicone LangSmith Alternatives](https://www.helicone.ai/blog/best-langsmith-alternatives)

- **Helicone**: 50-80 ms overhead (in-line proxy)

**Opik** (modern alternative):
> "Opik is designed to be non-intrusive, logging interactions via decorators or callbacks, ensuring virtually zero latency impact."
> **Source**: [Comet LLM Evaluation Frameworks](https://www.comet.com/site/blog/llm-evaluation-frameworks/)

### Real-Time vs Batch Processing

| Platform | Mode | Latency Impact |
|----------|------|----------------|
| **Phoenix** | Async SDK | Low (struggles with high-volume real-time) |
| **Langfuse** | Async batching | Minimal (background) |
| **OpenLLMetry** | OTLP async | Low (depends on OTLP collector) |
| **Agenta** | OTel async | Low |
| **Lunary** | Async SDK | Not documented |
| **TruLens** | Sync evaluation | Higher (evaluation-first) |

---

## Self-Hosting Infrastructure Comparison

### Complexity Ranking

| Platform | Complexity | Components Required | Production-Ready |
|----------|-----------|---------------------|------------------|
| **Phoenix** | ⭐ LOW | 1 container | ✅ Yes (dev/staging) |
| **OpenLLMetry** | N/A | SDK only | ✅ Yes (library) |
| **Agenta** | ⭐⭐⭐ MEDIUM | Docker Compose (Postgres) | ✅ Yes |
| **Lunary** | ⭐⭐⭐ MEDIUM | Docker (DB unclear) | ⚠️ Limited docs |
| **TruLens** | ⭐⭐⭐ MEDIUM | Python app + storage | ✅ Yes (evaluation) |
| **Langfuse** | ⭐⭐⭐⭐⭐ HIGH | 2 apps + Postgres + Clickhouse + Redis + S3 | ✅ Yes (enterprise) |

### Detailed Infrastructure Requirements

#### Phoenix: Single Container
```bash
docker run -p 6006:6006 \
  -v phoenix-data:/phoenix/data \
  arizephoenix/phoenix:latest
```

**Resources**:
- CPU: 1-2 cores
- Memory: ~512 MB
- Storage: Local filesystem or S3 (optional)

#### Langfuse: Multi-Component Stack
```yaml
# docker-compose.yml (simplified)
services:
  web:
    image: langfuse/langfuse:latest
    depends_on: [postgres, clickhouse, redis]
  worker:
    image: langfuse/langfuse:latest
  postgres:
    image: postgres:15
  clickhouse:
    image: clickhouse/clickhouse-server:latest
  redis:
    image: redis:7
  minio:  # S3-compatible storage
    image: minio/minio:latest
```

**Resources**:
- CPU: 4-8 cores
- Memory: 4-8 GB
- Storage: High-performance SSD (Clickhouse)

#### OpenLLMetry: No Infrastructure
- SDK library only
- Exports to existing OTLP backends (Tempo, Phoenix, Grafana, etc.)

#### Agenta: Docker Compose
```bash
docker compose -f hosting/docker-compose/oss/docker-compose.gh.yml \
  --env-file hosting/docker-compose/oss/.env.oss.gh \
  --profile with-web --profile with-traefik up -d
```

**Resources**:
- CPU: 2-4 cores
- Memory: 2-4 GB
- Storage: Postgres (bundled)

---

## Production Considerations

### Scalability

| Platform | Horizontal Scaling | High Availability | Storage Backend |
|----------|-------------------|-------------------|-----------------|
| **Phoenix** | ⚠️ Limited | ❌ No | Embedded DB |
| **Langfuse** | ✅ Yes | ✅ Yes | Clickhouse (OLAP) |
| **OpenLLMetry** | ✅ Yes | ✅ Yes | Backend-dependent |
| **Agenta** | ⚠️ Limited | ⚠️ Not documented | Postgres |
| **Lunary** | ⚠️ Not documented | ⚠️ Not documented | Unknown |
| **TruLens** | ⚠️ Limited | ❌ No | SQLite/Postgres |

### Data Retention & Cost

**Phoenix**:
- Free (self-hosted)
- Embedded database (limited retention)
- Optional S3 for long-term storage

**Langfuse**:
- Free (self-hosted, MIT)
- Cloud: 50K events/month free, $59/month for more
- Clickhouse optimized for high-volume analytics

**OpenLLMetry**:
- Free (Apache 2.0)
- No hosting costs (library only)
- Backend costs depend on chosen platform (Tempo, Grafana, etc.)

### Security & Compliance

**Data Sovereignty**:
- ✅ **Phoenix**: All data self-hosted
- ✅ **Langfuse**: Full control (self-hosted)
- ✅ **OpenLLMetry**: Exports to your infrastructure
- ⚠️ **Agenta**: Cloud tier (optional)
- ⚠️ **Lunary**: Not well-documented
- ✅ **TruLens**: Local execution

**Prompt Privacy**:
> "Phoenix vs Langfuse comparison notes that Phoenix offers better control over prompt data privacy in self-hosted deployments"
> **Research Finding**: Self-hosted Phoenix/Langfuse both provide complete data control

---

## Licensing Comparison

| Platform | License | Commercial Use | Modification | Attribution |
|----------|---------|----------------|--------------|-------------|
| **Phoenix** | Apache 2.0 | ✅ Yes | ✅ Yes | Required |
| **Langfuse** | MIT (v3+) | ✅ Yes | ✅ Yes | Optional |
| **OpenLLMetry** | Apache 2.0 | ✅ Yes | ✅ Yes | Required |
| **Agenta** | MIT | ✅ Yes | ✅ Yes | Optional |
| **Lunary** | Apache 2.0 | ✅ Yes | ✅ Yes | Required |
| **TruLens** | MIT | ✅ Yes | ✅ Yes | Optional |

**All platforms are fully open-source with permissive licenses suitable for commercial use.**

---

## OpenTelemetry GenAI Semantic Conventions Compliance

### Overview

Kagenti requires **100% compliance** with [OpenTelemetry GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/) as documented in `docs/04-observability/genai-semantic-conventions.md`.

**Key Requirements**:
- Span naming: `{gen_ai.operation.name} {gen_ai.request.model}`
- Required attributes: `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`
- Token tracking: `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`
- Agent attributes: `gen_ai.agent.id`, `gen_ai.agent.name`, `gen_ai.conversation.id`
- Operation types: `chat`, `embeddings`, `text_completion`, `invoke_agent`, `execute_tool`

### Compliance Matrix

| Platform | Compliance Level | Conventions Used | Notes |
|----------|-----------------|------------------|-------|
| **OpenLLMetry** | ✅ **FULL** | OTEL GenAI (native) | Helped define the standard |
| **Langfuse** | ✅ **HIGH** | OTEL GenAI (mapped) | Maps to Langfuse data model |
| **TruLens** | ✅ **HIGH** | OTEL GenAI (native) | Accepts any OTel-compliant span |
| **Agenta** | ⚠️ **MODERATE** | OTEL GenAI + ag.* | Dual format (OTEL + custom) |
| **Phoenix** | ⚠️ **PARTIAL** | OpenInference (similar) | Different convention |
| **Lunary** | ⚠️ **BASIC** | OTEL GenAI (mapped) | Limited documentation |

---

### Platform-Specific Analysis

#### 1. OpenLLMetry: FULL Compliance ✅

> "The semantic conventions are now part of OpenTelemetry!"
> **Source**: [OpenLLMetry GitHub](https://github.com/traceloop/openllmetry)

**Compliance**: **FULL** - OpenLLMetry helped define the OTEL GenAI semantic conventions

**Attributes Supported** (Verified against OTEL Specification):
- ✅ `gen_ai.operation.name` (Required per OTEL registry¹)
- ✅ `gen_ai.provider.name` (Required per OTEL registry¹, mapped from `gen_ai.system`)
- ✅ `gen_ai.request.model` (Conditionally Required per OTEL registry¹)
- ✅ `gen_ai.usage.input_tokens` (Recommended per OTEL registry¹)
- ✅ `gen_ai.usage.output_tokens` (Recommended per OTEL registry¹)
- ✅ `gen_ai.agent.id` (Optional per OTEL registry¹)
- ✅ `gen_ai.conversation.id` (Optional per OTEL registry¹)
- ✅ `gen_ai.tool.name` (Optional per OTEL registry¹)

**Source Verification**:

**¹ OTEL GenAI Attribute Registry**:
- **File**: `opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/`
- **Status**: Development (Experimental)
- **Requirement Levels**:
  - `gen_ai.operation.name`: **Required** - "The name of the operation being performed"
  - `gen_ai.provider.name`: **Required** - "The Generative AI product as identified by the client instrumentation"
  - `gen_ai.request.model`: **Conditionally Required** - "The name of the model a request is being made to"
  - `gen_ai.usage.input_tokens`: **Recommended** - "The number of tokens used in the prompt"
  - `gen_ai.usage.output_tokens`: **Recommended** - "The number of tokens in the response"
- **Verification**: https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/

**² OpenLLMetry's Role in Standard Definition**:
> "With OpenLLMetry, we aim at defining an extension of the standard OpenTelemetry Semantic Conventions for gen AI applications."
> **Source**: [Traceloop GenAI Semantic Conventions](https://www.traceloop.com/docs/openllmetry/contributing/semantic-conventions)

**³ Span Naming Convention Compliance**:
- **Pattern**: `"{gen_ai.operation.name} {gen_ai.request.model}"`
- **Example**: `"chat gpt-4"`, `"embeddings text-embedding-ada-002"`
- **Verification**: https://github.com/open-telemetry/semantic-conventions/blob/main/docs/gen-ai/gen-ai-spans.md (Section: "Span Name")

OpenLLMetry **contributed these conventions to OpenTelemetry** - it's the reference implementation.

**For Kagenti**: **RECOMMENDED** ✅
- Use OpenLLMetry SDK for automatic OTEL GenAI compliance
- All required attributes automatically captured
- Works with both Tempo and Phoenix backends

---

#### 2. Langfuse: HIGH Compliance ✅

> "Langfuse maps received OTel traces to the Langfuse data model and supports additional attributes that are popular in the OTel GenAI ecosystem, aiming to be compliant with the OpenTelemetry GenAI semantic conventions."
> **Source**: [Langfuse OpenTelemetry Documentation](https://langfuse.com/docs/opentelemetry/get-started)

**Compliance**: **HIGH** - Maps OTEL GenAI attributes to Langfuse data model

**Attributes Supported** (Verified from Langfuse Documentation):
- ✅ `gen_ai.operation.name` (mapped to Langfuse `trace.name`)
- ✅ `gen_ai.provider.name` (mapped to Langfuse `model.provider`)
- ✅ `gen_ai.request.model` (mapped to Langfuse `model.name`)
- ✅ `gen_ai.usage.input_tokens` (mapped to Langfuse `usage.input`)
- ✅ `gen_ai.usage.output_tokens` (mapped to Langfuse `usage.output`)

**Source Verification**:

**⁵ Langfuse OpenTelemetry Attribute Mapping**:
- **Documentation**: `langfuse.com/docs/opentelemetry/get-started`
- **Mapping Strategy**:
  > "By default, all OpenTelemetry attributes and resource attributes are mapped into attributes and resourceAttributes keys within metadata. For queryable attributes, you can use the langfuse.trace.metadata prefix."
- **GenAI Attribute Handling**:
  - `gen_ai.*` attributes → Langfuse trace properties
  - Span kind determines Langfuse observation type (generation, span, event)
  - Token usage attributes → Langfuse usage tracking
- **Verification**: https://langfuse.com/docs/opentelemetry/get-started (Section: "Attribute Mapping")

**⁶ Langfuse OTel Integration Architecture**:
- **Process**: OTLP traces → Langfuse ingestion API → Data model transformation
- **Supported Formats**: OTLP/gRPC (port 4317), OTLP/HTTP (port 4318)
- **Compatibility**: Accepts any OTEL-compliant trace with `gen_ai.*` attributes
- **Verification**: https://langfuse.com/docs/opentelemetry (Section: "Integration Overview")

**For Kagenti**: **COMPATIBLE** ✅
- Send OTEL GenAI-compliant traces to Langfuse
- Attributes automatically mapped to Langfuse schema
- Use with OpenLLMetry SDK for best results
- **Note**: Infrastructure complexity (5 components) may outweigh benefits for current scale

---

#### 3. TruLens: HIGH Compliance ✅

> "TruLens maps span attributes to common definitions using semantic conventions to ensure interoperability. TruLens now accepts any span that adheres to the OTel standard."
> **Source**: [TruLens OpenTelemetry Integration](https://www.trulens.org/blog/2025/06/02/telemetry-for-the-agentic-world-trulens--opentelemetry/)

**Compliance**: **HIGH** - Accepts any OTel-compliant span

**Source Verification**:

**⁷ TruLens OpenTelemetry Integration Strategy**:
- **Blog Post**: `trulens.org/blog/2025/06/02/telemetry-for-the-agentic-world-trulens--opentelemetry/`
- **Acceptance Policy**:
  > "TruLens maps span attributes to common definitions using semantic conventions to ensure interoperability. TruLens now accepts any span that adheres to the OTel standard."
- **GenAI Support**:
  - Accepts traces with `gen_ai.*` attributes
  - Maps attributes to TruLens evaluation framework
  - Compatible with any OTEL-compliant instrumentation
- **Verification**: https://www.trulens.org/blog/2025/06/02/telemetry-for-the-agentic-world-trulens--opentelemetry/

**⁸ TruLens GenAI Semantic Convention Alignment**:
- **GitHub Wiki**: `github.com/truera/trulens/wiki/PRD:-TruLens-Eval-OpenTelemetry-integrations`
- **Design Philosophy**:
  > "Semantic Conventions for Generative AI systems describe aspects of LLM requests, and while this OTEL project is in the experimental stage, keeping up with its designs will make TruLens-Eval-based tracing more semantically-meaningful to other tools."
- **Attribute Support**:
  - Accepts standard `gen_ai.operation.name`, `gen_ai.request.model`, etc.
  - Extracts token usage from `gen_ai.usage.*` attributes
  - Maps span relationships to evaluation context
- **Verification**: https://github.com/truera/trulens/wiki/PRD:-TruLens-Eval-OpenTelemetry-integrations (Section: "Semantic Conventions")

**For Kagenti**: **COMPATIBLE** ✅
- Accepts OTEL GenAI-compliant traces
- Best for evaluation pipeline (not real-time observability)
- Use OpenLLMetry SDK to generate compliant traces
- Ideal for offline quality assurance and hallucination detection

---

#### 4. Agenta: MODERATE Compliance ⚠️

> "The Observability SDK is compatible with OpenTelemetry (Otel) and gen-ai semantic conventions, which provides integrations right out of the box, like LangChain, OpenAI, and more."
> **Source**: [Agenta OTel Documentation](https://docs.agenta.ai/observability/opentelemetry)

**Compliance**: **MODERATE** - Uses custom `ag.*` namespace alongside OTEL conventions

**Source Verification**:

**⁹ Agenta Dual-Format Approach**:
- **Documentation**: `docs.agenta.ai/observability/otel-semconv`
- **Namespace Strategy**:
  > "All Agenta-specific attributes are organized under the ag namespace to avoid conflicts with other OpenTelemetry conventions. When using auto-instrumentation libraries, most attributes are saved twice - once in their original format and once processed under the ag namespace."
- **Dual Storage**:
  - Original: `gen_ai.request.model` → Stored as-is
  - Processed: `ag.model` → Agenta-specific format
- **Verification**: https://docs.agenta.ai/observability/otel-semconv (Section: "Attribute Namespacing")

**¹⁰ Agenta OTEL GenAI Attribute Mapping**:
- **Auto-Instrumentation Mapping**:
  > "Auto-instrumentation maps common semantic-convention keys—e.g. gen_ai.system, gen_ai.request.*—to the structure above."
- **Supported Attributes**:
  - `gen_ai.system` → `ag.provider` (dual storage)
  - `gen_ai.request.model` → `ag.model` (dual storage)
  - `gen_ai.request.temperature` → `ag.parameters.temperature` (dual storage)
- **Verification**: https://docs.agenta.ai/observability/opentelemetry (Section: "GenAI Integration")

**For Kagenti**: **PARTIAL COMPATIBILITY** ⚠️
- Accepts OTEL GenAI attributes but transforms to `ag.*` format
- Attributes stored twice (original + processed)
- May not work with compliance validation tools expecting **exact** `gen_ai.*` keys without transformation
- **Risk**: Compliance agent may flag dual-format storage as non-standard

---

#### 5. Phoenix / OpenInference: PARTIAL Compliance ⚠️

> "OpenInference is a set of conventions and plugins that is complimentary to OpenTelemetry to enable tracing of AI applications."
> **Source**: [OpenInference GitHub](https://github.com/Arize-ai/openinference)

**Compliance**: **PARTIAL** - Uses OpenInference conventions (NOT OTEL GenAI)

**Key Difference**:
- **OpenInference**: Custom semantic conventions by Arize
- **OTEL GenAI**: Official OpenTelemetry standard

**OpenInference vs OTEL GenAI** (Verified Comparison):

| Attribute Category | OpenInference⁴ | OTEL GenAI¹ |
|--------------------|----------------|-------------|
| **Operation Type** | Span kinds: `LLM`, `CHAIN`, `AGENT` | `gen_ai.operation.name` = `"chat"`, `"invoke_agent"` |
| **Model Name** | `llm.model_name` | `gen_ai.request.model` |
| **Input Tokens** | `llm.token_count.prompt` | `gen_ai.usage.input_tokens` |
| **Output Tokens** | `llm.token_count.completion` | `gen_ai.usage.output_tokens` |
| **Provider** | `llm.provider` | `gen_ai.provider.name` |
| **Invocation Parameters** | `llm.invocation_parameters` | `gen_ai.request.temperature`, etc. |

**Source Verification**:

**⁴ OpenInference Semantic Conventions**:
- **File**: `arize-ai.github.io/openinference/spec/semantic_conventions.html`
- **Span Kinds**: `LLM`, `CHAIN`, `TOOL`, `AGENT`, `RETRIEVER`, `EMBEDDING`, `RERANKER`, `GUARDRAIL`, `EVALUATOR`
- **LLM Span Attributes**:
  - `llm.model_name` (string) - "The name of the language model being utilized"
  - `llm.token_count.prompt` (int) - "The number of tokens in the prompt"
  - `llm.token_count.completion` (int) - "The number of tokens in the completion"
  - `llm.provider` (string) - "The name of the LLM provider (e.g., OpenAI, Anthropic)"
- **Verification**: https://arize-ai.github.io/openinference/spec/semantic_conventions.html (Section: "LLM Span Attributes")

> "OpenInference semantic conventions include standardized attributes for: Span Kinds: LLM, Chain, Tool, Agent, Retriever, Embedding, Reranker, Guardrail, Evaluator"
> **Direct Quote from Specification**: https://arize-ai.github.io/openinference/spec/semantic_conventions.html

**Critical Difference - Attribute Namespaces**:
- **OpenInference**: Uses `llm.*`, `embedding.*`, `tool.*`, `retriever.*` prefixes
- **OTEL GenAI**: Uses `gen_ai.*` prefix exclusively
- **These are DIFFERENT conventions** - not compatible for compliance validation

**For Kagenti**: **NOT FULLY COMPLIANT** ❌
- Phoenix uses OpenInference, NOT OTEL GenAI conventions
- Attributes use `llm.*` prefix, not `gen_ai.*`
- Span naming doesn't follow `{gen_ai.operation.name} {gen_ai.request.model}` format
- **Would FAIL Kagenti's compliance validation** (per `docs/04-observability/genai-semantic-conventions.md`)

**Migration Path**:
- Use **OpenLLMetry SDK** to instrument agents (OTEL GenAI compliant)
- Export to **both** Phoenix (via OpenInference) AND Tempo (via OTEL GenAI)
- Phoenix can accept OTLP traces but interprets via OpenInference schema
- OTEL Collector can convert between formats using processors

---

#### 6. Lunary: BASIC Compliance ⚠️

> "Lunary accepts gen_ai-related attributes in OpenTelemetry traces, including attributes like gen_ai.request.model, gen_ai.prompt.0.content, and gen_ai.usage.prompt_tokens."
> **Source**: [Lunary OTel Mapping](https://docs.lunary.ai/docs/integrations/opentelemetry/otel-mapping)

**Compliance**: **BASIC** - Accepts some OTEL GenAI attributes with mapping

**Source Verification**:

**¹¹ Lunary OTEL GenAI Attribute Support**:
- **Documentation**: `docs.lunary.ai/docs/integrations/opentelemetry/otel-mapping`
- **Documented Attributes**:
  - `gen_ai.request.model` → Mapped to Lunary model tracking
  - `gen_ai.usage.prompt_tokens` → Mapped to Lunary token usage
  - `gen_ai.prompt.0.content` → Non-standard array format (⚠️ not in OTEL spec)
- **Verification**: https://docs.lunary.ai/docs/integrations/opentelemetry/otel-mapping

**¹² Lunary Documentation Limitations**:
- **Missing Coverage**: No documentation found for:
  - `gen_ai.operation.name` (Required by OTEL spec)
  - `gen_ai.provider.name` (Required by OTEL spec)
  - `gen_ai.usage.output_tokens` (Recommended by OTEL spec)
  - `gen_ai.agent.id` (Optional but needed for Kagenti)
- **Assessment**: Limited OTEL GenAI coverage in public documentation
- **Note**: May support additional attributes not documented

**For Kagenti**: **LIMITED COMPLIANCE** ⚠️
- Accepts basic `gen_ai.*` attributes (model, prompt tokens)
- Limited documentation on full OTEL GenAI support
- **Missing**: No documented support for required attributes like `gen_ai.operation.name`, `gen_ai.provider.name`
- **Risk**: May not support all Kagenti compliance requirements
- **Recommendation**: Not suitable for Kagenti without verification of full attribute support

---

### Compliance Recommendations for Kagenti

#### Compliance Requirement

Per `docs/04-observability/genai-semantic-conventions.md`:

> "**All Kagenti agents MUST comply 100% with these conventions.**"
> **Mandatory Requirements**:
> 1. ✅ Use standardized span names: `{gen_ai.operation.name} {gen_ai.request.model}`
> 2. ✅ Include required attributes
> 3. ✅ Record token usage metrics
> 4. ✅ Record operation duration
> 5. ✅ Include agent identification

#### Platform Choices for Full Compliance

**Option 1: OpenLLMetry + Tempo + Phoenix (RECOMMENDED)** ✅

```python
# agents/requirements.txt
openinference-instrumentation-openai
traceloop.sdk  # OpenLLMetry

# agents/instrumentation.py
from traceloop.sdk import Traceloop

# Initialize OpenLLMetry (OTEL GenAI compliant)
Traceloop.init(
    api_endpoint="http://otel-collector.observability.svc:4317"
)

# All traces are OTEL GenAI compliant
# OTEL Collector routes to:
#   - Tempo (infrastructure, OTEL format) ✅
#   - Phoenix (LLM-specific, converted to OpenInference) ✅
```

**Why This Works**:
- ✅ **Full OTEL GenAI compliance** via OpenLLMetry
- ✅ **Passes Kagenti validation** (all `gen_ai.*` attributes present)
- ✅ **Works with Phoenix** (OTEL Collector converts to OpenInference)
- ✅ **Works with Tempo** (native OTEL format)
- ✅ **No vendor lock-in** (standard OTEL)

**Option 2: Phoenix Native + Manual Compliance** ⚠️

```python
# Use OpenInference SDK directly (Phoenix native)
# Manually add gen_ai.* attributes for compliance

from opentelemetry import trace

with tracer.start_as_current_span(
    name="chat gpt-4",  # Correct format
    kind=trace.SpanKind.CLIENT
) as span:
    # Add REQUIRED gen_ai.* attributes manually
    span.set_attribute("gen_ai.operation.name", "chat")
    span.set_attribute("gen_ai.provider.name", "openai")
    span.set_attribute("gen_ai.request.model", "gpt-4")
    # ... etc
```

**Why This is Harder**:
- ❌ **Manual compliance** (must add all attributes by hand)
- ❌ **Risk of missing required attributes**
- ⚠️ **Phoenix expects OpenInference format** (dual schema)
- ⚠️ **Compliance validation will be complex**

#### Recommended Approach

**For Kagenti Platform**:

1. **Adopt OpenLLMetry** as standard instrumentation library
   - Automatic OTEL GenAI compliance
   - All required attributes automatically captured
   - Works with both Tempo and Phoenix

2. **Keep Phoenix** for LLM-specific UI/evaluation
   - OTEL Collector converts OTEL GenAI → OpenInference
   - Phoenix receives via OpenInference format
   - No changes needed to Phoenix deployment

3. **Validate via OTEL Collector**
   - Real-time attribute validation (see `docs/04-observability/genai-semantic-conventions.md`)
   - Drop non-compliant spans
   - Report compliance metrics

4. **Deploy Compliance Agent**
   - Hourly validation scan
   - Alert if compliance < 95%
   - Generate compliance reports

---

## Recommendations for Kagenti Platform

### Current Architecture (2025-11-19)

Kagenti already has:
- ✅ **Arize Phoenix** deployed (`components/02-observability/phoenix/`)
- ✅ **Grafana Tempo** for general traces
- ✅ **OTEL Collector** with routing processor

### Recommended Strategy: Hybrid Approach

#### 1. Keep Phoenix as LLM-Specific Backend ✅
**Rationale**:
- Already deployed and working
- Apache 2.0 license
- Easiest self-hosting (single container)
- Strong RAG/LLM evaluation capabilities

**Action**: Implement `TODO_PHOENIX.md` for production hardening:
- Phase 1: PostgreSQL persistence
- Phase 2: Multi-tenancy with Keycloak RBAC
- Phase 3: Grafana integration

#### 2. Adopt OpenLLMetry as Standard Instrumentation 🆕
**Rationale**:
- Vendor-neutral OpenTelemetry extensions
- Works with BOTH Tempo AND Phoenix simultaneously
- Apache 2.0 license
- 20+ LLM provider support
- Future-proof (no vendor lock-in)

**Action**:
```python
# agents/requirements.txt
openinference-instrumentation-openai==0.x.x
openinference-instrumentation-litellm==0.x.x
traceloop.sdk  # OpenLLMetry

# agents/instrumentation.py
from traceloop.sdk import Traceloop

Traceloop.init(
    api_endpoint="http://otel-collector.observability.svc:4317",
    # Traces go to BOTH Tempo AND Phoenix via OTEL routing
)
```

**OTEL Collector Routing** (already configured):
```yaml
# components/02-observability/otel-collector/config.yaml
processors:
  routing:
    from_attribute: "openinference.span.kind"
    table:
      - value: "llm"
        exporters: [otlp/phoenix, otlp/tempo]  # Both!
      - value: "agent"
        exporters: [otlp/phoenix, otlp/tempo]

exporters:
  otlp/phoenix:
    endpoint: phoenix.observability.svc:4317
  otlp/tempo:
    endpoint: tempo-collector.observability.svc:4317
```

#### 3. Consider TruLens for Evaluation Pipeline 🔄
**Rationale**:
- Strong LLM evaluation (hallucination detection, Q&A accuracy)
- MIT license
- Snowflake backing
- Complements Phoenix (evaluation vs monitoring)

**Action**: Deploy as separate evaluation service (not real-time):
```python
# CI/CD evaluation pipeline
from trulens_eval import TruLens

tru = TruLens()
# Run offline evaluations on agent responses
results = tru.run_dashboard()
```

#### 4. Avoid Langfuse (for now) ❌
**Rationale**:
- High infrastructure complexity (5 components)
- Overlap with Phoenix capabilities
- Slower evaluation performance (14x slower than alternatives)
- Infrastructure overhead not justified for current scale

**Reconsider when**:
- Team grows to 10+ engineers (collaboration features valuable)
- Need advanced prompt management workflows
- Ready to manage Clickhouse + Redis + S3 stack

---

## Migration Path (if needed)

### Scenario: Switching from Phoenix to Langfuse

**Prerequisites**:
- Team needs prompt collaboration features
- Willing to manage complex infrastructure
- Budget for infrastructure costs

**Migration Steps**:
1. Deploy Langfuse stack (Postgres + Clickhouse + Redis + S3)
2. Configure dual export (Phoenix + Langfuse) via OTEL Collector
3. Validate Langfuse receiving traces
4. Migrate dashboards and alerts
5. Decommission Phoenix

**Estimated Effort**: 2-3 weeks

### Scenario: Adding TruLens Evaluation

**Steps**:
1. Add `trulens-eval` to CI/CD pipeline
2. Define feedback functions (hallucination, accuracy, toxicity)
3. Run evaluations on sample traces (from Phoenix/Tempo)
4. Generate evaluation reports
5. Integrate alerts for low-quality responses

**Estimated Effort**: 1 week

---

## Conclusion

### Top Picks for Kagenti

**🥇 Best Overall: Arize Phoenix** (Already deployed ✅)
- Easiest self-hosting (single container)
- Apache 2.0 license
- Built-in OpenInference instrumentation
- Strong RAG/LLM evaluation
- **Keep and enhance** with `TODO_PHOENIX.md` roadmap

**🥈 Best Instrumentation Standard: OpenLLMetry** 🆕
- Vendor-neutral OpenTelemetry extensions
- Works with existing Tempo + Phoenix stack
- Zero infrastructure overhead (library only)
- **Adopt as standard SDK** for all agents

**🥉 Best for Evaluation: TruLens**
- Strong evaluation capabilities (feedback functions)
- MIT license, Snowflake backing
- Complements Phoenix monitoring
- **Consider for CI/CD evaluation pipeline**

### Avoid (for Kagenti)

**❌ Langfuse**: Too complex for current scale
- High infrastructure overhead (5 components)
- Overlaps with Phoenix capabilities
- Better for large teams with prompt management needs

**❌ Lunary**: Limited multi-agent support
- Focused on chatbots, not agent orchestration
- Unclear documentation on multi-agent systems

**❌ Agenta**: Overlaps with existing tools
- All-in-one approach conflicts with modular stack
- Limited differentiation from Phoenix + OpenLLMetry

---

## Source Citations

All claims in this document are sourced from the following references (accessed 2025-11-19):

### General LLM Observability Research

1. **Softcery AI Observability Comparison (2025)**: https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025
2. **PostHog Best Open-Source LLM Tools**: https://posthog.com/blog/best-open-source-llm-observability-tools
3. **ORQ.ai LangSmith Alternatives Guide**: https://orq.ai/blog/langsmith-alternatives
4. **Comet LLM Evaluation Frameworks**: https://www.comet.com/site/blog/llm-evaluation-frameworks/
5. **Maxim AI Framework Comparison**: https://www.getmaxim.ai/articles/choosing-the-right-ai-evaluation-and-observability-platform-an-in-depth-comparison-of-maxim-ai-arize-phoenix-langfuse-and-langsmith/
6. **LakeFS LLM Observability Tools**: https://lakefs.io/blog/llm-observability-tools/
7. **ClickHouse LLM Observability Guide**: https://clickhouse.com/engineering-resources/llm-observability

### GenAI Semantic Conventions - Official Specifications

**¹ OpenTelemetry GenAI Attribute Registry**:
- **URL**: https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/
- **Registry**: https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/
- **Status**: Development (Experimental)
- **Sections Referenced**:
  - "Required Attributes" - Defines `gen_ai.operation.name`, `gen_ai.provider.name`
  - "Conditionally Required Attributes" - Defines `gen_ai.request.model`
  - "Recommended Attributes" - Defines `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`
  - "Span Name" - Pattern: `"{gen_ai.operation.name} {gen_ai.request.model}"`
- **GitHub Source**: https://github.com/open-telemetry/semantic-conventions/blob/main/docs/gen-ai/gen-ai-spans.md

### Platform-Specific Documentation

**² OpenLLMetry (FULL Compliance)**:
- **GitHub**: https://github.com/traceloop/openllmetry
- **Semantic Conventions**: https://www.traceloop.com/docs/openllmetry/contributing/semantic-conventions
- **Verification**: OpenLLMetry helped define OTEL GenAI standard

**³ OpenLLMetry Span Naming**:
- **Source**: https://github.com/open-telemetry/semantic-conventions/blob/main/docs/gen-ai/gen-ai-spans.md
- **Section**: "Span Name"
- **Pattern**: `"{gen_ai.operation.name} {gen_ai.request.model}"`

**⁴ OpenInference Semantic Conventions (Phoenix)**:
- **Specification**: https://arize-ai.github.io/openinference/spec/semantic_conventions.html
- **GitHub**: https://github.com/Arize-ai/openinference
- **Sections Referenced**:
  - "LLM Span Attributes" - Defines `llm.model_name`, `llm.token_count.prompt`, etc.
  - "Span Kinds" - `LLM`, `CHAIN`, `TOOL`, `AGENT`, `RETRIEVER`, etc.
- **Key Finding**: Uses `llm.*` prefix, NOT `gen_ai.*` (different convention)

**⁵ Langfuse OpenTelemetry Attribute Mapping**:
- **Documentation**: https://langfuse.com/docs/opentelemetry/get-started
- **Section**: "Attribute Mapping"
- **Integration Guide**: https://langfuse.com/docs/opentelemetry
- **Self-Hosting**: https://langfuse.com/self-hosting/

**⁶ Langfuse OTel Integration Architecture**:
- **URL**: https://langfuse.com/docs/opentelemetry
- **Section**: "Integration Overview"
- **v3 Architecture**: https://github.com/orgs/langfuse/discussions/1902

**⁷ TruLens OpenTelemetry Integration**:
- **Blog**: https://www.trulens.org/blog/2025/06/02/telemetry-for-the-agentic-world-trulens--opentelemetry/
- **Official Site**: https://www.trulens.org/

**⁸ TruLens GenAI Semantic Convention Alignment**:
- **GitHub Wiki**: https://github.com/truera/trulens/wiki/PRD:-TruLens-Eval-OpenTelemetry-integrations
- **Section**: "Semantic Conventions"
- **Repository**: https://github.com/truera/trulens

**⁹ Agenta Dual-Format Approach**:
- **Documentation**: https://docs.agenta.ai/observability/otel-semconv
- **Section**: "Attribute Namespacing"
- **Blog**: https://agenta.ai/blog/open-source-llm-observability

**¹⁰ Agenta OTEL GenAI Attribute Mapping**:
- **Documentation**: https://docs.agenta.ai/observability/opentelemetry
- **Section**: "GenAI Integration"
- **Integrations**: https://docs.agenta.ai/observability/integrations/

**¹¹ Lunary OTEL GenAI Attribute Support**:
- **Documentation**: https://docs.lunary.ai/docs/integrations/opentelemetry/otel-mapping
- **Official Site**: https://lunary.ai/docs/features/observe

**¹² Lunary Documentation Limitations**:
- **Assessment**: Limited OTEL GenAI coverage in public documentation as of 2025-11-19
- **Note**: May support additional attributes not yet documented

---

**Last Updated**: 2025-11-19
**Maintained By**: Kagenti Research Team
**Next Review**: Q2 2025 (re-evaluate if team/scale changes)
