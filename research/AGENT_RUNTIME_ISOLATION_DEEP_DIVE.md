# Agent Runtime Isolation: Deep Dive

**Date**: 2025-11-19
**Focus**: Comprehensive analysis of agent runtime isolation concerns
**Question**: If we don't isolate agents by namespace, what security/privacy issues arise?

---

## Critical Realization

**You're absolutely right**: If all agents run in the same namespace with shared resources, **approval inbox isolation alone is insufficient**. We need to think about **agent runtime isolation** more carefully.

---

## Table of Contents

1. [The Isolation Problem](#1-the-isolation-problem)
2. [What Gets Shared in Same Namespace](#2-what-gets-shared-in-same-namespace)
3. [Attack Scenarios](#3-attack-scenarios)
4. [Observability Data Isolation](#4-observability-data-isolation)
5. [MCP Server Multi-Tenancy](#5-mcp-server-multi-tenancy)
6. [GitHub Token Isolation](#6-github-token-isolation)
7. [Slack Integration Isolation](#7-slack-integration-isolation)
8. [Complete Isolation Architecture](#8-complete-isolation-architecture)
9. [Trade-offs Analysis](#9-trade-offs-analysis)

---

## 1. The Isolation Problem

### 1.1 Current Plan (from TODO_monitoring_agents.md)

**All monitoring agents in single namespace**:
```
monitoring-agents namespace:
  ├── metrics-monitor-agent (pod)
  ├── trace-analyzer-agent (pod)
  ├── log-analyzer-agent (pod)
  ├── orchestrator-agent (pod)
  ├── correlation-rca-agent (pod)
  └── github-remediation-agent (pod)
```

**Problem**: All these agents share:
- Same namespace
- Same ServiceAccount (potentially)
- Same ConfigMaps (MCP endpoints, credentials)
- Same Secrets (GitHub tokens, Slack tokens)
- Same network policies
- Same Kubernetes API access

### 1.2 Why This Matters

**Scenario**: Team1 deploys their own monitoring agent in `monitoring-agents` namespace

**What Team1's agent can do**:
1. ✅ Read ConfigMaps in `monitoring-agents` namespace → **Sees all MCP endpoints**
2. ✅ Read Secrets in `monitoring-agents` namespace → **Sees GitHub token, Slack token**
3. ✅ Call MCP servers directly → **Query metrics/logs/traces from all teams**
4. ✅ Create ApprovalRequests in other namespaces (if RBAC allows) → **Spam other teams**
5. ✅ Create GitHub PRs using shared token → **Impersonate platform team**
6. ✅ Send Slack messages using shared bot → **Impersonate platform team**

**Conclusion**: **Shared namespace = NO isolation** ❌

---

## 2. What Gets Shared in Same Namespace

### 2.1 ServiceAccount Tokens

**Scenario**: All agents use same ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: monitoring-agent
  namespace: monitoring-agents
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-monitor-agent
  namespace: monitoring-agents
spec:
  template:
    spec:
      serviceAccountName: monitoring-agent  # SHARED!
```

**What this means**:
- All agents have **identical K8s RBAC permissions**
- If `monitoring-agent` ServiceAccount can create ApprovalRequests, ALL agents can
- If `monitoring-agent` ServiceAccount can read Secrets, ALL agents can
- **No way to differentiate** which agent made which API call (from K8s audit log perspective)

**Solution**: **Per-agent ServiceAccounts**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metrics-monitor-agent-sa
  namespace: monitoring-agents
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-remediation-agent-sa
  namespace: monitoring-agents
```

**Benefits**:
- ✅ Fine-grained RBAC per agent
- ✅ Audit trail shows which agent made which call
- ✅ Can revoke one agent's permissions without affecting others

### 2.2 ConfigMaps (MCP Endpoints, Config)

**Scenario**: All agents mount same ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mcp-endpoints
  namespace: monitoring-agents
data:
  prometheus.url: "http://prometheus-mcp:8080"
  github.url: "http://github-mcp:8080"
  slack.url: "http://slack-mcp:8080"
```

**What this means**:
- All agents know all MCP endpoints
- If Team1's agent is malicious, it can call GitHub MCP to create PRs
- **No isolation of capabilities**

**Solution Options**:

**Option A: Per-Agent ConfigMaps** (recommended for shared namespace)
```yaml
# Metrics monitor agent ONLY sees Prometheus MCP
apiVersion: v1
kind: ConfigMap
metadata:
  name: metrics-monitor-config
  namespace: monitoring-agents
data:
  prometheus.url: "http://prometheus-mcp:8080"
  # No GitHub URL, no Slack URL
---
# GitHub remediation agent sees GitHub + Slack MCP
apiVersion: v1
kind: ConfigMap
metadata:
  name: github-remediation-config
  namespace: monitoring-agents
data:
  github.url: "http://github-mcp:8080"
  slack.url: "http://slack-mcp:8080"
  # No Prometheus URL
```

**Option B: Namespace Isolation** (cleanest solution)
```yaml
# Team1's namespace - only their MCP endpoints
team1 namespace:
  ConfigMap: mcp-endpoints
    prometheus.url: "http://prometheus-mcp.team1:8080"  # Team1's MCP

# Team2's namespace - only their MCP endpoints
team2 namespace:
  ConfigMap: mcp-endpoints
    prometheus.url: "http://prometheus-mcp.team2:8080"  # Team2's MCP
```

### 2.3 Secrets (GitHub Tokens, Slack Tokens, Keycloak Credentials)

**Scenario**: All agents mount same Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: agent-credentials
  namespace: monitoring-agents
type: Opaque
stringData:
  github-token: "ghp_xxxxxxxxxxxx"
  slack-bot-token: "xoxb-xxxxxxxxxxxx"
  keycloak-client-secret: "xxxxxxxxxxxx"
```

**What this means**:
- **ANY agent can read ALL credentials**
- Malicious agent can use GitHub token to create PRs in any repo
- Malicious agent can use Slack token to send messages as the bot
- **Huge security risk** 🔴

**Solution**: **Per-Agent Secrets with RBAC**

```yaml
# GitHub token - only github-remediation-agent can read
apiVersion: v1
kind: Secret
metadata:
  name: github-token
  namespace: monitoring-agents
type: Opaque
stringData:
  token: "ghp_xxxxxxxxxxxx"
---
# RBAC: Only github-remediation-agent-sa can read github-token
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-token-reader
  namespace: monitoring-agents
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["github-token"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-remediation-agent-github-token-access
  namespace: monitoring-agents
subjects:
  - kind: ServiceAccount
    name: github-remediation-agent-sa
    namespace: monitoring-agents
roleRef:
  kind: Role
  name: github-token-reader
  apiGroup: rbac.authorization.k8s.io
```

**Result**: Metrics monitor agent **cannot** read GitHub token ✅

### 2.4 Network Policies

**Scenario**: No network policies in `monitoring-agents` namespace

**What this means**:
- All agents can reach all MCP servers
- Metrics monitor agent can call GitHub MCP
- GitHub remediation agent can call Prometheus MCP
- **No network-level isolation**

**Solution**: **NetworkPolicies to restrict access**

```yaml
# Metrics monitor agent can ONLY reach Prometheus MCP
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: metrics-monitor-network-policy
  namespace: monitoring-agents
spec:
  podSelector:
    matchLabels:
      app: metrics-monitor-agent
  policyTypes:
    - Egress
  egress:
    # Allow DNS
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53

    # Allow Prometheus MCP only
    - to:
        - podSelector:
            matchLabels:
              app: prometheus-mcp
      ports:
        - protocol: TCP
          port: 8080

    # Allow OTEL Collector (for tracing)
    - to:
        - namespaceSelector:
            matchLabels:
              name: observability
        - podSelector:
            matchLabels:
              app: otel-collector
      ports:
        - protocol: TCP
          port: 4317

    # Deny all other egress (including GitHub MCP, Slack MCP)
```

**Result**: Metrics monitor agent **cannot** reach GitHub MCP even if it has the URL ✅

---

## 3. Attack Scenarios

### 3.1 Scenario 1: Malicious Agent Steals Credentials

**Attack**:
1. Team1 deploys malicious agent in `monitoring-agents` namespace
2. Agent mounts shared Secret `agent-credentials`
3. Agent reads GitHub token, Slack token
4. Agent exfiltrates credentials to external server

**Impact**:
- Attacker can create PRs in any repository
- Attacker can send Slack messages as the bot
- Attacker can impersonate platform team

**Defense (if shared namespace)**:
- ✅ Per-agent Secrets with RBAC (agent can't mount other agents' secrets)
- ✅ NetworkPolicy to block egress to external servers
- ✅ Pod Security Policies (restrict what containers can do)

**Defense (namespace isolation)**:
- ✅ Team1's agent runs in `team1` namespace, can't access `monitoring-agents` secrets

### 3.2 Scenario 2: Data Exfiltration via MCP Servers

**Attack**:
1. Team1 deploys agent in `monitoring-agents` namespace
2. Agent calls Prometheus MCP to query metrics
3. Agent queries metrics from Team2's services: `http_requests_total{namespace="team2"}`
4. Agent exfiltrates Team2's traffic data

**Impact**:
- Cross-team data leakage
- Privacy violation

**Defense (if shared namespace)**:
- ⚠️ **HARD TO PREVENT** - MCP servers see all data
- Requires **MCP server multi-tenancy** (filter queries by caller's identity)

**Defense (namespace isolation)**:
- ✅ Team1's agent uses Team1's Prometheus MCP
- ✅ Team1's Prometheus MCP only has access to Team1's metrics
- ✅ Team2's metrics stored in separate Prometheus instance (or filtered by RBAC)

### 3.3 Scenario 3: PR Injection

**Attack**:
1. Team1's agent calls GitHub MCP
2. Agent creates PR to `kagenti-demo-deployment` with malicious changes
3. PR description mimics platform team's RCA (looks legitimate)
4. Human approves thinking it's from platform's monitoring agent

**Impact**:
- Supply chain attack (malicious code merged)
- Infrastructure compromise

**Defense (if shared namespace)**:
- ✅ **GitHub MCP authentication** (MCP verifies caller's identity)
- ✅ **Approval metadata** shows which agent created request
- ✅ **Audit trail** in ApprovalRequest CR (agent name, namespace, service account)

**Defense (namespace isolation)**:
- ✅ Team1's agent can't access GitHub MCP (no token, no network access)
- ✅ Only platform's GitHub remediation agent has GitHub access

---

## 4. Observability Data Isolation

### 4.1 Prometheus Multi-Tenancy

**Problem**: Single Prometheus instance stores metrics from all namespaces

**Query without isolation**:
```promql
# Team1's agent can query Team2's metrics
http_requests_total{namespace="team2"}
```

**Solutions**:

**Option A: Prometheus RBAC (via Prometheus Operator)**
```yaml
# PrometheusRule with namespace filtering (not natively supported)
# Workaround: Use Thanos/Cortex with tenant labels
```

**Option B: Per-Namespace Prometheus Instances**
```yaml
# Team1's Prometheus (only scrapes team1 namespace)
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: team1-prometheus
  namespace: team1
spec:
  serviceMonitorNamespaceSelector:
    matchLabels:
      team: team1
  podMonitorNamespaceSelector:
    matchLabels:
      team: team1
```

**Option C: Prometheus MCP Multi-Tenancy**
```python
# Prometheus MCP enforces namespace filtering
class PrometheusMCP:
    def query_promql(self, query, caller_namespace):
        # Inject namespace filter into query
        filtered_query = self._inject_namespace_filter(query, caller_namespace)

        # Example: http_requests_total becomes http_requests_total{namespace="team1"}
        result = prometheus_client.query(filtered_query)
        return result

    def _inject_namespace_filter(self, query, namespace):
        # Parse PromQL and add namespace label filter
        # This is complex and error-prone!
        pass
```

**Recommendation**: **Per-namespace Prometheus** if strict isolation is needed

### 4.2 Loki Multi-Tenancy

**Problem**: Single Loki instance stores logs from all namespaces

**Loki has native multi-tenancy**:
```yaml
# Loki config with multi-tenancy enabled
auth_enabled: true

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

# Promtail sends logs with X-Scope-OrgID header
```

**Promtail per namespace**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: team1
data:
  promtail.yaml: |
    clients:
      - url: http://loki.observability.svc:3100/loki/api/v1/push
        tenant_id: team1  # Tenant isolation
```

**Query with tenant filter**:
```
# Loki MCP queries with X-Scope-OrgID: team1 header
GET /loki/api/v1/query_range?query={job="app"}
Header: X-Scope-OrgID: team1
```

**Result**: Team1 only sees Team1's logs ✅

### 4.3 Tracing (Phoenix/Tempo) Multi-Tenancy

**Phoenix (LLM Traces)**:
- Currently **no multi-tenancy** in Phoenix OSS
- All traces stored in same PostgreSQL database
- **Risk**: Team1's agent can query Team2's LLM traces (sensitive prompts!)

**Solutions**:
- **Per-namespace Phoenix instances** (recommended)
  ```
  team1 namespace:
    - phoenix (PostgreSQL backend)
    - phoenix-mcp

  team2 namespace:
    - phoenix (PostgreSQL backend)
    - phoenix-mcp
  ```

- **Phoenix MCP tenant filtering** (requires custom implementation)

**Tempo (Infrastructure Traces)**:
- Supports multi-tenancy via `X-Scope-OrgID` header
- Similar to Loki approach

---

## 5. MCP Server Multi-Tenancy

### 5.1 Current Plan: Shared MCP Servers

**From AGENT_INBOX_RESEARCH.md**:
```
monitoring-agents namespace:
  ├── prometheus-mcp (shared by all agents)
  ├── loki-mcp (shared by all agents)
  ├── github-mcp (shared by all agents)
  └── slack-mcp (shared by all agents)
```

**Problem**: All agents call same MCP servers, no isolation

### 5.2 Option A: MCP Server RBAC (Implement Multi-Tenancy)

**Prometheus MCP with caller identity verification**:

```python
from kubernetes import client, config

class PrometheusMCP:
    def __init__(self):
        config.load_incluster_config()
        self.auth_api = client.AuthorizationV1Api()

    def query_promql(self, query, caller_token):
        # 1. Verify caller's K8s token
        caller_identity = self._verify_token(caller_token)

        # 2. Get caller's accessible namespaces
        accessible_namespaces = self._get_accessible_namespaces(caller_identity)

        # 3. Inject namespace filter into query
        filtered_query = self._filter_by_namespaces(query, accessible_namespaces)

        # 4. Execute filtered query
        result = prometheus_client.query(filtered_query)
        return result

    def _verify_token(self, token):
        # Verify K8s ServiceAccount token
        # Extract namespace, service account name
        pass

    def _get_accessible_namespaces(self, identity):
        # Query K8s RBAC: which namespaces can this SA access?
        # Return list of namespaces
        pass

    def _filter_by_namespaces(self, query, namespaces):
        # Inject: {namespace=~"team1|team2"}
        pass
```

**Pros**:
- ✅ Single MCP server instance
- ✅ Multi-tenant by design
- ✅ Enforces K8s RBAC

**Cons**:
- ❌ **Complex to implement correctly**
- ❌ **Error-prone** (query injection, filter bypass)
- ❌ **Performance overhead** (RBAC check on every call)

### 5.3 Option B: Per-Namespace MCP Servers (Recommended)

**Architecture**:
```
team1 namespace:
  ├── team1-prometheus-mcp (points to team1-prometheus)
  ├── team1-loki-mcp (tenant_id=team1)
  ├── team1-github-mcp (uses team1-github-token)

team2 namespace:
  ├── team2-prometheus-mcp (points to team2-prometheus)
  ├── team2-loki-mcp (tenant_id=team2)
  ├── team2-github-mcp (uses team2-github-token)

monitoring-agents namespace (platform):
  ├── platform-prometheus-mcp (points to platform-prometheus)
  ├── platform-github-mcp (uses platform-github-token)
```

**Pros**:
- ✅ **Hard isolation** (network policies, no cross-namespace access)
- ✅ **Simple to implement** (no multi-tenancy logic in MCP)
- ✅ **Clear boundaries** (each namespace owns its MCP servers)
- ✅ **Scalable** (each team can configure their own MCP)

**Cons**:
- ❌ More MCP server instances (resource overhead)
- ❌ Duplicate code (same MCP server deployed multiple times)

**Recommendation**: **Per-namespace MCP servers** for strict isolation ✅

---

## 6. GitHub Token Isolation

### 6.1 Problem: Shared GitHub Token

**Current plan**: Single GitHub token for all agents

**Risks**:
- Team1's agent can create PRs to any repository
- No audit trail showing which team created which PR
- Token compromise affects all teams

### 6.2 Solution: Per-Team GitHub Apps

**GitHub Apps with team-specific permissions**:

```yaml
# Team1's GitHub App credentials
apiVersion: v1
kind: Secret
metadata:
  name: team1-github-app
  namespace: team1
type: Opaque
stringData:
  app-id: "12345"
  installation-id: "67890"
  private-key: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----
---
# Team2's GitHub App credentials
apiVersion: v1
kind: Secret
metadata:
  name: team2-github-app
  namespace: team2
type: Opaque
stringData:
  app-id: "54321"
  installation-id: "98765"
  private-key: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----
```

**GitHub App Permissions**:
- Team1's GitHub App: Can create PRs in `team1-*` repositories only
- Team2's GitHub App: Can create PRs in `team2-*` repositories only
- Platform GitHub App: Can create PRs in `kagenti-demo-deployment` only

**Benefits**:
- ✅ **Least privilege** (app can only access authorized repos)
- ✅ **Audit trail** (GitHub shows which app created PR)
- ✅ **Revocable** (revoke team's app without affecting others)

---

## 7. Slack Integration Isolation

### 7.1 Problem: Shared Slack Bot

**Current plan**: Single Slack bot for all agents

**Risks**:
- Team1's agent can send messages to Team2's channels
- No way to identify which team sent which message
- Slack token compromise affects all teams

### 7.2 Solution: Per-Team Slack Apps

**Option A: Single Slack App with Bot User OAuth**
```yaml
# Each team gets their own bot token (via OAuth)
# Bot is invited only to team's channels

team1:
  slack-bot-token: "xoxb-team1-xxxx"  # Only in #team1-* channels

team2:
  slack-bot-token: "xoxb-team2-xxxx"  # Only in #team2-* channels
```

**Option B: Separate Slack Apps per Team**
```yaml
team1:
  slack-app-id: "A12345"
  slack-bot-token: "xoxb-A12345-xxxx"

team2:
  slack-app-id: "A54321"
  slack-bot-token: "xoxb-A54321-xxxx"
```

**Benefits**:
- ✅ Channel-level isolation (bot can only access invited channels)
- ✅ Audit trail (Slack shows which bot sent message)
- ✅ Granular permissions

---

## 8. Complete Isolation Architecture

### 8.1 Recommended: Namespace-Per-Team

**Principle**: Each team gets their own namespace with full stack

```
Platform (monitoring-agents namespace):
  ├── Agents:
  │   ├── metrics-monitor-agent
  │   ├── github-remediation-agent
  │   └── correlation-rca-agent
  ├── MCP Servers:
  │   ├── platform-prometheus-mcp → platform-prometheus
  │   ├── platform-loki-mcp → loki (tenant_id=platform)
  │   └── platform-github-mcp → GitHub App (platform-bot)
  ├── Observability:
  │   └── platform-prometheus (scrapes platform namespaces only)
  ├── Secrets:
  │   ├── platform-github-token
  │   └── platform-slack-token
  └── RBAC:
      └── platform-team (RoleBinding)

Team1 (team1 namespace):
  ├── Agents:
  │   ├── team1-custom-agent
  │   └── team1-deployment-agent
  ├── MCP Servers:
  │   ├── team1-prometheus-mcp → team1-prometheus
  │   ├── team1-loki-mcp → loki (tenant_id=team1)
  │   └── team1-github-mcp → GitHub App (team1-bot)
  ├── Observability:
  │   └── team1-prometheus (scrapes team1 namespace only)
  ├── Secrets:
  │   ├── team1-github-token
  │   └── team1-slack-token
  └── RBAC:
      └── team1-members (RoleBinding)

Team2 (team2 namespace):
  └── (same structure as team1)
```

### 8.2 Isolation Matrix

| Resource | Platform Team | Team1 | Team2 |
|----------|--------------|-------|-------|
| **Namespace** | `monitoring-agents` | `team1` | `team2` |
| **Agents** | Platform agents | Team1 agents | Team2 agents |
| **MCP Servers** | Platform MCP | Team1 MCP | Team2 MCP |
| **Prometheus** | Platform metrics | Team1 metrics only | Team2 metrics only |
| **Loki** | tenant_id=platform | tenant_id=team1 | tenant_id=team2 |
| **Phoenix** | Platform Phoenix | Team1 Phoenix | Team2 Phoenix |
| **GitHub Token** | Platform GitHub App | Team1 GitHub App | Team2 GitHub App |
| **Slack Token** | Platform Slack bot | Team1 Slack bot | Team2 Slack bot |
| **ApprovalRequests** | monitoring-agents NS | team1 NS | team2 NS |
| **Inbox Access** | Platform team only | Team1 only | Team2 only |

**Result**: **Complete isolation** ✅

### 8.3 Cross-Namespace Communication (If Needed)

**Use Case**: Platform monitoring agent detects issue in Team1's namespace, needs to notify Team1

**Solution**: Agent creates ApprovalRequest in Team1's namespace

```python
# Platform agent (in monitoring-agents namespace)
def notify_team_of_issue(team_namespace, issue_data):
    # Create ApprovalRequest in team's namespace (not platform's)
    approval = create_approval_request(
        namespace=team_namespace,  # team1
        title=f"Platform detected issue in your namespace",
        request_type='notify',
        notifications={
            'channels': ['inbox', 'slack'],
            'slackChannel': f'#{team_namespace}-alerts'  # #team1-alerts
        }
    )
```

**RBAC**: Platform agents need `create` permission for ApprovalRequests in all namespaces

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: platform-agent-cross-namespace-approval
rules:
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-agents-approval-creator
subjects:
  - kind: ServiceAccount
    name: metrics-monitor-agent-sa
    namespace: monitoring-agents
roleRef:
  kind: ClusterRole
  name: platform-agent-cross-namespace-approval
  apiGroup: rbac.authorization.k8s.io
```

---

## 9. Trade-offs Analysis

### 9.1 Shared Namespace (monitoring-agents)

**Pros**:
- ✅ Simpler to deploy (one namespace)
- ✅ Fewer resources (one MCP server instance)
- ✅ Easier to manage

**Cons**:
- ❌ **No isolation** (agents see each other's data)
- ❌ **Shared credentials** (GitHub token, Slack token)
- ❌ **Complex RBAC** (need per-resource RBAC)
- ❌ **Security risks** (credential theft, data exfiltration)
- ❌ **Hard to implement multi-tenancy** (MCP servers need custom logic)

**When to use**:
- ⚠️ **Only for trusted platform team**
- ⚠️ All operators are from same organization
- ⚠️ No sensitive data in metrics/logs/traces

### 9.2 Per-Namespace Isolation

**Pros**:
- ✅ **Hard isolation** (Kubernetes-enforced)
- ✅ **Simple RBAC** (namespace-scoped)
- ✅ **No data leakage** (each team sees only their data)
- ✅ **Audit trail** (clear ownership)
- ✅ **Scalable** (add teams independently)
- ✅ **Secure by default**

**Cons**:
- ❌ More namespaces to manage
- ❌ More MCP server instances (resource overhead)
- ❌ Duplicate configurations

**When to use**:
- ✅ **Multi-team environment**
- ✅ Sensitive data in metrics/logs/traces
- ✅ Different trust levels between teams
- ✅ **Recommended for production**

---

## Summary & Final Recommendation

### The Answer to Your Question

**Q: "Would it be just per namespace and K8s RBAC?"**

**A: YES, absolutely.** ✅

**Without namespace isolation**:
- Agents share ConfigMaps, Secrets, network access
- Agents can steal credentials, query cross-team data
- RBAC alone is insufficient (too complex, error-prone)
- **Agent runs are NOT properly isolated** ❌

**With namespace isolation**:
- Each team/agent gets own namespace
- Hard boundary enforced by Kubernetes
- RBAC is simple (namespace-scoped)
- **Agent runs ARE properly isolated** ✅

### Recommended Architecture

**For Platform Monitoring Agents** (TODO_monitoring_agents.md):
- **Single namespace** (`monitoring-agents`) is OK **if and only if**:
  - All agents operated by same trusted platform team
  - All agents need access to all observability data
  - No cross-team isolation required

**For Multi-Team Agent Deployment**:
- **Namespace-per-team** is **REQUIRED** for proper isolation
- Each namespace gets:
  - Own agents
  - Own MCP servers
  - Own observability backends (Prometheus, Phoenix, Loki with tenant_id)
  - Own credentials (GitHub App, Slack bot)
  - Own RBAC

### Implementation Priority

**Phase 1: Single Namespace (Platform Team)**
- Deploy platform monitoring agents in `monitoring-agents`
- All agents operated by platform team
- Accept that agents are not isolated from each other
- **Good enough for MVP**

**Phase 2: Per-Team Namespaces (Multi-Tenancy)**
- Implement namespace-per-team model
- Deploy per-namespace MCP servers
- Configure observability multi-tenancy (Loki, Tempo)
- **Required for production multi-team deployment**

**The right answer**: **Start with Phase 1, plan for Phase 2** ✅

Your instinct was correct - **K8s namespace + RBAC is the isolation boundary** we need.
