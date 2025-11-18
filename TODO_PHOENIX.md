# TODO: Phoenix LLM Observability - Multi-Tenancy & RBAC Configuration

**Date Created:** 2025-11-17
**Status:** 🔴 Not Started
**Priority:** HIGH
**Owner:** Platform Team

---

## Executive Summary

This document outlines the implementation plan for configuring **Arize Phoenix** LLM observability platform with **multi-tenancy and RBAC** to enable namespace-based agent debugging and trace isolation for the Kagenti platform.

**Goal**: Configure Phoenix so users can:
- ✅ See only traces from agents they have access to (e.g., `team1` namespace)
- ✅ Authenticate via Keycloak (same SSO as rest of platform)
- ✅ Use Projects to organize traces by team/namespace
- ✅ Debug agents with the same RBAC as Kubernetes users
- ✅ Start with admin user, extend to user-specific access later

**Current State**: Phoenix deployed with OAuth2-Proxy for authentication, but **no RBAC, no persistence, no projects configured**.

---

## Table of Contents

1. [Current Phoenix Architecture](#current-phoenix-architecture)
2. [Phoenix RBAC & Authentication Capabilities](#phoenix-rbac--authentication-capabilities)
3. [Agent Integration & Trace Flow](#agent-integration--trace-flow)
4. [Multi-Tenancy Strategy](#multi-tenancy-strategy)
5. [Action Items (Phased Roadmap)](#action-items-phased-roadmap)
6. [Implementation Details](#implementation-details)
7. [Testing Strategy](#testing-strategy)
8. [Known Limitations](#known-limitations)
9. [Future Enhancements](#future-enhancements)

---

## Current Phoenix Architecture

### 🏗️ Deployment Overview

**Location**: `components/02-observability/phoenix/`

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Current Phoenix Setup                            │
└─────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│  Users (Browser)                                                    │
│  https://phoenix.localtest.me:9443                                 │
└────────────────┬───────────────────────────────────────────────────┘
                 │
                 ↓ HTTPS (Gateway API)
┌────────────────────────────────────────────────────────────────────┐
│  OAuth2-Proxy (phoenix-oauth2-proxy)                               │
│  Namespace: oauth2-proxy                                           │
│  - Keycloak authentication (kagenti realm)                         │
│  - Client: phoenix                                                 │
│  - Passes access token to upstream                                 │
└────────────────┬───────────────────────────────────────────────────┘
                 │
                 ↓ HTTP (ClusterIP)
┌────────────────────────────────────────────────────────────────────┐
│  Phoenix (deployment/phoenix)                                      │
│  Namespace: observability                                          │
│  Image: arizephoenix/phoenix:latest                                │
│  Ports:                                                            │
│    - 6006: Web UI (HTTP)                                           │
│    - 4317: OTLP gRPC (traces)                                      │
│  Storage: NONE (ephemeral - data lost on restart!)                 │
│  Auth: DISABLED (relies on OAuth2-Proxy)                           │
│  Istio: DISABLED (sidecar.istio.io/inject: "false")               │
└────────────────┬───────────────────────────────────────────────────┘
                 │
                 ↑ OTLP/gRPC (port 4317)
┌────────────────────────────────────────────────────────────────────┐
│  OTEL Collector (otel-collector)                                   │
│  Namespace: observability                                          │
│  Routing: OpenInference spans → Phoenix ONLY                       │
│           (Infrastructure spans → Tempo)                           │
│  Processors:                                                       │
│    - resourcedetection: Adds k8s metadata                         │
│    - attributes: Baggage propagation (user.id, tenant.id, etc.)   │
│    - routing: Routes by openinference.span.kind attribute          │
└────────────────┬───────────────────────────────────────────────────┘
                 │
                 ↑ OTLP/gRPC (port 4317)
┌────────────────────────────────────────────────────────────────────┐
│  Agents (team1 namespace)                                          │
│  - research-agent                                                  │
│  - code-agent                                                      │
│  - orchestrator-agent                                              │
│                                                                    │
│  OTEL Config (from agent.py):                                      │
│    OTEL_EXPORTER_OTLP_ENDPOINT:                                    │
│      http://otel-collector.observability.svc:4317                 │
│    OTEL_SERVICE_NAME: research-agent (etc.)                        │
│                                                                    │
│  Instrumentation:                                                  │
│    - openinference.instrumentation.langchain (auto-instrumented)  │
│    - opentelemetry (manual span creation)                         │
└────────────────────────────────────────────────────────────────────┘
```

### 📄 Current Configuration Files

**Deployment** (`components/02-observability/phoenix/deployment.yaml`):
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
          - containerPort: 6006  # Web UI
            name: http
          - containerPort: 4317  # OTLP gRPC (not exposed yet!)
            name: grpc
        env:
          - name: PHOENIX_PORT
            value: "6006"
          - name: PHOENIX_HOST
            value: "0.0.0.0"
        # ⚠️ MISSING: Database URL, Auth config, Projects
```

**Service** (`components/02-observability/phoenix/service.yaml`):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: phoenix
  namespace: observability
spec:
  type: ClusterIP
  ports:
    - port: 6006
      name: http
    # ⚠️ MISSING: Port 4317 for OTLP gRPC
```

**OAuth2-Proxy** (`components/00-infrastructure/oauth2-proxy/phoenix-proxy.yaml`):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix-oauth2-proxy
  namespace: oauth2-proxy
spec:
  template:
    spec:
      containers:
      - name: oauth2-proxy
        args:
          - --provider=oidc
          - --oidc-issuer-url=http://keycloak.keycloak.svc:8080/realms/kagenti
          - --client-id=phoenix
          - --upstream=http://phoenix.observability.svc:6006
          - --pass-access-token=true  # ✅ Passes JWT to Phoenix
          - --set-authorization-header=true
```

### 🚨 Critical Issues with Current Setup

1. **❌ No Persistence**: Phoenix uses in-memory storage (SQLite ephemeral)
   - All traces lost on pod restart
   - No retention policy
   - Cannot support production workloads

2. **❌ No Authentication in Phoenix**: OAuth2-Proxy authenticates, but Phoenix doesn't know the user
   - Phoenix has no concept of users
   - All traces visible to everyone
   - No RBAC enforcement

3. **❌ No Projects**: All traces dumped into default project
   - Cannot organize by namespace/team
   - No isolation between teams
   - Cannot implement per-team access control

4. **❌ OTLP Port Not Exposed**: Phoenix's gRPC port (4317) not accessible
   - **WAIT**: OTEL Collector routes to Phoenix via internal service
   - Actually OK! `otel-collector → phoenix.observability.svc:4317` works

5. **❌ No Namespace Metadata**: Agents don't send namespace in traces
   - OTEL Collector's `resourcedetection` adds `k8s.namespace.name`
   - But agents deployed locally may not have k8s context
   - Need to explicitly set in agent deployment

---

## Phoenix RBAC & Authentication Capabilities

### 🔐 Authentication System

**Phoenix Native Authentication** (as of September 2024):
- Enabled via `PHOENIX_ENABLE_AUTH=true`
- Supports three authentication methods:
  1. **Built-in login** (username/password stored in PostgreSQL)
  2. **OAuth2/OIDC** (Google, AWS Cognito, Microsoft Entra ID, Keycloak)
  3. **API Keys** (system keys vs user keys)

**Environment Variables**:
```bash
# Enable authentication
PHOENIX_ENABLE_AUTH=true

# JWT signing secret (must be long, random string)
PHOENIX_SECRET=<64-char-random-string>

# Admin API secret (for programmatic API key creation)
PHOENIX_ADMIN_SECRET=<another-random-string>

# Optional: Secure cookies (requires HTTPS)
PHOENIX_USE_SECURE_COOKIES=true
```

**Default Admin User** (on first startup with auth enabled):
- Email: `admin@localhost`
- Password: Must be set on first login

### 👥 RBAC Roles

Phoenix has **three built-in roles**:

| Role     | Permissions                                                                 |
|----------|-----------------------------------------------------------------------------|
| **Admin**   | Full system control, create/delete users, manage all projects, system API keys |
| **Member**  | Add traces/experiments, create projects, change own password/username          |
| **Viewer**  | Read-only access, can view traces/projects, cannot create/modify               |

**Key RBAC Features**:
- ✅ Users can be assigned to projects
- ✅ Admins can manage all projects
- ✅ Members can create own projects
- ✅ Viewers have read-only access
- ❌ **No namespace-based automatic assignment** (manual project membership)
- ❌ **No attribute-based access control (ABAC)** (e.g., filter by k8s namespace)

### 🗂️ Projects for Trace Organization

**What are Projects?**
- Logical containers for traces, experiments, datasets
- Each project has its own trace store
- Users can be assigned to projects (via RBAC)
- Traces sent to specific project via `PHOENIX_PROJECT_NAME` env var or API

**How Traces are Routed to Projects**:

**Option 1: Static Project Assignment (Agent-level)**
```python
# In agent code (agent.py)
import os
os.environ["PHOENIX_PROJECT_NAME"] = "team1-agents"

# All traces from this agent → "team1-agents" project
```

**Option 2: Dynamic Project Assignment (Trace-level)**
```python
# Using Phoenix Python SDK
from phoenix.trace import using_project

with using_project("team1-agents"):
    # Traces in this context → "team1-agents" project
    run_agent()
```

**Option 3: REST API for Project Management**
```bash
# Create project via REST API (requires PHOENIX_ADMIN_SECRET)
curl -X POST "http://phoenix:6006/v1/projects" \
  -H "Authorization: Bearer $ADMIN_API_KEY" \
  -d '{"name": "team1-agents", "description": "Team 1 Agent Traces"}'
```

**Project Limitations**:
- ⚠️ **No automatic assignment by trace attributes** (e.g., k8s.namespace.name)
- ⚠️ **Projects are NOT namespaces** (flat list, no hierarchy)
- ⚠️ **OTEL Collector cannot route to projects** (requires Phoenix SDK in agents)

### 🔑 API Keys

Phoenix supports two types of API keys:

**System Keys**:
- Act on behalf of the system (not tied to a user)
- Can access all projects
- Used for infrastructure/CI

**User Keys**:
- Tied to a specific user
- Inherit user's role and project access
- Used for personal development

**Creating API Keys** (requires `PHOENIX_ADMIN_SECRET`):
```bash
# Create system key via REST API
curl -X POST "http://phoenix:6006/v1/api-keys" \
  -H "Authorization: Bearer $ADMIN_SECRET" \
  -d '{
    "name": "ci-key",
    "expires_at": "2026-01-01T00:00:00Z"
  }'
```

---

## Agent Integration & Trace Flow

### 🔄 Current Agent → Phoenix Trace Flow

```
┌────────────────────────────────────────────────────────────────────┐
│ Agent Code (research-agent/agent.py)                               │
│                                                                    │
│ 1. Setup OTEL Tracer                                               │
│    - Endpoint: http://otel-collector.observability.svc:4317       │
│    - Service Name: research-agent                                 │
│    - Resource: service.name=research-agent                        │
│                                                                    │
│ 2. LangChain Instrumentation (OpenInference)                       │
│    from openinference.instrumentation.langchain import \           │
│      LangChainInstrumentor                                         │
│    LangChainInstrumentor().instrument()                            │
│                                                                    │
│ 3. Execute Agent (auto-traced)                                     │
│    graph = create_research_graph()                                 │
│    output = graph.astream(input)                                   │
│                                                                    │
│ 4. Spans Created (OpenInference Semantic Conventions)              │
│    - openinference.span.kind = CHAIN                               │
│    - openinference.span.kind = LLM                                 │
│    - openinference.span.kind = TOOL                                │
│    - Attributes: input.value, output.value, llm.model, etc.       │
└────────────────┬───────────────────────────────────────────────────┘
                 │
                 ↓ OTLP/gRPC
┌────────────────────────────────────────────────────────────────────┐
│ OTEL Collector (otel-collector.observability.svc)                  │
│                                                                    │
│ Processors:                                                        │
│   1. resourcedetection                                             │
│      Adds: k8s.namespace.name, k8s.pod.name, k8s.deployment.name  │
│                                                                    │
│   2. attributes                                                    │
│      Adds: cluster.name, deployment.environment                    │
│      Propagates baggage: user.id, tenant.id, task.type            │
│                                                                    │
│   3. routing (by openinference.span.kind)                          │
│      if span has openinference.span.kind → Phoenix                │
│      else → Tempo                                                  │
│                                                                    │
│ Export Decision:                                                   │
│   ✅ OpenInference spans (LLM, CHAIN, TOOL) → Phoenix              │
│   ✅ Infrastructure spans (HTTP, DB) → Tempo                       │
│   ⚠️ NO project routing (Phoenix handles project assignment)      │
└────────────────┬───────────────────────────────────────────────────┘
                 │
                 ↓ OTLP/gRPC (to Phoenix endpoint)
┌────────────────────────────────────────────────────────────────────┐
│ Phoenix (phoenix.observability.svc:4317)                           │
│                                                                    │
│ Receives:                                                          │
│   - Trace ID (W3C trace context)                                   │
│   - Spans with OpenInference attributes                           │
│   - Resource attributes (k8s.namespace.name, service.name, etc.)  │
│                                                                    │
│ Current Behavior (NO PROJECTS):                                    │
│   → All traces dumped into "default" project                       │
│   → No user association                                            │
│   → No namespace-based filtering                                   │
│                                                                    │
│ ⚠️ PROBLEM: Phoenix cannot route to projects automatically!       │
│             Agents must set PHOENIX_PROJECT_NAME env var           │
└────────────────────────────────────────────────────────────────────┘
```

### 🧩 Agent Environment Variables

**Current Agent Deployment** (`agent-examples-local/k8s/research-agent-deployment.yaml`):
```yaml
spec:
  template:
    spec:
      containers:
      - name: agent
        env:
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.observability.svc:4317"
        - name: OTEL_SERVICE_NAME
          value: "research-agent"
        # ⚠️ MISSING: PHOENIX_PROJECT_NAME for project routing
        # ⚠️ MISSING: k8s namespace metadata in resource attributes
```

**What Needs to be Added**:
```yaml
env:
# Phoenix project assignment (if using Phoenix SDK)
- name: PHOENIX_PROJECT_NAME
  value: "team1-agents"  # Or use namespace: $(NAMESPACE)

# OR: Use k8s.namespace.name resource attribute (via Downward API)
- name: K8S_NAMESPACE_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace

# OTEL resource attributes (for filtering in Phoenix)
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "k8s.namespace.name=$(K8S_NAMESPACE_NAME),team.name=team1"
```

### 📊 Trace Attributes Available for Filtering

**From OTEL Collector's resourcedetection processor**:
- `k8s.namespace.name`: Agent's Kubernetes namespace (e.g., `team1`)
- `k8s.pod.name`: Pod name (e.g., `research-agent-7f8d9c-xyz`)
- `k8s.deployment.name`: Deployment name (e.g., `research-agent`)
- `service.name`: OTEL service name (e.g., `research-agent`)

**From agents (OpenInference)**:
- `openinference.span.kind`: CHAIN, LLM, TOOL, AGENT, RETRIEVER, EMBEDDING
- `llm.model_name`: LLM model used (e.g., `granite3.2:8b`)
- `input.value`: User prompt (potentially sensitive!)
- `output.value`: Agent response (potentially sensitive!)

**Custom attributes we can add**:
- `team.name`: Team identifier (e.g., `team1`)
- `user.id`: User who triggered the agent (from baggage)
- `tenant.id`: Tenant identifier for multi-tenancy

---

## Multi-Tenancy Strategy

### 🎯 Goal: Namespace-Based Access Control

**Requirement**: Users can only see traces from agents in namespaces they have access to.

**Example**:
- User `alice@example.com` has K8s RBAC access to `team1` namespace
- Alice should see traces from: `research-agent.team1`, `code-agent.team1`
- Alice should NOT see traces from: `research-agent.team2`

### 🏗️ Architecture Options

#### Option 1: One Phoenix Instance per Namespace (Strong Isolation)

**Deployment**:
```
team1 namespace:
  - phoenix-team1 (separate deployment)
  - PostgreSQL (team1 DB)
  - Agents send to: phoenix-team1.team1.svc:4317

team2 namespace:
  - phoenix-team2 (separate deployment)
  - PostgreSQL (team2 DB)
  - Agents send to: phoenix-team2.team2.svc:4317
```

**Pros**:
- ✅ Complete data isolation (separate DBs)
- ✅ No risk of cross-namespace data leakage
- ✅ Scales horizontally per team
- ✅ Simple RBAC (K8s namespace RBAC = Phoenix access)

**Cons**:
- ❌ High resource overhead (N Phoenix instances)
- ❌ No cross-team trace correlation
- ❌ Complex to manage (N deployments)
- ❌ OTEL Collector needs namespace-aware routing

**Verdict**: ❌ **NOT RECOMMENDED** - Too complex for initial implementation

---

#### Option 2: Shared Phoenix + Projects (Soft Isolation) ✅ RECOMMENDED

**Deployment**:
```
observability namespace:
  - phoenix (single deployment)
  - PostgreSQL (shared DB)
  - Projects: team1-agents, team2-agents, admin-agents

Agents (team1 namespace):
  - env: PHOENIX_PROJECT_NAME=team1-agents
  - Traces → phoenix → "team1-agents" project

Agents (team2 namespace):
  - env: PHOENIX_PROJECT_NAME=team2-agents
  - Traces → phoenix → "team2-agents" project
```

**Access Control**:
```
Phoenix Users:
  - alice@example.com (role: Member)
    - Assigned to: team1-agents project
    - Can see: team1 traces only

  - bob@example.com (role: Member)
    - Assigned to: team2-agents project
    - Can see: team2 traces only

  - admin@example.com (role: Admin)
    - Can see: ALL projects
```

**Pros**:
- ✅ Single Phoenix deployment (simple ops)
- ✅ Project-based RBAC (built-in Phoenix feature)
- ✅ Cross-team correlation possible (for admins)
- ✅ Low resource overhead

**Cons**:
- ⚠️ Soft isolation (data in same DB, relies on Phoenix RBAC)
- ⚠️ Manual project assignment (agents must set `PHOENIX_PROJECT_NAME`)
- ⚠️ Cannot auto-sync with K8s RBAC (manual user management)

**Verdict**: ✅ **RECOMMENDED** - Best balance of simplicity and isolation

---

#### Option 3: Hybrid - Shared Phoenix + PostgreSQL Schema Isolation

**Deployment**:
```
observability namespace:
  - phoenix (single deployment)
  - PostgreSQL (single DB, multiple schemas)

PostgreSQL Schemas:
  - team1_traces (Phoenix project: team1-agents)
  - team2_traces (Phoenix project: team2-agents)
  - default (Phoenix project: admin-agents)

Agents:
  - env: PHOENIX_SQL_DATABASE_SCHEMA=team1_traces
  - env: PHOENIX_PROJECT_NAME=team1-agents
```

**Pros**:
- ✅ Database-level isolation (stronger than Option 2)
- ✅ Single Phoenix deployment
- ✅ Easier to backup/restore per team

**Cons**:
- ⚠️ Complex configuration (per-team schema setup)
- ❌ Phoenix doesn't natively support dynamic schema routing
- ❌ Would require custom Phoenix deployment per schema

**Verdict**: ⚠️ **FUTURE ENHANCEMENT** - Good for production, complex for MVP

---

### 📝 Selected Strategy: Shared Phoenix + Projects

**Implementation Plan**:

1. **Phase 1: Enable Phoenix Authentication & RBAC**
   - Deploy PostgreSQL for persistence
   - Enable `PHOENIX_ENABLE_AUTH=true`
   - Configure Keycloak OAuth2 integration
   - Create admin user

2. **Phase 2: Create Projects for Each Namespace**
   - Create project: `team1-agents`
   - Create project: `team2-agents`
   - Create project: `admin-agents`

3. **Phase 3: Configure Agents to Use Projects**
   - Add `PHOENIX_PROJECT_NAME=team1-agents` to agents in `team1` namespace
   - Add `PHOENIX_PROJECT_NAME=team2-agents` to agents in `team2` namespace

4. **Phase 4: Assign Users to Projects**
   - Create Phoenix users (synced from Keycloak)
   - Assign `alice@example.com` → `team1-agents` project (Member role)
   - Assign `bob@example.com` → `team2-agents` project (Member role)
   - Assign `admin@example.com` → ALL projects (Admin role)

5. **Phase 5: Test Isolation**
   - Alice logs in → sees only team1 traces
   - Bob logs in → sees only team2 traces
   - Admin logs in → sees all traces

---

## Action Items (Phased Roadmap)

### ✅ Phase 0: Research & Planning (CURRENT)

**Goal**: Understand Phoenix capabilities and design multi-tenancy strategy

- [x] Research Phoenix RBAC and authentication
- [x] Research Phoenix projects and trace organization
- [x] Analyze current agent OTEL configuration
- [x] Design multi-tenancy strategy
- [x] Document current architecture
- [ ] Review with team and get approval

**Deliverables**:
- [x] TODO_PHOENIX.md (this document)

---

### 🟡 Phase 1: Enable Persistence & Authentication

**Goal**: Deploy PostgreSQL backend and enable Phoenix authentication

**Duration**: 1 week

#### Tasks:

**1.1: Deploy PostgreSQL for Phoenix**

Create `components/02-observability/phoenix/postgres/` directory:

**StatefulSet** (`statefulset.yaml`):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: phoenix-postgres
  namespace: observability
spec:
  serviceName: phoenix-postgres
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
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_DB
          value: phoenix
        - name: POSTGRES_USER
          value: phoenix
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: phoenix-postgres-secret
              key: password
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 20Gi  # Adjust based on trace volume
```

**Secret** (`secret.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: phoenix-postgres-secret
  namespace: observability
type: Opaque
stringData:
  password: changeme  # ⚠️ Use sealed-secrets or external-secrets in prod
```

**Service** (`service.yaml`):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: phoenix-postgres
  namespace: observability
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: phoenix-postgres
```

**Kustomization** (`kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: observability

resources:
  - statefulset.yaml
  - service.yaml
  - secret.yaml
```

**GitOps Steps**:
```bash
# 1. Create directory
mkdir -p components/02-observability/phoenix/postgres

# 2. Create files
vim components/02-observability/phoenix/postgres/statefulset.yaml
vim components/02-observability/phoenix/postgres/service.yaml
vim components/02-observability/phoenix/postgres/secret.yaml
vim components/02-observability/phoenix/postgres/kustomization.yaml

# 3. Update parent kustomization
vim components/02-observability/phoenix/kustomization.yaml
# Add: - postgres/

# 4. Commit and push
git add components/02-observability/phoenix/postgres/
git commit -m "feat(phoenix): Add PostgreSQL backend for persistence"
git push origin feature/phoenix-auth

# 5. Sync via ArgoCD
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web

# 6. Verify
kubectl get statefulset -n observability phoenix-postgres
kubectl get pvc -n observability
kubectl logs -n observability phoenix-postgres-0
```

---

**1.2: Generate Phoenix Secrets**

Create `components/02-observability/phoenix/secrets/` directory:

**Generate secrets script** (`generate-secrets.sh`):
```bash
#!/bin/bash
# Generate Phoenix authentication secrets

set -euo pipefail

NAMESPACE="observability"
SECRET_NAME="phoenix-auth-secrets"

# Generate 64-character random strings
PHOENIX_SECRET=$(openssl rand -base64 48 | tr -d '\n')
PHOENIX_ADMIN_SECRET=$(openssl rand -base64 48 | tr -d '\n')

# Create secret YAML
cat > phoenix-auth-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  PHOENIX_SECRET: "${PHOENIX_SECRET}"
  PHOENIX_ADMIN_SECRET: "${PHOENIX_ADMIN_SECRET}"
EOF

echo "✅ Generated ${SECRET_NAME}.yaml"
echo "⚠️  IMPORTANT: Do not commit this file to Git!"
echo "📋 Apply with: kubectl apply -f phoenix-auth-secrets.yaml"
```

**Usage**:
```bash
cd components/02-observability/phoenix/secrets/
chmod +x generate-secrets.sh
./generate-secrets.sh

# Apply secret
kubectl apply -f phoenix-auth-secrets.yaml

# Verify
kubectl get secret -n observability phoenix-auth-secrets
```

**⚠️ Security Note**: Use **Sealed Secrets** or **External Secrets Operator** in production!

---

**1.3: Update Phoenix Deployment with Auth & Persistence**

Update `components/02-observability/phoenix/deployment.yaml`:

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
          - containerPort: 4317  # ✅ ADDED: OTLP gRPC
            name: grpc
        env:
          # Server config
          - name: PHOENIX_PORT
            value: "6006"
          - name: PHOENIX_HOST
            value: "0.0.0.0"
          - name: PHOENIX_GRPC_PORT
            value: "4317"

          # ✅ NEW: Database connection
          - name: PHOENIX_SQL_DATABASE_URL
            value: "postgresql://phoenix:$(POSTGRES_PASSWORD)@phoenix-postgres.observability.svc:5432/phoenix"
          - name: POSTGRES_PASSWORD
            valueFrom:
              secretKeyRef:
                name: phoenix-postgres-secret
                key: password

          # ✅ NEW: Authentication
          - name: PHOENIX_ENABLE_AUTH
            value: "true"
          - name: PHOENIX_SECRET
            valueFrom:
              secretKeyRef:
                name: phoenix-auth-secrets
                key: PHOENIX_SECRET
          - name: PHOENIX_ADMIN_SECRET
            valueFrom:
              secretKeyRef:
                name: phoenix-auth-secrets
                key: PHOENIX_ADMIN_SECRET

          # ✅ NEW: OAuth2 (Keycloak)
          - name: PHOENIX_OAUTH2_KEYCLOAK_CLIENT_ID
            value: "phoenix"
          - name: PHOENIX_OAUTH2_KEYCLOAK_CLIENT_SECRET
            valueFrom:
              secretKeyRef:
                name: phoenix-client-secret
                key: CLIENT_SECRET
          - name: PHOENIX_OAUTH2_KEYCLOAK_OIDC_CONFIG_URL
            value: "https://keycloak.localtest.me:9443/realms/kagenti/.well-known/openid-configuration"

          # ✅ NEW: Working directory (for local SQLite fallback)
          - name: PHOENIX_WORKING_DIR
            value: "/data"

          # ✅ NEW: Retention policy
          - name: PHOENIX_DEFAULT_RETENTION_POLICY_DAYS
            value: "30"  # Keep traces for 30 days

          # ✅ NEW: CSRF trusted origins
          - name: PHOENIX_CSRF_TRUSTED_ORIGINS
            value: "https://phoenix.localtest.me:9443"

        volumeMounts:
          # ✅ NEW: Mount for working directory (fallback)
          - name: phoenix-data
            mountPath: /data

        resources:
          requests:
            cpu: 200m    # ↑ Increased (database queries)
            memory: 512Mi  # ↑ Increased
          limits:
            cpu: 1000m
            memory: 2Gi

      volumes:
        - name: phoenix-data
          emptyDir: {}  # For working directory (not critical data)
```

**Update Service** (`components/02-observability/phoenix/service.yaml`):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: phoenix
  namespace: observability
spec:
  type: ClusterIP
  ports:
    - port: 6006
      targetPort: 6006
      name: http
    # ✅ ADDED: OTLP gRPC port
    - port: 4317
      targetPort: 4317
      name: grpc
  selector:
    app: phoenix
```

**GitOps Steps**:
```bash
# 1. Update deployment
vim components/02-observability/phoenix/deployment.yaml

# 2. Update service
vim components/02-observability/phoenix/service.yaml

# 3. Commit and push
git add components/02-observability/phoenix/
git commit -m "feat(phoenix): Enable authentication and PostgreSQL persistence"
git push origin feature/phoenix-auth

# 4. Sync via ArgoCD
argocd app sync observability --port-forward --port-forward-namespace argocd --grpc-web --force

# 5. Wait for rollout
kubectl rollout status deployment/phoenix -n observability

# 6. Check logs
kubectl logs -n observability deployment/phoenix --tail=50
```

**Expected Log Output**:
```
INFO: Phoenix starting...
INFO: Database migration running...
INFO: Database schema: public
INFO: Authentication enabled
INFO: Creating default admin user: admin@localhost
INFO: OAuth2 provider configured: keycloak
INFO: Server listening on 0.0.0.0:6006
INFO: gRPC server listening on 0.0.0.0:4317
```

---

**1.4: Configure Keycloak OAuth2 Client for Phoenix**

Phoenix needs to authenticate users via Keycloak using OAuth2/OIDC.

**Update Keycloak post-install job** (`components/01-platform/keycloak/post-install-job.yaml`):

Add Phoenix client creation to the existing job script:

```bash
# Create Phoenix OIDC client
echo "Creating Phoenix OIDC client..."
PHOENIX_CLIENT_JSON=$(cat <<EOF
{
  "clientId": "phoenix",
  "name": "Phoenix LLM Observability",
  "description": "Phoenix LLM Observability Platform",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": true,
  "authorizationServicesEnabled": false,
  "redirectUris": [
    "https://phoenix.localtest.me:9443/*",
    "https://phoenix.localtest.me:9443/oauth2/callback"
  ],
  "webOrigins": [
    "https://phoenix.localtest.me:9443"
  ],
  "defaultClientScopes": [
    "profile",
    "email",
    "roles"
  ],
  "attributes": {
    "pkce.code.challenge.method": "S256"
  }
}
EOF
)

PHOENIX_CLIENT_SECRET=$(curl -s -X POST \
  "http://keycloak.keycloak.svc:8080/admin/realms/kagenti/clients" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PHOENIX_CLIENT_JSON" | jq -r '.secret // empty')

# Create client secret for Phoenix
if [ -n "$PHOENIX_CLIENT_SECRET" ]; then
  kubectl create secret generic phoenix-client-secret \
    --from-literal=CLIENT_SECRET="$PHOENIX_CLIENT_SECRET" \
    --namespace=observability \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✅ Phoenix client created with secret"
else
  echo "⚠️ Phoenix client created (check Keycloak for secret)"
fi
```

**GitOps Steps**:
```bash
# 1. Update Keycloak post-install job
vim components/01-platform/keycloak/post-install-job.yaml

# 2. Commit and push
git add components/01-platform/keycloak/
git commit -m "feat(keycloak): Add Phoenix OIDC client configuration"
git push origin feature/phoenix-auth

# 3. Delete existing job to trigger recreation
kubectl delete job -n keycloak keycloak-post-install || true

# 4. Sync via ArgoCD
argocd app sync platform --port-forward --port-forward-namespace argocd --grpc-web

# 5. Verify client created
kubectl get secret -n observability phoenix-client-secret
```

---

**1.5: Test Authentication**

**Access Phoenix UI**:
```bash
# 1. Open Phoenix in browser
open https://phoenix.localtest.me:9443

# 2. Should redirect to Keycloak login
# 3. Login with Keycloak credentials:
#    - Username: admin
#    - Password: admin123 (or your Keycloak admin password)

# 4. After login, should redirect to Phoenix
# 5. Phoenix prompts to set new admin password (first login)
#    - Email: admin@localhost
#    - Set new password

# 6. Should see Phoenix dashboard
```

**Test API Access**:
```bash
# 1. Create API key via Phoenix UI
# Settings → API Keys → Create System Key
# Copy the key

# 2. Test API with key
export PHOENIX_API_KEY="px_..."  # Your API key

curl -H "Authorization: Bearer $PHOENIX_API_KEY" \
  https://phoenix.localtest.me:9443/v1/projects

# Should return: {"data": []}  (no projects yet)
```

**Deliverables**:
- [x] PostgreSQL deployed and running
- [x] Phoenix deployment updated with auth + persistence
- [x] Phoenix secrets generated and applied
- [x] Keycloak OAuth2 client configured
- [x] Phoenix UI accessible via Keycloak SSO
- [x] Admin user configured
- [x] API key created and tested

---

### 🟡 Phase 2: Create Projects for Namespaces

**Goal**: Create Phoenix projects for each team namespace

**Duration**: 3 days

#### Tasks:

**2.1: Create Projects via REST API**

Create script `scripts/phoenix/create-projects.sh`:

```bash
#!/bin/bash
# Create Phoenix projects for each team namespace

set -euo pipefail

PHOENIX_URL="${PHOENIX_URL:-https://phoenix.localtest.me:9443}"
ADMIN_SECRET="${PHOENIX_ADMIN_SECRET:-}"  # From phoenix-auth-secrets

if [ -z "$ADMIN_SECRET" ]; then
  echo "❌ PHOENIX_ADMIN_SECRET not set"
  echo "Usage: PHOENIX_ADMIN_SECRET=<secret> ./create-projects.sh"
  exit 1
fi

# List of namespaces to create projects for
NAMESPACES=("team1" "team2" "admin")

for ns in "${NAMESPACES[@]}"; do
  PROJECT_NAME="${ns}-agents"
  echo "Creating project: $PROJECT_NAME"

  curl -X POST "$PHOENIX_URL/v1/projects" \
    -H "Authorization: Bearer $ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$PROJECT_NAME\",
      \"description\": \"Agent traces from $ns namespace\"
    }" || echo "⚠️ Project may already exist"

  echo "✅ Project created: $PROJECT_NAME"
done

# List all projects
echo ""
echo "📋 All projects:"
curl -s "$PHOENIX_URL/v1/projects" \
  -H "Authorization: Bearer $ADMIN_SECRET" | jq '.data[] | {name, description}'
```

**Usage**:
```bash
# 1. Get PHOENIX_ADMIN_SECRET from Kubernetes
export PHOENIX_ADMIN_SECRET=$(kubectl get secret phoenix-auth-secrets -n observability -o jsonpath='{.data.PHOENIX_ADMIN_SECRET}' | base64 -d)

# 2. Run script
chmod +x scripts/phoenix/create-projects.sh
./scripts/phoenix/create-projects.sh

# Output:
# Creating project: team1-agents
# ✅ Project created: team1-agents
# Creating project: team2-agents
# ✅ Project created: team2-agents
# Creating project: admin-agents
# ✅ Project created: admin-agents
#
# 📋 All projects:
# {
#   "name": "team1-agents",
#   "description": "Agent traces from team1 namespace"
# }
# ...
```

---

**2.2: Create Projects via Phoenix UI**

**Alternative: Manual creation via UI**:

1. Open Phoenix UI: `https://phoenix.localtest.me:9443`
2. Login as admin
3. Navigate to: **Projects** → **Create Project**
4. Create:
   - Name: `team1-agents`
   - Description: `Agent traces from team1 namespace`
5. Repeat for `team2-agents`, `admin-agents`

---

**2.3: Verify Projects Created**

```bash
# Via API
curl -s "https://phoenix.localtest.me:9443/v1/projects" \
  -H "Authorization: Bearer $PHOENIX_ADMIN_SECRET" | jq '.'

# Via UI
# Open: https://phoenix.localtest.me:9443/projects
# Should see: team1-agents, team2-agents, admin-agents
```

**Deliverables**:
- [x] Projects created for each namespace
- [x] Script to automate project creation
- [x] Projects visible in Phoenix UI

---

### 🟡 Phase 3: Configure Agents to Use Projects

**Goal**: Update agent deployments to send traces to correct Phoenix project

**Duration**: 1 week

#### Tasks:

**3.1: Update Agent Deployment Template**

Create base agent deployment template with Phoenix project configuration:

`components/03-applications/agents/base-agent-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: research-agent
  namespace: team1  # ⚠️ Will be patched per namespace
spec:
  template:
    spec:
      containers:
      - name: agent
        env:
          # OTEL configuration
          - name: OTEL_EXPORTER_OTLP_ENDPOINT
            value: "http://otel-collector.observability.svc:4317"
          - name: OTEL_SERVICE_NAME
            value: "research-agent"  # ⚠️ Will be patched per agent

          # ✅ NEW: Phoenix project assignment
          - name: PHOENIX_PROJECT_NAME
            value: "team1-agents"  # ⚠️ Will be patched per namespace

          # ✅ NEW: K8s namespace for resource attributes
          - name: K8S_NAMESPACE_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace

          # ✅ NEW: OTEL resource attributes (for filtering)
          - name: OTEL_RESOURCE_ATTRIBUTES
            value: "k8s.namespace.name=$(K8S_NAMESPACE_NAME),team.name=team1"

          # Existing env vars...
          - name: llm_api_base
            value: "http://ollama.kagenti-system.svc:11434/v1"
          - name: LLM_MODEL
            value: "granite3.2:8b"
```

---

**3.2: Update Agents to Use Phoenix SDK (Optional)**

If agents don't already use Phoenix Python SDK, update agent code to set project:

`agent-examples-local/a2a/research-agent/agent.py`:
```python
import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

def setup_telemetry():
    """Setup OpenTelemetry with OTLP exporter and Phoenix project."""
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    service_name = os.getenv("OTEL_SERVICE_NAME", "research-agent")

    # ✅ NEW: Get Phoenix project from environment
    phoenix_project = os.getenv("PHOENIX_PROJECT_NAME", "default")
    k8s_namespace = os.getenv("K8S_NAMESPACE_NAME", "unknown")
    team_name = os.getenv("TEAM_NAME", "unknown")

    if otlp_endpoint:
        logger.info(f"Configuring OTEL exporter: {otlp_endpoint} for service: {service_name}")
        logger.info(f"Phoenix project: {phoenix_project}")

        # Create resource with Phoenix project attribute
        resource = Resource(attributes={
            "service.name": service_name,
            "k8s.namespace.name": k8s_namespace,
            "team.name": team_name,
            # ✅ NEW: Phoenix project as resource attribute
            "phoenix.project.name": phoenix_project,
        })

        # Create tracer provider
        tracer_provider = TracerProvider(resource=resource)

        # Create OTLP exporter
        otlp_exporter = OTLPSpanExporter(
            endpoint=otlp_endpoint,
            insecure=True,
            # ✅ NEW: Pass Phoenix project in headers (if supported)
            headers={
                "x-phoenix-project": phoenix_project,
            }
        )

        # Add span processor
        tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))

        # Set global tracer provider
        trace.set_tracer_provider(tracer_provider)

        logger.info("OpenTelemetry configured successfully")
    else:
        logger.warning("OTEL_EXPORTER_OTLP_ENDPOINT not set, tracing disabled")
```

**⚠️ Note**: Phoenix project assignment via SDK may require Phoenix Python SDK (`arize-phoenix` package). Check if OTEL headers work first.

---

**3.3: Deploy Updated Agents**

Update agents in `team1` namespace with project configuration:

```bash
# 1. Update agent deployment manifests
vim components/03-applications/agents/team1/research-agent-deployment.yaml
# Add PHOENIX_PROJECT_NAME=team1-agents

# 2. Commit and push
git add components/03-applications/agents/
git commit -m "feat(agents): Configure Phoenix project assignment"
git push origin feature/phoenix-projects

# 3. Sync via ArgoCD
argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web

# 4. Verify agent environment
kubectl get deployment research-agent -n team1 -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.[] | select(.name=="PHOENIX_PROJECT_NAME")'

# Output:
# {
#   "name": "PHOENIX_PROJECT_NAME",
#   "value": "team1-agents"
# }
```

---

**3.4: Test Trace Routing**

**Trigger agent execution**:
```bash
# 1. Port-forward to research agent
kubectl port-forward -n team1 svc/research-agent 8000:8000

# 2. Send test request
curl -X POST http://localhost:8000/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is the capital of France?"
  }'

# 3. Wait for response...
# 4. Check Phoenix for traces
```

**Verify in Phoenix UI**:
```bash
# 1. Open Phoenix
open https://phoenix.localtest.me:9443

# 2. Select project: "team1-agents"
# 3. Should see trace from research-agent
# 4. Verify attributes:
#    - service.name = research-agent
#    - k8s.namespace.name = team1
#    - openinference.span.kind = CHAIN, LLM, TOOL
```

**Deliverables**:
- [x] Agents configured with `PHOENIX_PROJECT_NAME`
- [x] Agent deployments updated in Git
- [x] Agents redeployed via ArgoCD
- [x] Test traces visible in correct Phoenix project

---

### 🟡 Phase 4: Create Users & Assign to Projects

**Goal**: Create Phoenix users and assign them to projects with appropriate roles

**Duration**: 3 days

#### Tasks:

**4.1: Understand User Management**

Phoenix supports **two user management modes**:

1. **Built-in users** (username/password in PostgreSQL)
   - Created via Phoenix UI or REST API
   - Managed entirely in Phoenix

2. **OAuth2/OIDC users** (auto-created on first login)
   - Users login via Keycloak
   - Phoenix auto-creates user on first OAuth login
   - Email from OAuth used as username

**For our use case**: Use **OAuth2 users** (auto-created from Keycloak)

**Workflow**:
1. User logs into Phoenix via Keycloak
2. Phoenix auto-creates user account (role: Member by default)
3. Admin assigns user to projects via Phoenix UI or API

---

**4.2: Create Test Users in Keycloak**

Create test users in Keycloak for testing:

```bash
# 1. Access Keycloak admin console
open https://keycloak.localtest.me:9443/admin

# 2. Login as admin (admin / admin123)

# 3. Navigate to: Users → Create User

# 4. Create user: alice@example.com
#    - Username: alice
#    - Email: alice@example.com
#    - Email Verified: ON
#    - Set password: alice123 (temporary: OFF)

# 5. Create user: bob@example.com
#    - Username: bob
#    - Email: bob@example.com
#    - Email Verified: ON
#    - Set password: bob123 (temporary: OFF)
```

---

**4.3: Users Login to Phoenix (Auto-Creation)**

**Alice (team1)**:
```bash
# 1. Open Phoenix
open https://phoenix.localtest.me:9443

# 2. Click "Login"
# 3. Redirects to Keycloak
# 4. Login: alice@example.com / alice123
# 5. Redirects back to Phoenix
# 6. Phoenix auto-creates user: alice@example.com (role: Member)
# 7. Alice sees empty dashboard (no projects assigned yet)
```

**Bob (team2)**:
```bash
# Repeat above with: bob@example.com / bob123
```

---

**4.4: Assign Users to Projects**

**Option 1: Via Phoenix UI (Manual)**

```bash
# 1. Login as admin (admin@localhost)
open https://phoenix.localtest.me:9443

# 2. Navigate to: Settings → Users
# 3. Should see:
#    - admin@localhost (Admin)
#    - alice@example.com (Member)
#    - bob@example.com (Member)

# 4. Click alice@example.com → Edit
# 5. Under "Projects":
#    - Add: team1-agents (role: Member)
# 6. Save

# 7. Click bob@example.com → Edit
# 8. Under "Projects":
#    - Add: team2-agents (role: Member)
# 9. Save
```

**Option 2: Via REST API (Automated)**

Create script `scripts/phoenix/assign-users.sh`:

```bash
#!/bin/bash
# Assign Phoenix users to projects

set -euo pipefail

PHOENIX_URL="${PHOENIX_URL:-https://phoenix.localtest.me:9443}"
ADMIN_API_KEY="${PHOENIX_ADMIN_API_KEY:-}"  # System API key (created in Phase 1)

if [ -z "$ADMIN_API_KEY" ]; then
  echo "❌ PHOENIX_ADMIN_API_KEY not set"
  echo "Usage: PHOENIX_ADMIN_API_KEY=<key> ./assign-users.sh"
  exit 1
fi

# User-to-project mappings
declare -A USER_PROJECTS=(
  ["alice@example.com"]="team1-agents"
  ["bob@example.com"]="team2-agents"
)

for user_email in "${!USER_PROJECTS[@]}"; do
  project_name="${USER_PROJECTS[$user_email]}"

  echo "Assigning $user_email → $project_name"

  # 1. Get user ID
  USER_ID=$(curl -s "$PHOENIX_URL/v1/users?email=$user_email" \
    -H "Authorization: Bearer $ADMIN_API_KEY" | jq -r '.data[0].id')

  if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
    echo "⚠️ User not found: $user_email (must login first to auto-create)"
    continue
  fi

  # 2. Get project ID
  PROJECT_ID=$(curl -s "$PHOENIX_URL/v1/projects?name=$project_name" \
    -H "Authorization: Bearer $ADMIN_API_KEY" | jq -r '.data[0].id')

  if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    echo "❌ Project not found: $project_name"
    continue
  fi

  # 3. Assign user to project
  curl -X POST "$PHOENIX_URL/v1/projects/$PROJECT_ID/members" \
    -H "Authorization: Bearer $ADMIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"user_id\": \"$USER_ID\",
      \"role\": \"member\"
    }"

  echo "✅ Assigned $user_email → $project_name"
done
```

**Usage**:
```bash
# 1. Get admin API key (created in Phase 1)
export PHOENIX_ADMIN_API_KEY="px_..."  # From Phoenix UI: Settings → API Keys

# 2. Run script
chmod +x scripts/phoenix/assign-users.sh
./scripts/phoenix/assign-users.sh
```

---

**4.5: Test User Access Isolation**

**Test Alice (team1)**:
```bash
# 1. Logout from Phoenix
# 2. Login as: alice@example.com / alice123
# 3. Should see:
#    - Dashboard shows: "team1-agents" project only
#    - Traces from research-agent (team1 namespace)
#    - NO traces from team2 agents
# 4. Try to access team2-agents project URL directly:
#    https://phoenix.localtest.me:9443/projects/team2-agents
#    Should show: "403 Forbidden" or redirect to team1-agents
```

**Test Bob (team2)**:
```bash
# 1. Logout from Phoenix
# 2. Login as: bob@example.com / bob123
# 3. Should see:
#    - Dashboard shows: "team2-agents" project only
#    - Traces from team2 agents
#    - NO traces from team1 agents
```

**Test Admin**:
```bash
# 1. Login as: admin@localhost
# 2. Should see:
#    - Dashboard shows: ALL projects (team1-agents, team2-agents, admin-agents)
#    - Can switch between projects
#    - Can see all traces
```

**Deliverables**:
- [x] Test users created in Keycloak (alice, bob)
- [x] Users logged into Phoenix (auto-created)
- [x] Users assigned to projects (alice→team1, bob→team2)
- [x] Access isolation verified (alice sees team1 only, bob sees team2 only)
- [x] Admin sees all projects

---

### 🟡 Phase 5: Testing & Documentation

**Goal**: Comprehensive testing of multi-tenancy and documentation

**Duration**: 1 week

#### Tasks:

**5.1: Integration Tests**

Create pytest tests for Phoenix multi-tenancy:

`tests/integration/test_phoenix_rbac.py`:
```python
"""
Phoenix RBAC and Multi-Tenancy Tests

Tests Phoenix role-based access control and project isolation.
"""

import pytest
import requests
from kubernetes import client, config


class TestPhoenixAuthentication:
    """Test Phoenix authentication."""

    def test_phoenix_ui_redirects_to_keycloak(self):
        """Test that Phoenix UI redirects to Keycloak for login."""
        response = requests.get(
            "https://phoenix.localtest.me:9443",
            allow_redirects=False,
            verify=False
        )

        # Should redirect to Keycloak
        assert response.status_code == 302
        assert "keycloak.localtest.me" in response.headers["Location"]

    def test_phoenix_api_requires_auth(self):
        """Test that Phoenix API requires authentication."""
        response = requests.get(
            "https://phoenix.localtest.me:9443/v1/projects",
            verify=False
        )

        # Should return 401 Unauthorized
        assert response.status_code == 401


class TestPhoenixProjects:
    """Test Phoenix project management."""

    @pytest.fixture(scope="class")
    def admin_api_key(self, k8s_client):
        """Get admin API key from secret."""
        import base64
        secret = k8s_client.read_namespaced_secret(
            name="phoenix-auth-secrets",
            namespace="observability"
        )
        return base64.b64decode(secret.data["PHOENIX_ADMIN_SECRET"]).decode()

    def test_projects_exist(self, admin_api_key):
        """Test that namespace projects are created."""
        response = requests.get(
            "https://phoenix.localtest.me:9443/v1/projects",
            headers={"Authorization": f"Bearer {admin_api_key}"},
            verify=False
        )

        assert response.status_code == 200
        projects = response.json()["data"]
        project_names = [p["name"] for p in projects]

        # Should have team1-agents, team2-agents
        assert "team1-agents" in project_names
        assert "team2-agents" in project_names

    def test_can_create_project_with_admin_key(self, admin_api_key):
        """Test creating a project with admin API key."""
        response = requests.post(
            "https://phoenix.localtest.me:9443/v1/projects",
            headers={"Authorization": f"Bearer {admin_api_key}"},
            json={
                "name": "test-project",
                "description": "Test project for integration tests"
            },
            verify=False
        )

        # Should succeed or return 409 if already exists
        assert response.status_code in [200, 201, 409]


class TestPhoenixTraceIngestion:
    """Test Phoenix trace ingestion from agents."""

    def test_agents_send_traces_to_correct_project(self):
        """Test that agents send traces to their namespace's project."""
        # This test requires triggering agent execution
        # and checking Phoenix for traces
        pytest.skip("Requires agent execution - implement after agent deployment")

    def test_traces_have_namespace_metadata(self):
        """Test that traces include k8s.namespace.name attribute."""
        pytest.skip("Requires agent execution - implement after agent deployment")


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
```

**Run tests**:
```bash
pytest tests/integration/test_phoenix_rbac.py -v
```

---

**5.2: Update Platform Tests**

Add Phoenix to platform health checks:

`scripts/platform-status.sh` (update):
```bash
# Check Phoenix
echo -e "${BLUE}Checking Phoenix Status...${NC}"
if kubectl get deployment phoenix -n observability &>/dev/null; then
    local ready=$(kubectl get deployment phoenix -n observability -o jsonpath='{.status.readyReplicas}')
    local desired=$(kubectl get deployment phoenix -n observability -o jsonpath='{.spec.replicas}')
    if [ "$ready" == "$desired" ]; then
        echo -e "${GREEN}✓ Phoenix: Running ($ready/$desired)${NC}"

        # Check PostgreSQL
        if kubectl get statefulset phoenix-postgres -n observability &>/dev/null; then
            local pg_ready=$(kubectl get statefulset phoenix-postgres -n observability -o jsonpath='{.status.readyReplicas}')
            echo -e "${GREEN}✓ Phoenix PostgreSQL: Running ($pg_ready/1)${NC}"
        fi

        # Check authentication enabled
        local auth_enabled=$(kubectl get deployment phoenix -n observability -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PHOENIX_ENABLE_AUTH")].value}')
        if [ "$auth_enabled" == "true" ]; then
            echo -e "${GREEN}✓ Phoenix Authentication: Enabled${NC}"
        else
            echo -e "${YELLOW}⚠ Phoenix Authentication: Disabled${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Phoenix: Not Ready ($ready/$desired)${NC}"
    fi
else
    echo -e "${RED}✗ Phoenix: Not Found${NC}"
fi
```

---

**5.3: Documentation**

Create Phoenix user documentation:

`docs/04-observability/PHOENIX_USER_GUIDE.md`:

```markdown
# Phoenix LLM Observability - User Guide

## Accessing Phoenix

**URL**: https://phoenix.localtest.me:9443

**Authentication**: Keycloak SSO (same credentials as other platform services)

## Projects

Each team has a dedicated Phoenix project:
- `team1-agents` - Traces from agents in `team1` namespace
- `team2-agents` - Traces from agents in `team2` namespace

## Viewing Traces

1. Login to Phoenix
2. Select your project from the dropdown
3. Navigate to **Traces** tab
4. Filter by:
   - Service: `research-agent`, `code-agent`, `orchestrator-agent`
   - Time range: Last 1 hour, 24 hours, 7 days, etc.
   - Attributes: `k8s.namespace.name`, `llm.model_name`, etc.

## Understanding Traces

Phoenix displays traces with OpenInference semantic conventions:

- **CHAIN** spans: LangGraph agent execution
- **LLM** spans: LLM API calls (to Ollama)
- **TOOL** spans: Tool executions (web search, code execution, etc.)

## Debugging Agent Issues

### Viewing Error Traces

1. Go to **Traces** tab
2. Filter by: `status.code = ERROR`
3. Click on trace to see:
   - Error message
   - Stack trace
   - Input/output values
   - LLM prompts and responses

### Analyzing Latency

1. Go to **Performance** tab
2. View metrics:
   - P50, P95, P99 latency
   - Requests per second
   - Error rate

## RBAC

**Member role** (default for team users):
- ✅ View traces in assigned projects
- ✅ Create experiments
- ✅ Export data
- ❌ Cannot create/delete projects
- ❌ Cannot manage users

**Admin role**:
- ✅ Full access to all projects
- ✅ Manage users and API keys
- ✅ Configure retention policies
```

**Update CLAUDE.md** with Phoenix section:

Add to `## 📊 Monitoring & Access`:
```markdown
### Phoenix LLM Observability

```bash
# Access Phoenix
open https://phoenix.localtest.me:9443

# Login with Keycloak SSO
# Select project: team1-agents (or your team)

# View agent traces
# Filter by service: research-agent, code-agent, etc.
```

**Projects**:
- `team1-agents` - Team 1 agent traces
- `team2-agents` - Team 2 agent traces

**Default credentials**: Use Keycloak SSO (same as Grafana, etc.)

**Admin access**: `admin@localhost` (password set on first login)
```

---

**5.4: Create Runbook for Common Tasks**

`docs/04-observability/PHOENIX_RUNBOOK.md`:

```markdown
# Phoenix Operations Runbook

## Adding a New Team

### 1. Create Phoenix Project

```bash
export PHOENIX_ADMIN_SECRET=$(kubectl get secret phoenix-auth-secrets -n observability -o jsonpath='{.data.PHOENIX_ADMIN_SECRET}' | base64 -d)

curl -X POST "https://phoenix.localtest.me:9443/v1/projects" \
  -H "Authorization: Bearer $PHOENIX_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "team3-agents",
    "description": "Agent traces from team3 namespace"
  }'
```

### 2. Update Agent Deployments

Add to agent deployment in `team3` namespace:
```yaml
env:
- name: PHOENIX_PROJECT_NAME
  value: "team3-agents"
```

### 3. Assign Users to Project

User must first login to Phoenix (auto-creates account), then:
```bash
# Via Phoenix UI: Settings → Users → <user> → Add to project: team3-agents

# Or via API:
curl -X POST "https://phoenix.localtest.me:9443/v1/projects/<PROJECT_ID>/members" \
  -H "Authorization: Bearer $PHOENIX_ADMIN_API_KEY" \
  -d '{"user_id": "<USER_ID>", "role": "member"}'
```

## Backup and Restore

### Backup Traces

```bash
# Backup PostgreSQL database
kubectl exec -n observability phoenix-postgres-0 -- \
  pg_dump -U phoenix phoenix > phoenix-backup-$(date +%Y%m%d).sql

# Backup to S3 (if configured)
aws s3 cp phoenix-backup-$(date +%Y%m%d).sql s3://backups/phoenix/
```

### Restore Traces

```bash
# Restore from backup
kubectl exec -i -n observability phoenix-postgres-0 -- \
  psql -U phoenix phoenix < phoenix-backup-20250117.sql
```

## Troubleshooting

### Phoenix Pod Crashes

```bash
# Check logs
kubectl logs -n observability deployment/phoenix --tail=100

# Common issues:
# - Database connection failed (check postgres)
# - Authentication error (check phoenix-auth-secrets)
# - OTLP port conflict (check port 4317)
```

### Traces Not Appearing

```bash
# 1. Check agent OTLP configuration
kubectl get deployment research-agent -n team1 -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.[] | select(.name | contains("OTEL"))'

# 2. Check OTEL Collector routing
kubectl logs -n observability deployment/otel-collector --tail=50 | grep -i phoenix

# 3. Check Phoenix gRPC logs
kubectl logs -n observability deployment/phoenix --tail=50 | grep -i grpc
```

### User Cannot See Traces

```bash
# 1. Verify user logged in (auto-creates account)
# 2. Check user assigned to project via Phoenix UI: Settings → Users
# 3. Check project has traces: Phoenix UI → Projects → <project> → Traces
```
```

**Deliverables**:
- [x] Integration tests for Phoenix RBAC
- [x] Platform status script updated
- [x] User guide documentation
- [x] Operations runbook
- [x] CLAUDE.md updated

---

## Implementation Details

### Database Schema

Phoenix creates these tables in PostgreSQL:

```
phoenix DB:
  - traces: Trace metadata (trace_id, start_time, end_time, project_id)
  - spans: Individual spans (span_id, trace_id, parent_id, attributes)
  - projects: Project metadata (id, name, description)
  - users: User accounts (id, email, role, created_at)
  - project_members: User-project assignments (user_id, project_id, role)
  - api_keys: API keys (id, name, key_hash, user_id, expires_at)
```

**Retention Policy**: Configurable via `PHOENIX_DEFAULT_RETENTION_POLICY_DAYS` (default: 30 days)

**Storage Estimates**:
- Average trace: ~10 KB (compressed)
- 1000 traces/day: ~10 MB/day = 300 MB/month
- 10,000 traces/day: ~100 MB/day = 3 GB/month

**Recommended PostgreSQL Storage**: 20 GB (for 30-day retention with moderate trace volume)

---

### Security Considerations

**1. Trace Data Privacy**:
- ⚠️ **Traces contain user prompts and LLM responses** (potentially sensitive!)
- ✅ **Projects provide soft isolation** (relies on Phoenix RBAC)
- ✅ **PostgreSQL access restricted** (only Phoenix pod can access)
- ⚠️ **No encryption at rest** (consider PostgreSQL encryption for production)

**2. Authentication Tokens**:
- ✅ **PHOENIX_SECRET stored in Kubernetes secret** (for JWT signing)
- ✅ **OAuth2 client secret stored in Kubernetes secret**
- ⚠️ **API keys stored in PostgreSQL** (hashed, but accessible to admins)

**3. RBAC Limitations**:
- ⚠️ **Phoenix RBAC is separate from K8s RBAC** (not synced)
- ⚠️ **Manual user-to-project assignment** (no auto-sync with K8s namespace RBAC)
- ⚠️ **Admins can see all traces** (including other teams' data)

**Recommendations for Production**:
1. **Use PostgreSQL schema isolation** (Option 3 from multi-tenancy strategy)
2. **Encrypt PostgreSQL at rest** (via cloud provider encryption or LUKS)
3. **Implement K8s RBAC sync** (custom controller to sync K8s namespace access → Phoenix projects)
4. **Use attribute-based filtering** (filter traces by `k8s.namespace.name` in Phoenix queries)
5. **Audit logs** (enable PostgreSQL audit logging for compliance)

---

### Performance Tuning

**Phoenix Resource Limits**:
```yaml
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m  # Increase if queries are slow
    memory: 2Gi  # Increase if OOM
```

**PostgreSQL Tuning**:
```yaml
env:
- name: POSTGRES_MAX_CONNECTIONS
  value: "100"  # Increase if connection errors
- name: POSTGRES_SHARED_BUFFERS
  value: "256MB"  # Increase for better query performance
```

**OTEL Collector Batching**:
```yaml
# components/02-observability/otel-collector/configmap.yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 1024  # Increase to reduce network overhead
```

**Phoenix Retention Policy**:
- Shorter retention = less storage = faster queries
- For production: 7-14 days for most teams, 30-90 days for data science teams

---

## Testing Strategy

### Unit Tests

**Not applicable** - Phoenix is a third-party application (no custom code to test)

### Integration Tests

**Test Coverage** (`tests/integration/test_phoenix_rbac.py`):
- [x] Phoenix UI redirects to Keycloak
- [x] Phoenix API requires authentication
- [x] Projects created for each namespace
- [x] Admin API key can create projects
- [ ] Agents send traces to correct project (requires agent execution)
- [ ] Traces have namespace metadata (requires agent execution)

### E2E Tests

**Test Scenarios** (`tests/e2e/test_phoenix_e2e.py`):
1. **User Login Flow**:
   - User logs into Phoenix via Keycloak
   - Phoenix auto-creates user
   - User sees only assigned projects

2. **Trace Ingestion**:
   - Trigger agent execution
   - Wait for trace to appear in Phoenix
   - Verify trace in correct project
   - Verify trace attributes (namespace, service name, etc.)

3. **Access Isolation**:
   - Alice (team1) cannot see team2 traces
   - Bob (team2) cannot see team1 traces
   - Admin can see all traces

4. **Project Management**:
   - Admin creates new project
   - Admin assigns user to project
   - User can see new project

### Load Testing

**Not planned for MVP** - Phoenix handles production workloads at Arize, so performance is proven

---

## Known Limitations

### 1. No Automatic K8s RBAC Sync

**Problem**: Phoenix users and projects are manually managed (not synced with K8s RBAC)

**Example**:
- Alice has K8s RBAC access to `team1` namespace
- Alice must still be manually assigned to `team1-agents` project in Phoenix
- If Alice's K8s access is revoked, Phoenix access must be revoked separately

**Workaround**: Manual user management (Phase 4)

**Future Enhancement**: Build K8s operator to sync:
- K8s namespace RBAC → Phoenix project membership
- K8s users/groups → Phoenix users
- Automatic project creation for new namespaces

---

### 2. No Attribute-Based Filtering (ABAC)

**Problem**: Phoenix cannot filter traces by resource attributes (e.g., `k8s.namespace.name`)

**Example**:
- Cannot query: "Show all traces where `k8s.namespace.name = team1`"
- Must rely on project assignment (agents send to `team1-agents` project)

**Workaround**: Use Projects for namespace isolation (recommended strategy)

**Future Enhancement**: Implement ABAC in Phoenix or use Grafana Tempo for flexible querying

---

### 3. Soft Isolation (Same Database)

**Problem**: All team traces stored in same PostgreSQL database (relies on Phoenix RBAC)

**Risk**: Phoenix RBAC vulnerability could expose cross-team data

**Mitigation**:
- PostgreSQL access restricted to Phoenix pod only
- Phoenix RBAC has been audited by Arize
- Use PostgreSQL schema isolation (Option 3) for stronger isolation

**Future Enhancement**: Deploy separate Phoenix instances per team (Option 1) for strong isolation

---

### 4. No Built-in Compliance Features

**Problem**: Phoenix does not have built-in data masking, PII redaction, or compliance reporting

**Example**:
- User prompts may contain PII (names, emails, etc.)
- Phoenix stores prompts as-is (no redaction)
- Cannot generate GDPR data export for specific users

**Workaround**: Implement PII redaction at agent level (before sending to Phoenix)

**Future Enhancement**: Integrate with data masking tools (e.g., Nightfall, Skyflow)

---

### 5. OTEL Collector Cannot Route to Projects

**Problem**: OTEL Collector's `routing` processor cannot route traces to Phoenix projects (only to different backends)

**Explanation**:
- OTEL Collector routes by exporter (Phoenix vs Tempo)
- Cannot route to Phoenix project within Phoenix exporter
- Project assignment must happen in agent code (via `PHOENIX_PROJECT_NAME` env var)

**Workaround**: Set `PHOENIX_PROJECT_NAME` in agent deployment

**Future Enhancement**: Build custom OTEL Collector processor to route by project (complex!)

---

## Future Enhancements

### 1. K8s RBAC Sync Operator

**Goal**: Automatically sync K8s namespace RBAC to Phoenix projects

**Architecture**:
```
┌─────────────────────────────────────────────────────────────────────┐
│ Phoenix RBAC Sync Operator                                          │
│ Watches: K8s RoleBindings, Namespaces                               │
│ Reconciles: Phoenix projects, users, memberships                    │
└─────────────────────────────────────────────────────────────────────┘

Events:
  - New namespace created → Create Phoenix project
  - User granted namespace access → Add user to Phoenix project
  - User removed from namespace → Remove user from Phoenix project
  - Namespace deleted → Archive Phoenix project

Implementation:
  - Kubernetes Operator (Golang or Python)
  - Watches: RBAC resources (RoleBindings, ClusterRoleBindings)
  - Calls: Phoenix REST API (to manage projects/users)
  - Config: Namespace label selector (e.g., kagenti.io/phoenix-enabled=true)
```

**Complexity**: High (requires operator development)

**Benefit**: Fully automated multi-tenancy (zero manual user management)

**Estimated Effort**: 2-3 weeks

---

### 2. PostgreSQL Schema Isolation

**Goal**: Use PostgreSQL schemas to isolate team traces at database level

**Implementation**:
```yaml
# Phoenix deployment for team1
env:
- name: PHOENIX_SQL_DATABASE_SCHEMA
  value: "team1_traces"  # Separate schema

# Phoenix deployment for team2
env:
- name: PHOENIX_SQL_DATABASE_SCHEMA
  value: "team2_traces"  # Separate schema
```

**Challenge**: Phoenix doesn't support dynamic schema routing (need separate Phoenix instances or custom fork)

**Benefit**: Stronger isolation (database-level, not just application-level)

**Estimated Effort**: 1 week (if using separate Phoenix instances)

---

### 3. PII Redaction in Agents

**Goal**: Redact PII from traces before sending to Phoenix

**Architecture**:
```python
# In agent code
from opentelemetry.sdk.trace import SpanProcessor

class PIIRedactionProcessor(SpanProcessor):
    """Redact PII from span attributes before export."""

    def on_end(self, span):
        # Redact input/output values
        for attr in span.attributes:
            if attr.key in ["input.value", "output.value"]:
                span.set_attribute(attr.key, self.redact_pii(attr.value))

    def redact_pii(self, text):
        # Use regex or ML model to detect and redact PII
        # Example: Replace emails with [EMAIL]
        import re
        text = re.sub(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', '[EMAIL]', text)
        return text
```

**Complexity**: Medium (depends on PII detection accuracy requirements)

**Benefit**: Compliance-ready (GDPR, HIPAA, etc.)

**Estimated Effort**: 1-2 weeks

---

### 4. Cross-Team Trace Correlation (for Admins)

**Goal**: Allow admins to correlate traces across teams (for debugging multi-team workflows)

**Use Case**:
- Orchestrator agent (team1) calls code agent (team2)
- Admin needs to see full trace across both teams

**Current Limitation**: Traces split into `team1-agents` and `team2-agents` projects (no cross-project view)

**Solution**:
- Create `admin-agents` project with aggregated view
- OTEL Collector sends traces to BOTH team project + admin project
- Agents set headers: `x-phoenix-projects: team1-agents,admin-agents`

**Complexity**: Medium (requires OTEL Collector multi-export)

**Benefit**: Full trace visibility for admins (cross-team debugging)

**Estimated Effort**: 3-5 days

---

### 5. Grafana Integration (Traces → Logs → Metrics)

**Goal**: Integrate Phoenix traces with Grafana for unified observability

**Architecture**:
```
Grafana → Tempo → Phoenix gRPC API (for OpenInference traces)
        → Loki  → Logs (correlated by trace ID)
        → Prometheus → Metrics (span metrics from OTEL Collector)
```

**Implementation**:
- Configure Grafana Tempo data source to query Phoenix
- Use Korrel8r to correlate traces ↔ logs ↔ metrics
- Create Grafana dashboard with:
  - Trace viewer (from Phoenix/Tempo)
  - Log viewer (from Loki)
  - Metrics graphs (from Prometheus)

**Benefit**: Unified observability (no need to switch between Phoenix and Grafana)

**Estimated Effort**: 1 week

---

## Summary

### What We're Building

**MVP (Phases 1-5)**:
- ✅ Phoenix with PostgreSQL persistence
- ✅ Keycloak OAuth2 authentication
- ✅ Projects for each namespace (team1-agents, team2-agents)
- ✅ Agents configured to send traces to correct project
- ✅ Users assigned to projects via Phoenix RBAC
- ✅ Access isolation (alice sees team1 only, bob sees team2 only)
- ✅ Admin sees all traces

**Timeline**: 4-5 weeks

**Complexity**: Medium

**Benefits**:
- ✅ LLM observability for agent debugging
- ✅ Multi-tenant trace isolation
- ✅ SSO via Keycloak (same as rest of platform)
- ✅ GitOps-managed configuration
- ✅ Production-ready storage (PostgreSQL)

**Limitations**:
- ⚠️ Manual user-to-project assignment (no K8s RBAC sync)
- ⚠️ Soft isolation (same database, relies on Phoenix RBAC)
- ⚠️ No PII redaction (agents send raw prompts/responses)

**Future Work**:
- K8s RBAC sync operator (automated user management)
- PostgreSQL schema isolation (stronger database-level isolation)
- PII redaction (compliance-ready)
- Grafana integration (unified observability)

---

## Next Steps

1. ✅ **Get approval from team** on multi-tenancy strategy (Shared Phoenix + Projects)
2. 🟡 **Start Phase 1**: Deploy PostgreSQL and enable Phoenix authentication
3. 🟡 **Start Phase 2**: Create projects for team namespaces
4. 🟡 **Start Phase 3**: Configure agents to use projects
5. 🟡 **Start Phase 4**: Create users and test access isolation
6. 🟡 **Start Phase 5**: Write tests and documentation

**Estimated completion**: 4-5 weeks from approval

---

**Questions? Contact**: Platform Team

**Last Updated**: 2025-11-17
