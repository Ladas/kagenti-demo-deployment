# Agent Inbox Research - Executive Summary

**Date**: 2025-11-19
**Research Question**: How should we implement human-in-the-loop (HITL) approvals for Kagenti monitoring agents?

---

## Quick Decision Matrix

| Your Situation | Recommended Approach | Time to Implement |
|----------------|---------------------|-------------------|
| **MVP / POC** (getting started, < 10 approvals/day) | **GitHub Issues only** | 1 day |
| **Small team** (10-50 approvals/day, need mobile notifications) | **GitHub + Slack** | 3 days |
| **Production** (> 50 approvals/day, need rich UI) | **GitHub + Slack + Custom Inbox** | 3-4 months |
| **Multi-tenant** (multiple teams, isolation required) | **GitHub + Slack + Namespace isolation** | 2 weeks |

---

## Three Solutions Compared

### Option 1: GitHub Issues + PR Comments (Simplest ✅)

**How it works**:
- Agent creates GitHub issue with label `approval-request`
- Agent @mentions platform team in issue body
- GitHub sends notifications (email, Slack, mobile)
- Human comments `@agent approve` or `@agent reject <reason>`
- Agent polls issue comments every 30s

**Pros**:
- ✅ **Zero dev time** - GitHub already exists
- ✅ **Familiar interface** - Everyone uses GitHub
- ✅ **Built-in notifications** - Email, Slack, mobile app
- ✅ **RBAC included** - GitHub repo permissions + CODEOWNERS
- ✅ **Audit trail** - All comments logged forever

**Cons**:
- ❌ **Tied to GitHub** - Can't switch to GitLab easily
- ❌ **Polling overhead** - Agent polls GitHub API every 30s
- ❌ **Limited UI** - Markdown only, no embedded charts
- ❌ **No batch approvals** - One at a time

**When to use**: **MVP, small teams, developer-centric orgs**

---

### Option 2: Slack Interactive Messages (Fastest ✅)

**How it works**:
- Agent sends Slack message with interactive buttons
- Human taps "Approve" or "Reject" in Slack
- Slack webhook notifies agent
- Agent resumes execution

**Pros**:
- ✅ **Real-time** - No polling, instant notifications
- ✅ **Mobile-friendly** - Slack push notifications
- ✅ **Fast approvals** - One tap to approve

**Cons**:
- ❌ **Not persistent** - Messages scroll away
- ❌ **Limited context** - Hard to show complex evidence
- ❌ **Hard to search** - Slack search is limited

**When to use**: **Urgent approvals, on-call teams**

---

### Option 3: Custom Kagenti Inbox (Best UX ✅)

**How it works**:
- Agent creates ApprovalRequest CRD in Kubernetes
- kagenti-operator sends notifications to all channels (GitHub, Slack, Inbox)
- Human responds via kagenti-ui, GitHub, or Slack
- First response wins, other channels auto-close
- Agent polls ApprovalRequest CR status

**Pros**:
- ✅ **Rich UI** - Embedded trace graphs, metric charts, log viewer
- ✅ **Batch approvals** - Approve 10 similar requests at once
- ✅ **Full control** - Custom filtering, search, sorting
- ✅ **Multi-channel** - Users pick their preferred channel
- ✅ **Kubernetes-native** - Fits GitOps workflow

**Cons**:
- ❌ **Development cost** - 3-4 months to build
- ❌ **Maintenance overhead** - Need to maintain custom UI

**When to use**: **Production, large teams, high volume (> 50 approvals/day)**

---

## Recommended Hybrid Approach

**Best strategy**: Start with GitHub, add Slack, build custom inbox later

### Phase 1: GitHub Only (Week 1)

```python
# Agent creates GitHub issue
issue_number = github_client.create_issue(
    repo="redhat-et/kagenti-demo-deployment",
    title="[APPROVAL] Fix database connection pool",
    body=approval_template,
    labels=["approval-request"],
    assignees=["platform-admin"]
)

# Agent polls for response
response = wait_for_github_response(issue_number, timeout=24h)

if response['decision'] == 'approved':
    create_github_pr(pr_data)
```

**Result**: Working HITL in 1 day ✅

### Phase 2: Add Slack (Week 2-3)

```python
# 1. Create GitHub issue (primary)
issue_number = create_github_issue(approval_data)

# 2. Send Slack notification (secondary)
slack_client.send_message(
    channel="#platform-alerts",
    text=f"🔔 Approval needed: {approval_data['title']}",
    blocks=[...interactive_buttons...]
)

# 3. Poll both channels
response = wait_for_response_any_channel(issue_number, slack_ts)
```

**Result**: Faster approvals via Slack, still have GitHub audit trail ✅

### Phase 3: Add ApprovalRequest CRD (Week 4-6)

```python
# Agent creates K8s CR (operator handles publishing)
k8s_client.create_namespaced_custom_object(
    group='kagenti.dev',
    version='v1alpha1',
    namespace='monitoring-agents',
    plural='approvalrequests',
    body={
        'apiVersion': 'kagenti.dev/v1alpha1',
        'kind': 'ApprovalRequest',
        'spec': {
            'channels': {
                'github': {'enabled': True},
                'slack': {'enabled': True}
            }
        }
    }
)

# Agent polls CR status (simpler code)
response = wait_for_cr_response(approval_name)
```

**Result**: Centralized state, foundation for custom inbox ✅

### Phase 4: Add Custom Inbox (Week 7-16)

```typescript
// kagenti-ui: Rich inbox interface
function InboxPage() {
  const { approvals } = useApprovals();  // Fetch from K8s API

  return (
    <ApprovalList approvals={approvals}>
      {approval => (
        <ApprovalCard
          title={approval.spec.title}
          evidence={<EvidenceViewer data={approval.spec.evidence} />}
          onApprove={() => approve(approval)}
        />
      )}
    </ApprovalList>
  );
}
```

**Result**: Full-featured inbox, GitHub + Slack still work ✅

---

## User Isolation Strategy

**Question**: How do we prevent Team1 from seeing Team2's approvals?

**Answer**: **Namespace-based isolation** (Kubernetes RBAC)

### Architecture

```
team1 namespace:
  ├── team1-agents (pods)
  ├── team1-mcp-servers (prometheus, loki, github)
  ├── ApprovalRequests (scoped to team1)
  └── RoleBinding (team1-members can access)

team2 namespace:
  ├── team2-agents (pods)
  ├── team2-mcp-servers
  ├── ApprovalRequests (scoped to team2)
  └── RoleBinding (team2-members can access)

monitoring-agents namespace (platform):
  ├── platform-agents (metrics-monitor, github-remediation)
  ├── platform-mcp-servers
  └── ApprovalRequests (platform team only)
```

**Isolation mechanisms**:
- ✅ **Namespace boundary** - K8s enforces access control
- ✅ **Per-namespace Secrets** - Team1 can't read Team2's GitHub token
- ✅ **Per-namespace MCP servers** - Team1's Prometheus only scrapes team1
- ✅ **RBAC** - Inbox API uses user's K8s token (respects RBAC)
- ✅ **NetworkPolicies** - Team1 agents can't reach Team2's services

**Result**: Complete isolation without application-level filtering ✅

---

## Implementation Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| **Phase 1: GitHub Only** | 1 day | Agent creates issues, polls for `@agent approve` |
| **Phase 2: + Slack** | 3 days | Slack notifications, interactive buttons |
| **Phase 3: + CRD** | 2 weeks | ApprovalRequest CR, operator coordination |
| **Phase 4: + Inbox** | 3-4 months | Rich UI, batch approvals, visualizations |
| **Phase 5: Multi-tenant** | +2 weeks | Namespace isolation, per-team MCP servers |

**Total**: 1 day (MVP) → 3-4 months (production-ready)

---

## Research Documents

1. **[AGENT_INBOX_RESEARCH.md](./AGENT_INBOX_RESEARCH.md)** - Full technical research
   - LangChain Agent Inbox analysis (MIT licensed, don't adopt directly)
   - GitHub Issues implementation (detailed code examples)
   - Custom Kagenti Inbox architecture (CRD, operator, UI)
   - Slack integration (interactive messages, webhook handlers)

2. **[AGENT_INBOX_ISOLATION.md](./AGENT_INBOX_ISOLATION.md)** - User isolation strategy
   - Namespace-level isolation (recommended approach)
   - RBAC configuration (Keycloak SSO + K8s RBAC)
   - Cross-namespace scenarios (platform agents → team namespaces)
   - Security considerations (prevent privilege escalation)

3. **[AGENT_RUNTIME_ISOLATION_DEEP_DIVE.md](./AGENT_RUNTIME_ISOLATION_DEEP_DIVE.md)** - Agent security
   - Why namespace isolation is required (shared Secrets = bad)
   - Attack scenarios (credential theft, data exfiltration)
   - MCP server multi-tenancy (per-namespace MCP servers)
   - Observability data isolation (Prometheus, Loki, Phoenix)

4. **[AGENT_INBOX_COMBINED.md](./AGENT_INBOX_COMBINED.md)** - Hybrid approach
   - How to combine GitHub + Slack + Custom Inbox
   - Response sync logic (first response wins)
   - Phased implementation (week-by-week plan)
   - Cost-benefit analysis

---

## Final Recommendations

### For TODO_monitoring_agents.md (Platform Monitoring)

**Recommended approach**: **GitHub + Slack** (Phase 1-2)

**Rationale**:
- ✅ **Low cost**: 3 days of dev time
- ✅ **Fast**: Working solution immediately
- ✅ **Platform team only**: No multi-tenant isolation needed yet
- ✅ **Familiar tools**: Platform team uses GitHub daily
- ✅ **Notifications work**: GitHub + Slack already integrated

**Implementation**:
1. **Week 1**: github-remediation-agent creates GitHub issues
2. **Week 2**: Add Slack notifications for urgent approvals
3. **Month 2**: Add ApprovalRequest CRD if scale increases
4. **Month 3+**: Consider custom inbox if > 50 approvals/day

### For Multi-Tenant Production

**Recommended approach**: **GitHub + Slack + CRD + Namespace Isolation** (Phase 1-3 + Multi-tenant)

**Rationale**:
- ✅ **Security**: Namespace isolation prevents data leakage
- ✅ **Scalable**: Each team manages their own agents
- ✅ **RBAC**: K8s enforces access control
- ✅ **Flexible**: Teams choose GitHub, Slack, or Inbox

**Implementation**:
1. **Week 1-3**: GitHub + Slack (same as above)
2. **Week 4-6**: ApprovalRequest CRD + operator coordination
3. **Week 7-8**: Namespace-per-team infrastructure
4. **Week 9-10**: Per-namespace MCP servers
5. **Month 3+**: Custom inbox UI (optional)

---

## Key Takeaways

1. **Start simple**: GitHub Issues are sufficient for MVP (1 day of work)
2. **Add channels incrementally**: Slack (week 2), CRD (week 4), Custom Inbox (month 3)
3. **Namespace isolation is required**: For multi-tenant deployments, use namespace-per-team
4. **User choice matters**: Let users pick GitHub, Slack, or Inbox (hybrid approach)
5. **Don't build custom UI prematurely**: Only build when scale demands it (> 50 approvals/day)

**Bottom line**: **GitHub + Slack gets you 80% of the value in 3 days.** Build custom inbox only when you need the last 20%.
