# Agent Inbox Research & Implementation Plan

**Date**: 2025-11-19
**Status**: Research Complete, Implementation Plan Ready
**Target**: Kagenti Platform (kagenti-ui + kagenti-operator)

---

## Executive Summary

This document provides comprehensive research on **agent inbox patterns** for human-in-the-loop (HITL) workflows, specifically for integrating an inbox into the Kagenti platform. The research covers:

1. **LangChain Agent Inbox** - Open-source solution analysis
2. **Alternative Inbox Patterns** - Industry approaches to HITL workflows
3. **Kagenti Integration Architecture** - Proposed design for kagenti-ui + kagenti-operator
4. **Monitoring Agents Integration** - How agents from `TODO_monitoring_agents.md` will use the inbox
5. **Slack Integration** - Dual-channel communication (inbox + Slack)
6. **Implementation Plan** - Phased rollout with operator considerations

**Key Findings**:
- ✅ **GitHub Issues/PRs as inbox** is simplest - no custom UI needed, built-in notifications
- ✅ **Slack** works for quick approvals, mobile-friendly
- ✅ **Custom Kagenti Inbox** offers best UX but requires development
- ✅ **Hybrid approach** recommended: start with GitHub, add Slack, build custom UI later
- ✅ **Namespace isolation** required for multi-tenant agent deployments

---

## 1. Solution Comparison

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **GitHub Issues + PR Comments** | ✅ No dev needed<br>✅ Built-in notifications<br>✅ Familiar interface<br>✅ GitHub handles RBAC | ❌ Tied to GitHub<br>❌ Less structured<br>❌ Polling overhead | **Quick start, developer teams** |
| **Slack Interactive Messages** | ✅ Fast approvals<br>✅ Mobile-friendly<br>✅ Real-time notifications | ❌ Not persistent<br>❌ Limited context<br>❌ Hard to search history | **Urgent approvals, on-call** |
| **Custom Kagenti Inbox** | ✅ Rich UI/UX<br>✅ Structured data<br>✅ Batch operations<br>✅ Full control | ❌ Development cost<br>❌ Maintenance overhead | **Production, large teams** |
| **Hybrid (All Three)** | ✅ Best of all worlds<br>✅ User choice | ❌ Complexity<br>❌ Sync logic needed | **Enterprise deployment** |

**Recommendation**: Start with **GitHub + Slack** (low cost, fast to implement), migrate to **Custom Inbox** when scale demands it.

---

## 2. GitHub-Native Inbox (Issues + PR Comments)

### 2.1 How It Works

**Core Concept**: Use GitHub Issues as approval requests, PR comments for PR reviews

**Workflow**:
```
1. Agent needs approval
   ↓
2. Agent creates GitHub Issue with label "approval-request"
   ↓
3. Agent @mentions relevant people in issue body
   ↓
4. GitHub sends notifications (email, Slack, mobile)
   ↓
5. Human responds via issue comment
   ↓
6. Agent polls issue comments for response
   ↓
7. Agent parses response and resumes
```

**Example**:

```python
# Agent creates approval request as GitHub issue
def create_approval_request(pr_data):
    issue_body = f"""
## 🤖 Agent Approval Request

**Agent**: github-remediation-agent
**Type**: PR Review
**Severity**: High
**Correlation ID**: {pr_data['correlation_id']}

### Proposed Change

The monitoring agent detected a database connection pool exhaustion issue and proposes the following fix:

**Repository**: {pr_data['repository']}
**Branch**: {pr_data['branch']}

**Change**:
```diff
{pr_data['diff']}
```

### Evidence

- **Trace**: https://phoenix.localtest.me:9443/traces/{pr_data['trace_id']}
- **Metric**: `db_connections_active{{service=checkout}}` = 10/10
- **Logs**: 47 "connection timeout" errors in last 5 minutes

### Root Cause Analysis

**Cause**: Database connection pool exhausted during high traffic
**Confidence**: 92%
**Affected Service**: checkout-service

### Required Action

Please respond with:
- ✅ **Approve**: Comment `@agent approve` to create the PR
- ❌ **Reject**: Comment `@agent reject <reason>` to cancel
- ✏️ **Edit**: Comment with suggested changes, then `@agent approve`
- ⏰ **Defer**: Comment `@agent defer` to decide later

**Timeout**: This request will auto-reject in 24 hours if no response.

**Approvers**: @platform-admin @platform-oncall
    """

    # Create issue via GitHub API
    issue = github_client.create_issue(
        repo="redhat-et/kagenti-demo-deployment",
        title=f"[APPROVAL] {pr_data['title']}",
        body=issue_body,
        labels=["approval-request", "agent-generated", f"severity-{pr_data['severity']}"],
        assignees=["platform-admin", "platform-oncall"]
    )

    return issue.number

# Agent polls for response
def wait_for_approval(issue_number, timeout_hours=24):
    start_time = time.time()
    poll_interval = 30  # Poll every 30 seconds

    while time.time() - start_time < timeout_hours * 3600:
        # Fetch issue comments
        comments = github_client.get_issue_comments(
            repo="redhat-et/kagenti-demo-deployment",
            issue_number=issue_number
        )

        # Look for approval/rejection in comments
        for comment in reversed(comments):
            body = comment['body'].lower()

            if '@agent approve' in body:
                # Close issue as approved
                github_client.update_issue(
                    repo="redhat-et/kagenti-demo-deployment",
                    issue_number=issue_number,
                    state='closed',
                    labels=['approved']
                )
                return {'decision': 'approved', 'respondedBy': comment['user']['login']}

            elif '@agent reject' in body:
                reason = body.split('@agent reject')[1].strip()
                github_client.update_issue(
                    repo="redhat-et/kagenti-demo-deployment",
                    issue_number=issue_number,
                    state='closed',
                    labels=['rejected']
                )
                return {'decision': 'rejected', 'reason': reason, 'respondedBy': comment['user']['login']}

            elif '@agent defer' in body:
                return {'decision': 'deferred', 'respondedBy': comment['user']['login']}

        time.sleep(poll_interval)

    # Timeout reached
    github_client.update_issue(
        repo="redhat-et/kagenti-demo-deployment",
        issue_number=issue_number,
        state='closed',
        labels=['timeout']
    )
    return {'decision': 'timeout'}
```

### 2.2 PR-Based Review Workflow

**For PR reviews**: Use PR comments instead of issues

```python
def create_pr_with_review_request(pr_data):
    # 1. Create PR
    pr = github_client.create_pull_request(
        repo="redhat-et/kagenti-demo-deployment",
        title=pr_data['title'],
        body=f"""
🤖 **Generated by**: github-remediation-agent
📊 **Correlation ID**: {pr_data['correlation_id']}

## Root Cause Analysis

{pr_data['rca_description']}

## Evidence

{pr_data['evidence']}

## Verification Steps

- [ ] Review code changes
- [ ] Check metrics return to normal range
- [ ] Monitor for 24h post-deployment

---

**Approvers**: @platform-admin @platform-oncall

To approve: Review and merge this PR
To reject: Close this PR with comment explaining why
        """,
        head=pr_data['branch'],
        base='main',
        draft=True  # Start as draft
    )

    # 2. Request reviews
    github_client.request_reviewers(
        repo="redhat-et/kagenti-demo-deployment",
        pull_number=pr.number,
        reviewers=["platform-admin", "platform-oncall"]
    )

    # 3. Add comment with instructions
    github_client.create_issue_comment(
        repo="redhat-et/kagenti-demo-deployment",
        issue_number=pr.number,
        body="✅ Please review this PR. Mark as 'Ready for review' and approve to merge, or close to reject."
    )

    return pr.number

# Agent waits for PR approval
def wait_for_pr_approval(pr_number, timeout_hours=24):
    start_time = time.time()
    poll_interval = 60  # Poll every minute

    while time.time() - start_time < timeout_hours * 3600:
        pr = github_client.get_pull_request(
            repo="redhat-et/kagenti-demo-deployment",
            pull_number=pr_number
        )

        if pr['merged']:
            return {'decision': 'approved', 'mergedBy': pr['merged_by']['login']}

        elif pr['state'] == 'closed' and not pr['merged']:
            # PR was closed without merging
            return {'decision': 'rejected'}

        time.sleep(poll_interval)

    # Timeout - close PR
    github_client.update_pull_request(
        repo="redhat-et/kagenti-demo-deployment",
        pull_number=pr_number,
        state='closed'
    )
    return {'decision': 'timeout'}
```

### 2.3 GitHub Notifications

**Built-in notification channels**:
- ✅ **Email**: GitHub sends email to @mentioned users and assignees
- ✅ **Slack**: GitHub Slack app can notify channels when issues created
- ✅ **Mobile**: GitHub mobile app shows notifications
- ✅ **Web**: GitHub notification bell in navbar

**GitHub Slack Integration**:
```yaml
# .github/slack.yml (if using GitHub Slack integration)
notifications:
  - repo: redhat-et/kagenti-demo-deployment
    events:
      - issues
      - pull_request
    filters:
      labels:
        - approval-request
    channel: "#platform-alerts"
    message: "🔔 New approval request: {issue.title}"
```

### 2.4 GitHub RBAC for Approvals

**Repository permissions as RBAC**:
- ✅ **Write access** required to comment on issues/PRs
- ✅ **Admin/Maintainer** required to merge PRs
- ✅ **CODEOWNERS** can be used to enforce specific reviewers

**Example CODEOWNERS**:
```
# .github/CODEOWNERS

# Infrastructure changes require platform team approval
/components/00-infrastructure/ @platform-team
/components/01-platform/ @platform-team

# Observability changes require platform + SRE approval
/components/02-observability/ @platform-team @sre-team

# Team-specific changes
/apps/team1/ @team1-leads
/apps/team2/ @team2-leads
```

### 2.5 Pros & Cons

**Pros**:
- ✅ **Zero development cost** - GitHub already exists
- ✅ **Familiar interface** - Developers use GitHub daily
- ✅ **Built-in notifications** - Email, Slack, mobile
- ✅ **Audit trail** - All comments and decisions logged
- ✅ **RBAC built-in** - Repository permissions + CODEOWNERS
- ✅ **Search & filter** - GitHub issue search is powerful
- ✅ **Mobile-friendly** - GitHub mobile app works well

**Cons**:
- ❌ **Tied to GitHub** - Can't easily switch to GitLab/Gitea
- ❌ **Less structured** - Free-form comments vs structured responses
- ❌ **Polling overhead** - Agent must poll GitHub API every 30-60s
- ❌ **Rate limits** - GitHub API has rate limits (5000 requests/hour)
- ❌ **No batch approvals** - Can't easily approve 10 similar requests at once
- ❌ **Limited context** - Can't embed rich visualizations (trace graphs, metric charts)

**When to Use**:
- ✅ **MVP / Quick Start** - Get HITL working in 1 day
- ✅ **Developer-focused teams** - Everyone already uses GitHub
- ✅ **Low volume** - < 50 approval requests per day
- ❌ **High volume** - > 100 approvals/day (polling becomes issue)
- ❌ **Rich UI needed** - Need to show complex trace graphs, metric dashboards

---

## Table of Contents

1. [Solution Comparison](#1-solution-comparison)
2. [GitHub-Native Inbox (Issues + PR Comments)](#2-github-native-inbox-issues--pr-comments)
3. [LangChain Agent Inbox Analysis](#3-langchain-agent-inbox-analysis)
4. [Custom Kagenti Inbox Architecture](#4-custom-kagenti-inbox-architecture)
5. [Slack Integration Strategy](#5-slack-integration-strategy)
6. [Hybrid Approach: Combining All Solutions](#6-hybrid-approach-combining-all-solutions)
7. [Implementation Recommendations](#7-implementation-recommendations)
8. [Appendix: Technical Details](#appendix-technical-details)

---

## 1. LangChain Agent Inbox Analysis

### 1.1 Overview

**Repository**: https://github.com/langchain-ai/agent-inbox
**License**: MIT (fully open source ✅)
**Language**: TypeScript (98.7%), Next.js frontend
**Purpose**: Inbox UX for human-in-the-loop LangGraph agents

### 1.2 Key Features

1. **Interrupt Management**:
   - Agents call `interrupt("message")` to pause execution
   - User receives notification in inbox
   - User can: accept, edit, respond, or ignore
   - Agent resumes with user response

2. **Three Interaction Patterns**:
   - **Notify**: Inform user of important events (no action required)
   - **Question**: Ask user for input to unblock agent
   - **Review**: Request approval/edit before executing action

3. **Technical Stack**:
   - Next.js frontend with Tailwind CSS
   - Integrates with LangGraph deployments
   - Uses LangGraph's persistence layer for state management
   - Supports both Python and TypeScript agents

4. **Workflow**:
   ```python
   # Agent code (Python)
   from langgraph.prebuilt import interrupt

   # Pause and wait for human input
   response = interrupt("Should I proceed with database migration?")

   # Agent execution pauses here until user responds via inbox

   # Resume with user response
   if response == "yes":
       perform_migration()
   ```

5. **Deployment Options**:
   - Self-hosted (open source)
   - Hosted version at `dev.agentinbox.ai`

### 1.3 Pros & Cons for Kagenti

**Pros**:
- ✅ MIT licensed, can fork and customize
- ✅ Proven pattern for HITL workflows
- ✅ Clean UI/UX design
- ✅ Multi-channel support (can add Slack notifications)

**Cons**:
- ❌ Tightly coupled to LangGraph (Kagenti doesn't use LangGraph)
- ❌ Next.js frontend (Kagenti may have different UI stack)
- ❌ Requires LangGraph persistence layer (not applicable to Kagenti)
- ❌ Additional dependency overhead

**Recommendation**: **Don't adopt LangChain Agent Inbox directly**. Instead, use it as **reference architecture** and build a **Kagenti-native inbox** that fits the existing platform.

---

## 2. Alternative Inbox Patterns

### 2.1 Industry Approaches

| Framework/Tool | Approach | Key Features | Notification Channels |
|---------------|----------|--------------|----------------------|
| **HumanLayer SDK** | Decorator-based approvals | `@require_approval`, `human_as_tool` | Slack, Email, SMS, WhatsApp |
| **AG2 (AutoGen)** | Context-aware handoff | Interactive approval UI, multi-agent orchestration | Email, custom webhooks |
| **Inngest AgentKit** | Event-driven waiting | `waitForEvent()` for async responses | Slack (via events) |
| **Relay.app** | Workflow checkpoints | Pause workflow, request approval, resume | Email, Slack, in-app notifications |
| **Zapier HITL** | Approval steps | Pause Zap, send approval request, continue | Email, Slack, webhook |
| **Microsoft Agents** | Action-level approvals | Multi-agent approval workflows | Teams, email |

### 2.2 Common Patterns

**Pattern 1: Interrupt & Wait**
- Agent execution pauses at checkpoint
- State saved to persistence layer (database/Redis)
- Notification sent to human (email, Slack, inbox)
- Agent resumes when human responds
- **Used by**: LangChain, AG2, Relay

**Pattern 2: Asynchronous Approval Queue**
- Agent creates approval request and continues other work
- Human reviews queue asynchronously
- Agent polls for response or receives webhook callback
- **Used by**: HumanLayer, Inngest, Zapier

**Pattern 3: Escalation**
- Agent attempts task autonomously
- If blocked/uncertain, escalates to human
- Human resolves issue and provides guidance
- Agent learns from feedback (optional)
- **Used by**: AutoGen, Deepagents

**Pattern 4: Dual-Channel Notification**
- Approval request created in inbox (primary)
- Notification sent via Slack/email (secondary)
- Human can respond via either channel
- Response synced back to inbox
- **Used by**: HumanLayer, Relay

### 2.3 Best Practices

1. **Clear Action Context**: Provide agent name, task description, evidence/reasoning
2. **Multiple Response Options**: Accept, reject, edit, defer, provide feedback
3. **Timeout Handling**: Auto-reject or fallback action after N hours
4. **Audit Trail**: Log all approvals, rejections, edits
5. **RBAC**: Role-based access control for approvers
6. **Notification Preferences**: Users choose channels (inbox, Slack, email)
7. **Batch Approvals**: Allow approving multiple similar requests at once

---

## 3. Kagenti Inbox Architecture

### 3.1 Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kagenti Inbox System                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    kagenti-ui (Frontend)                   │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  Inbox Tab:                                                │  │
│  │  - List pending approvals                                  │  │
│  │  - Filter by: agent, severity, age, status                 │  │
│  │  - View approval details (context, evidence)               │  │
│  │  - Actions: Approve, Reject, Edit, Defer, Comment          │  │
│  │  - Search and batch operations                             │  │
│  │  - Notifications badge (unread count)                      │  │
│  └───────────────┬───────────────────────────────────────────┘  │
│                  │ REST API                                      │
│                  ▼                                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Kagenti Backend (API Server)                  │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  Endpoints:                                                │  │
│  │  - GET /api/v1/inbox/approvals                             │  │
│  │  - POST /api/v1/inbox/approvals/{id}/respond               │  │
│  │  - GET /api/v1/inbox/approvals/{id}                        │  │
│  │  - POST /api/v1/inbox/notifications/preferences            │  │
│  │                                                             │  │
│  │  Notification Service:                                     │  │
│  │  - Send Slack messages via Slack API                       │  │
│  │  - Send email notifications                                │  │
│  │  - Webhook delivery for custom integrations                │  │
│  └───────────────┬───────────────────────────────────────────┘  │
│                  │ K8s API                                       │
│                  ▼                                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │           kagenti-operator (Controller)                    │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  Watches:                                                  │  │
│  │  - ApprovalRequest CRD (new)                               │  │
│  │                                                             │  │
│  │  Reconciliation Logic:                                     │  │
│  │  1. Agent creates ApprovalRequest CR                       │  │
│  │  2. Operator updates status: Pending                       │  │
│  │  3. Operator triggers notification (Slack, email, inbox)   │  │
│  │  4. Human responds via kagenti-ui or Slack                 │  │
│  │  5. Operator updates CR status: Approved/Rejected/Edited   │  │
│  │  6. Agent reads CR status and resumes                      │  │
│  │                                                             │  │
│  │  Timeout Handler:                                          │  │
│  │  - Auto-update CR status after timeout period              │  │
│  │  - Configurable fallback action (reject, approve, defer)   │  │
│  └───────────────┬───────────────────────────────────────────┘  │
│                  │                                               │
│                  ▼                                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Kubernetes API Server                         │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  Custom Resources:                                         │  │
│  │  - ApprovalRequest (new CRD)                               │  │
│  │  - Agent (existing)                                        │  │
│  │  - AgentBuild (existing)                                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
├─────────────────────────────────────────────────────────────────┤
│                      Notification Channels                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────┐  ┌────────────┐  ┌────────────┐               │
│  │   Inbox    │  │   Slack    │  │   Email    │               │
│  │  (Primary) │  │ (Secondary)│  │ (Fallback) │               │
│  └────────────┘  └────────────┘  └────────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 New CRD: ApprovalRequest

```yaml
apiVersion: kagenti.dev/v1alpha1
kind: ApprovalRequest
metadata:
  name: github-remediation-pr-12345
  namespace: monitoring-agents
  labels:
    agent: github-remediation-agent
    severity: high
    request-type: review
spec:
  # Agent information
  agentName: github-remediation-agent
  agentNamespace: monitoring-agents

  # Request details
  requestType: review  # notify, question, review
  title: "Review PR for database connection pool fix"
  description: |
    The monitoring agent detected a database connection pool exhaustion issue
    and has generated a PR to increase the pool size from 10 to 50 connections.

    **Root Cause**: Database connection pool exhausted during high traffic
    **Confidence**: 0.92
    **Affected Service**: checkout-service

  # Context and evidence
  context:
    correlationId: "uuid-12345"
    severity: high
    issueType: infrastructure
    affectedComponents:
      - checkout-service
    evidence:
      traces:
        - id: "abc123def456"
          url: "https://phoenix.localtest.me:9443/traces/abc123"
      metrics:
        - query: "db_connections_active{service=checkout}"
          value: 10
          threshold: 10
      logs:
        - message: "connection timeout after 30s"
          count: 47

  # Proposed action (for review requests)
  proposedAction:
    type: pull_request
    repository: "redhat-et/kagenti-demo-deployment"
    branch: "agent-fix/infra-uuid-12345"
    title: "Fix: Increase database connection pool size"
    files:
      - path: "components/01-platform/checkout-service/deployment.yaml"
        diff: |
          @@ -15,7 +15,7 @@
                   env:
                     - name: DB_POOL_SIZE
          -            value: "10"
          +            value: "50"

  # Response options
  responseOptions:
    - accept: "Approve and create PR"
    - reject: "Reject this change"
    - edit: "Edit the proposed change"
    - defer: "Defer decision for later"

  # Notification settings
  notifications:
    channels:
      - inbox
      - slack
    slackChannel: "#platform-alerts"
    slackUsers:
      - "@platform-oncall"
    emails:
      - platform-team@example.com

  # Timeout configuration
  timeout:
    duration: 24h
    action: reject  # reject, approve, defer

  # RBAC
  approvers:
    - user: platform-admin
      role: admin
    - group: platform-team
      role: reviewer

status:
  # Current state
  phase: Pending  # Pending, Approved, Rejected, Edited, Deferred, TimedOut

  # Response data (when human responds)
  response:
    decision: approved  # approved, rejected, edited, deferred
    respondedBy: platform-admin
    respondedAt: "2025-11-19T10:45:00Z"
    comment: "LGTM, but monitor connection pool usage after deployment"
    editedAction:  # If decision == edited
      files:
        - path: "components/01-platform/checkout-service/deployment.yaml"
          diff: |
            @@ -15,7 +15,7 @@
                    env:
                      - name: DB_POOL_SIZE
            -            value: "10"
            +            value: "30"  # Changed from 50 to 30

  # Notification tracking
  notificationsSent:
    - channel: inbox
      sentAt: "2025-11-19T10:30:00Z"
      status: delivered
    - channel: slack
      sentAt: "2025-11-19T10:30:01Z"
      status: delivered
      messageId: "Cxxxx"

  # Audit trail
  events:
    - timestamp: "2025-11-19T10:30:00Z"
      type: Created
      message: "ApprovalRequest created by github-remediation-agent"
    - timestamp: "2025-11-19T10:30:01Z"
      type: NotificationSent
      message: "Notification sent via Slack and inbox"
    - timestamp: "2025-11-19T10:45:00Z"
      type: Responded
      message: "Approved by platform-admin"
```

### 3.3 Component Breakdown

#### 3.3.1 kagenti-ui (Frontend)

**New Feature**: Inbox Tab

**UI Components**:
- **Inbox List View**:
  - Card-based layout for each approval request
  - Filters: agent, severity, status, age
  - Sort: newest, oldest, highest severity
  - Search: full-text search across title, description
  - Batch actions: approve all, reject all

- **Approval Detail View**:
  - Full context and evidence display
  - Expandable sections: traces, metrics, logs
  - Diff viewer for code changes
  - Comment thread for discussion
  - Quick actions: approve, reject, edit, defer

- **Notification Badge**:
  - Unread count in navbar
  - Real-time updates via WebSocket or polling

**Implementation**:
```typescript
// Example React component
function InboxPage() {
  const { approvals, loading } = useApprovals();  // API hook

  return (
    <div className="inbox-page">
      <InboxFilters />
      <ApprovalList approvals={approvals} loading={loading} />
    </div>
  );
}

function ApprovalCard({ approval }: { approval: ApprovalRequest }) {
  return (
    <Card>
      <CardHeader>
        <Badge severity={approval.spec.context.severity} />
        <span>{approval.spec.title}</span>
        <TimeAgo timestamp={approval.metadata.creationTimestamp} />
      </CardHeader>

      <CardBody>
        <Markdown>{approval.spec.description}</Markdown>
        <EvidenceSection evidence={approval.spec.context.evidence} />
      </CardBody>

      <CardFooter>
        <Button onClick={() => approve(approval)}>Approve</Button>
        <Button onClick={() => reject(approval)}>Reject</Button>
        <Button onClick={() => edit(approval)}>Edit</Button>
        <Button onClick={() => defer(approval)}>Defer</Button>
      </CardFooter>
    </Card>
  );
}
```

#### 3.3.2 Kagenti Backend API

**New Endpoints**:

```typescript
// GET /api/v1/inbox/approvals
// List all approval requests with filters
interface ListApprovalsRequest {
  status?: 'Pending' | 'Approved' | 'Rejected' | 'Edited' | 'Deferred';
  agent?: string;
  severity?: 'critical' | 'high' | 'medium' | 'low';
  limit?: number;
  offset?: number;
}

// POST /api/v1/inbox/approvals/{id}/respond
// Respond to an approval request
interface RespondRequest {
  decision: 'approved' | 'rejected' | 'edited' | 'deferred';
  comment?: string;
  editedAction?: ProposedAction;  // If decision == edited
}

// GET /api/v1/inbox/approvals/{id}
// Get single approval request details

// POST /api/v1/inbox/notifications/preferences
// Update notification preferences
interface NotificationPreferences {
  channels: ('inbox' | 'slack' | 'email')[];
  slackUserId?: string;
  email?: string;
}
```

**Notification Service**:

```python
class NotificationService:
    def send_approval_notification(self, approval: ApprovalRequest):
        """Send notifications via configured channels"""

        # 1. Inbox (always enabled)
        # No action needed - inbox reads from K8s API

        # 2. Slack (if enabled)
        if 'slack' in approval.spec.notifications.channels:
            self._send_slack_notification(approval)

        # 3. Email (if enabled)
        if 'email' in approval.spec.notifications.channels:
            self._send_email_notification(approval)

    def _send_slack_notification(self, approval: ApprovalRequest):
        """Send Slack message with interactive buttons"""
        slack_client.chat_postMessage(
            channel=approval.spec.notifications.slackChannel,
            text=f"🔔 Approval needed: {approval.spec.title}",
            blocks=[
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": approval.spec.description}
                },
                {
                    "type": "actions",
                    "elements": [
                        {"type": "button", "text": "Approve", "action_id": "approve"},
                        {"type": "button", "text": "Reject", "action_id": "reject"},
                        {"type": "button", "text": "View in Inbox", "url": f"https://kagenti.localtest.me/inbox/{approval.metadata.name}"}
                    ]
                }
            ]
        )
```

#### 3.3.3 kagenti-operator (Controller)

**New Controller**: ApprovalRequestController

```python
from kubernetes import client, watch
import kopf

@kopf.on.create('kagenti.dev', 'v1alpha1', 'approvalrequests')
def approval_request_created(spec, meta, status, **kwargs):
    """Handle new ApprovalRequest creation"""

    # 1. Initialize status
    patch_status(meta['name'], meta['namespace'], {
        'phase': 'Pending',
        'events': [{
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'type': 'Created',
            'message': f"ApprovalRequest created by {spec['agentName']}"
        }]
    })

    # 2. Send notifications
    notification_service.send_approval_notification(
        approval_request=get_approval_request(meta['name'], meta['namespace'])
    )

    # 3. Update notification tracking
    patch_status(meta['name'], meta['namespace'], {
        'notificationsSent': [
            {'channel': 'inbox', 'sentAt': datetime.utcnow().isoformat() + 'Z', 'status': 'delivered'},
            {'channel': 'slack', 'sentAt': datetime.utcnow().isoformat() + 'Z', 'status': 'delivered'}
        ]
    })

    # 4. Schedule timeout check
    timeout_duration = parse_duration(spec['timeout']['duration'])
    schedule_timeout_check(meta['name'], meta['namespace'], timeout_duration)

@kopf.on.field('kagenti.dev', 'v1alpha1', 'approvalrequests', field='status.response')
def approval_response_updated(old, new, meta, **kwargs):
    """Handle human response to approval request"""

    if new is None:
        return  # No response yet

    decision = new['decision']

    # Update status phase based on decision
    phase_map = {
        'approved': 'Approved',
        'rejected': 'Rejected',
        'edited': 'Edited',
        'deferred': 'Deferred'
    }

    patch_status(meta['name'], meta['namespace'], {
        'phase': phase_map[decision],
        'events': [{
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'type': 'Responded',
            'message': f"{decision.capitalize()} by {new['respondedBy']}"
        }]
    })

    # Notify agent (agent polls ApprovalRequest status)
    logger.info(f"ApprovalRequest {meta['name']} {decision} by {new['respondedBy']}")

@kopf.timer('kagenti.dev', 'v1alpha1', 'approvalrequests', interval=60)
def check_timeouts(spec, status, meta, **kwargs):
    """Check for timed-out approval requests"""

    if status.get('phase') != 'Pending':
        return  # Already responded

    timeout_duration = parse_duration(spec['timeout']['duration'])
    created_at = parse_timestamp(meta['creationTimestamp'])

    if datetime.utcnow() - created_at > timeout_duration:
        # Timeout reached
        fallback_action = spec['timeout']['action']

        patch_status(meta['name'], meta['namespace'], {
            'phase': 'TimedOut',
            'response': {
                'decision': fallback_action,
                'respondedBy': 'system',
                'respondedAt': datetime.utcnow().isoformat() + 'Z',
                'comment': f'Auto-{fallback_action} due to timeout after {spec["timeout"]["duration"]}'
            }
        })
```

### 3.4 Agent Integration Pattern

**How Agents Use the Inbox**:

```python
# Example: GitHub Remediation Agent creating an approval request

from kubernetes import client, config
import yaml
import time

class GitHubRemediationAgent:
    def __init__(self):
        config.load_incluster_config()
        self.k8s_client = client.CustomObjectsApi()

    def create_pr_with_approval(self, pr_data):
        """Create PR with human approval"""

        # 1. Create ApprovalRequest CR
        approval_request = {
            'apiVersion': 'kagenti.dev/v1alpha1',
            'kind': 'ApprovalRequest',
            'metadata': {
                'name': f"github-pr-{pr_data['correlation_id']}",
                'namespace': 'monitoring-agents',
                'labels': {
                    'agent': 'github-remediation-agent',
                    'severity': pr_data['severity'],
                    'request-type': 'review'
                }
            },
            'spec': {
                'agentName': 'github-remediation-agent',
                'agentNamespace': 'monitoring-agents',
                'requestType': 'review',
                'title': f"Review PR: {pr_data['title']}",
                'description': pr_data['description'],
                'context': pr_data['context'],
                'proposedAction': {
                    'type': 'pull_request',
                    'repository': pr_data['repository'],
                    'branch': pr_data['branch'],
                    'title': pr_data['title'],
                    'files': pr_data['files']
                },
                'responseOptions': [
                    {'accept': 'Approve and create PR'},
                    {'reject': 'Reject this change'},
                    {'edit': 'Edit the proposed change'},
                    {'defer': 'Defer decision for later'}
                ],
                'notifications': {
                    'channels': ['inbox', 'slack'],
                    'slackChannel': '#platform-alerts',
                    'emails': ['platform-team@example.com']
                },
                'timeout': {
                    'duration': '24h',
                    'action': 'reject'
                }
            }
        }

        # Create the ApprovalRequest
        self.k8s_client.create_namespaced_custom_object(
            group='kagenti.dev',
            version='v1alpha1',
            namespace='monitoring-agents',
            plural='approvalrequests',
            body=approval_request
        )

        # 2. Wait for human response (polling pattern)
        approval_name = approval_request['metadata']['name']
        max_wait_time = 24 * 60 * 60  # 24 hours
        poll_interval = 30  # 30 seconds

        elapsed = 0
        while elapsed < max_wait_time:
            # Fetch ApprovalRequest status
            approval = self.k8s_client.get_namespaced_custom_object(
                group='kagenti.dev',
                version='v1alpha1',
                namespace='monitoring-agents',
                plural='approvalrequests',
                name=approval_name
            )

            status = approval.get('status', {})
            phase = status.get('phase', 'Pending')

            if phase != 'Pending':
                # Human responded!
                response = status.get('response', {})
                decision = response['decision']

                if decision == 'approved':
                    # Create PR
                    self.create_github_pr(pr_data)
                    logger.info(f"PR created after approval by {response['respondedBy']}")

                elif decision == 'edited':
                    # Use edited action
                    edited_action = response.get('editedAction', {})
                    pr_data['files'] = edited_action.get('files', pr_data['files'])
                    self.create_github_pr(pr_data)
                    logger.info(f"PR created with edits by {response['respondedBy']}")

                elif decision == 'rejected':
                    logger.info(f"PR rejected by {response['respondedBy']}: {response.get('comment')}")

                elif decision == 'deferred':
                    logger.info(f"PR deferred by {response['respondedBy']}, will retry later")

                return decision

            # Still waiting, sleep and poll again
            time.sleep(poll_interval)
            elapsed += poll_interval

        # Timeout reached (should have been handled by operator)
        logger.warning(f"Approval request {approval_name} reached max wait time")
        return 'timeout'

    def create_github_pr(self, pr_data):
        """Create GitHub PR via GitHub MCP"""
        # ... GitHub API call ...
        pass
```

---

## 4. Monitoring Agents Integration

### 4.1 How Monitoring Agents Use Inbox

Based on `TODO_monitoring_agents.md`, the monitoring agents system includes:

1. **Metrics Monitor Agent** - Detects metric anomalies
2. **Trace Analyzer Agent** - Detects trace errors/latency
3. **Log Analyzer Agent** - Detects error patterns in logs
4. **Orchestrator Agent** - Coordinates detection events
5. **Correlation & RCA Agent** - Performs root cause analysis
6. **GitHub Remediation Agent** - Creates PRs with fixes

**Inbox Integration Points**:

| Agent | Inbox Use Case | Request Type | Example |
|-------|---------------|--------------|---------|
| **Metrics Monitor** | Notify about critical metric anomaly | `notify` | "CPU usage spiked to 95% on checkout-service" |
| **Trace Analyzer** | Notify about error spike | `notify` | "47 error traces detected in last 5 minutes" |
| **Log Analyzer** | Notify about exception pattern | `notify` | "NullPointerException detected 100+ times" |
| **Orchestrator** | Question: Which issue to prioritize? | `question` | "Multiple issues detected, which should I investigate first?" |
| **Correlation & RCA** | Review root cause analysis | `review` | "RCA: Database connection pool exhausted (confidence: 0.92)" |
| **GitHub Remediation** | Review PR before creation | `review` | "Review PR to increase DB connection pool size" |

### 4.2 Workflow Example

**Scenario**: Database connection pool exhaustion detected

1. **Detection Phase** (No inbox yet):
   - Metrics Monitor detects high DB connection count
   - Trace Analyzer detects connection timeout errors
   - Log Analyzer finds "connection timeout" logs
   - Events published to Redis stream

2. **Orchestration Phase** (Optional inbox):
   - Orchestrator groups related events
   - **OPTIONAL**: Creates `notify` ApprovalRequest to inform team
   - Triggers Correlation Agent

3. **Correlation Phase** (Optional inbox):
   - Correlation Agent queries Korrel8r for signal correlation
   - LLM performs root cause analysis
   - **OPTIONAL**: Creates `review` ApprovalRequest for RCA validation
   - Human reviews RCA, approves/edits confidence score

4. **Remediation Phase** (Inbox required):
   - GitHub Remediation Agent generates PR to increase DB pool size
   - **REQUIRED**: Creates `review` ApprovalRequest
   - Notification sent to Slack + inbox
   - Human reviews PR in inbox
   - Human approves with comment: "LGTM, but monitor usage"
   - Agent creates GitHub PR

### 4.3 Agent Configuration

```yaml
# Example: GitHub Remediation Agent configuration
agent_name: github-remediation-agent

# Inbox integration settings
inbox:
  enabled: true

  # When to request approval
  approval_required_for:
    - pull_request_creation
    - issue_creation (optional)

  # Notification channels
  notification_channels:
    - inbox
    - slack

  # Timeout settings
  approval_timeout: 24h
  timeout_action: reject  # reject, approve, defer

  # RBAC
  approvers:
    - group: platform-team
      role: reviewer
    - user: platform-admin
      role: admin
```

### 4.4 Agent Behavior Patterns

**Pattern 1: Notify (No Blocking)**
```python
# Agent sends notification but doesn't wait
def notify_anomaly_detected(anomaly_data):
    create_approval_request(
        request_type='notify',
        title=f"Anomaly detected: {anomaly_data['metric']}",
        description=anomaly_data['description'],
        timeout={'duration': '1h', 'action': 'auto-close'}
    )
    # Agent continues immediately (no blocking)
```

**Pattern 2: Question (Blocking with Timeout)**
```python
# Agent waits for human input, with fallback
def prioritize_issues(issues):
    response = create_approval_request_and_wait(
        request_type='question',
        title="Multiple issues detected - prioritization needed",
        description="Which issue should I investigate first?",
        response_options=[
            {'option': 'issue_1', 'label': 'CPU spike (critical)'},
            {'option': 'issue_2', 'label': 'Memory leak (high)'},
            {'option': 'issue_3', 'label': 'Slow query (medium)'},
            {'option': 'auto', 'label': 'Auto-prioritize by severity'}
        ],
        timeout={'duration': '5m', 'action': 'auto'}  # 5-minute timeout, auto-prioritize
    )

    if response['decision'] == 'timeout':
        return auto_prioritize(issues)  # Fallback
    else:
        return issues[response['selectedOption']]
```

**Pattern 3: Review (Blocking, Human Required)**
```python
# Agent waits for human approval before taking action
def create_pr_with_approval(pr_data):
    response = create_approval_request_and_wait(
        request_type='review',
        title=f"Review PR: {pr_data['title']}",
        description=pr_data['description'],
        proposed_action=pr_data,
        timeout={'duration': '24h', 'action': 'reject'}  # 24h timeout, reject by default
    )

    if response['decision'] == 'approved':
        create_github_pr(pr_data)
        return 'pr_created'

    elif response['decision'] == 'edited':
        # Use human's edited version
        create_github_pr(response['editedAction'])
        return 'pr_created_edited'

    elif response['decision'] in ['rejected', 'timeout']:
        logger.info(f"PR creation rejected: {response.get('comment')}")
        return 'pr_rejected'
```

---

## 5. Slack Integration Strategy

### 5.1 Dual-Channel Architecture

**Primary Channel**: Kagenti Inbox (kagenti-ui)
**Secondary Channel**: Slack (notifications + quick actions)

**Workflow**:
1. Agent creates ApprovalRequest CR
2. kagenti-operator sends notifications to BOTH channels:
   - Inbox: Full context, always available
   - Slack: Notification + quick action buttons
3. Human responds via EITHER channel:
   - Via Inbox: Full UI experience
   - Via Slack: Interactive buttons for quick actions
4. Response synced back to ApprovalRequest CR
5. Agent reads CR and resumes

### 5.2 Slack Message Format

**Example Slack Message**:

```json
{
  "channel": "#platform-alerts",
  "text": "🔔 Approval needed: Review PR for database connection pool fix",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "🔔 Approval Request"
      }
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Agent:*\ngithub-remediation-agent"
        },
        {
          "type": "mrkdwn",
          "text": "*Severity:*\n🔴 High"
        },
        {
          "type": "mrkdwn",
          "text": "*Type:*\nPR Review"
        },
        {
          "type": "mrkdwn",
          "text": "*Timeout:*\n24 hours"
        }
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Title:* Review PR for database connection pool fix\n\n*Description:*\nThe monitoring agent detected a database connection pool exhaustion issue and has generated a PR to increase the pool size from 10 to 50 connections.\n\n**Root Cause**: Database connection pool exhausted during high traffic\n**Confidence**: 0.92\n**Affected Service**: checkout-service"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Evidence:*\n• Trace: <https://phoenix.localtest.me:9443/traces/abc123|abc123def456>\n• Metric: `db_connections_active{service=checkout}` = 10/10\n• Logs: 47 \"connection timeout\" errors"
      }
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "✅ Approve"
          },
          "style": "primary",
          "value": "approve",
          "action_id": "approval_approve"
        },
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "❌ Reject"
          },
          "style": "danger",
          "value": "reject",
          "action_id": "approval_reject"
        },
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "✏️ Edit in Inbox"
          },
          "url": "https://kagenti.localtest.me:9443/inbox/github-pr-12345"
        },
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "⏰ Defer"
          },
          "value": "defer",
          "action_id": "approval_defer"
        }
      ]
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "Approval ID: `github-pr-12345` | Created: <!date^1732016400^{date_short_pretty} at {time}|2025-11-19 10:30>"
        }
      ]
    }
  ]
}
```

### 5.3 Slack Interactivity Endpoints

**Slack App Configuration**:

1. **Slash Commands** (optional):
   - `/kagenti-inbox list` - List pending approvals
   - `/kagenti-inbox approve <id>` - Approve by ID
   - `/kagenti-inbox reject <id>` - Reject by ID

2. **Interactive Components**:
   - Button clicks: `approval_approve`, `approval_reject`, `approval_defer`
   - Request URL: `https://kagenti.localtest.me:9443/api/v1/slack/interactions`

3. **Event Subscriptions** (optional):
   - `message.channels` - Allow thread-based discussions
   - Request URL: `https://kagenti.localtest.me:9443/api/v1/slack/events`

**Backend Handler**:

```python
from flask import Flask, request, jsonify
from slack_sdk import WebClient

app = Flask(__name__)
slack_client = WebClient(token=os.environ['SLACK_BOT_TOKEN'])

@app.route('/api/v1/slack/interactions', methods=['POST'])
def handle_slack_interaction():
    """Handle Slack button clicks"""

    payload = json.loads(request.form['payload'])
    action = payload['actions'][0]
    action_id = action['action_id']
    user_id = payload['user']['id']

    # Extract approval ID from message
    approval_id = extract_approval_id_from_message(payload['message'])

    # Map Slack action to approval decision
    decision_map = {
        'approval_approve': 'approved',
        'approval_reject': 'rejected',
        'approval_defer': 'deferred'
    }
    decision = decision_map.get(action_id)

    if decision:
        # Update ApprovalRequest CR
        update_approval_request(
            name=approval_id,
            namespace='monitoring-agents',
            decision=decision,
            responded_by=get_user_email(user_id),
            comment=f"Responded via Slack by {get_user_name(user_id)}"
        )

        # Update Slack message
        slack_client.chat_update(
            channel=payload['channel']['id'],
            ts=payload['message']['ts'],
            text=f"✅ {decision.capitalize()} by <@{user_id}>",
            blocks=[
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"✅ *{decision.capitalize()}* by <@{user_id}>\n\nView details in <https://kagenti.localtest.me:9443/inbox/{approval_id}|Kagenti Inbox>"
                    }
                }
            ]
        )

        return jsonify({"ok": True})

    return jsonify({"error": "Unknown action"}), 400
```

### 5.4 Slack vs Inbox Decision Matrix

| Scenario | Best Channel | Reason |
|----------|-------------|--------|
| Quick approve/reject (high confidence) | Slack | Fast, mobile-friendly, context already in message |
| Complex review (need to see code diff) | Inbox | Rich UI, diff viewer, full context |
| Edit proposed action | Inbox | Requires text input and code editing |
| On-call urgent approval | Slack | Mobile push notification, faster response |
| Batch approvals (multiple similar requests) | Inbox | Better UI for bulk operations |
| Audit/review history | Inbox | Searchable, filterable, persistent |

### 5.5 User Notification Preferences

**User Settings** (stored in user profile):

```yaml
user: platform-admin
notification_preferences:
  # Channels to receive notifications
  channels:
    - inbox  # Always enabled
    - slack  # Optional
    - email  # Optional

  # Severity-based routing
  severity_routing:
    critical:
      channels: [inbox, slack, email]  # All channels for critical
      slack_urgency: high  # Mobile push notification
    high:
      channels: [inbox, slack]
      slack_urgency: normal
    medium:
      channels: [inbox]
    low:
      channels: [inbox]

  # Time-based routing (working hours vs off-hours)
  time_routing:
    working_hours:
      start: "09:00"
      end: "17:00"
      timezone: "America/New_York"
      channels: [inbox, slack]
    off_hours:
      channels: [inbox, email]  # No Slack during off-hours

  # Slack settings
  slack:
    user_id: "U12345"
    dm_enabled: true  # Send DM in addition to channel message
    thread_notifications: true  # Notify on thread replies

  # Email settings
  email:
    address: "admin@example.com"
    digest: false  # false = immediate, true = daily digest
```

---

## 6. Implementation Plan

### 6.1 Phased Rollout

#### Phase 1: Foundation (Weeks 1-3)

**Goals**:
- Create ApprovalRequest CRD
- Implement basic operator controller
- Build inbox API endpoints

**Tasks**:
- [ ] Design ApprovalRequest CRD schema (Week 1)
- [ ] Implement CRD in kagenti-operator (Week 1)
- [ ] Create ApprovalRequestController (Week 2)
  - [ ] Handle CR creation
  - [ ] Handle CR status updates
  - [ ] Implement timeout checking
- [ ] Build backend API endpoints (Week 2-3)
  - [ ] `GET /api/v1/inbox/approvals`
  - [ ] `GET /api/v1/inbox/approvals/{id}`
  - [ ] `POST /api/v1/inbox/approvals/{id}/respond`
- [ ] Unit tests for operator and API (Week 3)

**Deliverables**:
- ✅ ApprovalRequest CRD installed in cluster
- ✅ Operator controller watching ApprovalRequests
- ✅ Backend API functional

#### Phase 2: Frontend (Weeks 4-6)

**Goals**:
- Build inbox UI in kagenti-ui
- Implement filtering, sorting, search
- Add approval detail view

**Tasks**:
- [ ] Design inbox UI mockups (Week 4)
- [ ] Implement Inbox List View (Week 4-5)
  - [ ] ApprovalCard component
  - [ ] Filters (status, agent, severity)
  - [ ] Search functionality
  - [ ] Pagination
- [ ] Implement Approval Detail View (Week 5-6)
  - [ ] Context and evidence display
  - [ ] Diff viewer for code changes
  - [ ] Comment thread
  - [ ] Action buttons (approve, reject, edit, defer)
- [ ] Add inbox tab to kagenti-ui navbar (Week 6)
- [ ] Implement real-time updates (WebSocket or polling) (Week 6)

**Deliverables**:
- ✅ Inbox tab in kagenti-ui
- ✅ Full approval workflow (create → review → respond)

#### Phase 3: Slack Integration (Weeks 7-9)

**Goals**:
- Integrate Slack notifications
- Implement interactive buttons
- Support Slack → Inbox response sync

**Tasks**:
- [ ] Create Slack app (Week 7)
- [ ] Implement NotificationService (Week 7-8)
  - [ ] Send Slack messages on ApprovalRequest creation
  - [ ] Format messages with blocks and buttons
- [ ] Implement Slack interaction handlers (Week 8)
  - [ ] Handle button clicks (approve, reject, defer)
  - [ ] Update ApprovalRequest CR from Slack responses
  - [ ] Update Slack message after response
- [ ] Implement user notification preferences (Week 9)
  - [ ] Store preferences in user profile
  - [ ] Apply severity and time-based routing
- [ ] Test Slack integration end-to-end (Week 9)

**Deliverables**:
- ✅ Slack notifications working
- ✅ Slack interactive buttons working
- ✅ Dual-channel (Inbox + Slack) response sync

#### Phase 4: Monitoring Agents Integration (Weeks 10-12)

**Goals**:
- Integrate inbox with monitoring agents
- Test end-to-end workflows
- Validate approval patterns

**Tasks**:
- [ ] Update GitHub Remediation Agent (Week 10)
  - [ ] Add approval request creation
  - [ ] Implement polling for response
  - [ ] Handle approved/rejected/edited responses
- [ ] Update Correlation & RCA Agent (Week 10-11)
  - [ ] Add optional RCA review approval
  - [ ] Test question pattern for prioritization
- [ ] Add notify pattern to detection agents (Week 11)
  - [ ] Metrics Monitor: notify on critical anomalies
  - [ ] Trace Analyzer: notify on error spikes
  - [ ] Log Analyzer: notify on exception patterns
- [ ] End-to-end testing (Week 12)
  - [ ] Test full workflow: detection → correlation → RCA → approval → PR
  - [ ] Test timeout handling
  - [ ] Test Slack integration
  - [ ] Test approval editing

**Deliverables**:
- ✅ Monitoring agents using inbox for approvals
- ✅ End-to-end workflow validated

#### Phase 5: Enhancements (Weeks 13-16)

**Goals**:
- Add advanced features
- Improve UX
- Add analytics

**Tasks**:
- [ ] Batch approvals (Week 13)
- [ ] Email notifications (Week 13)
- [ ] Approval templates (Week 14)
- [ ] Analytics dashboard (Week 14-15)
  - [ ] Approval response time
  - [ ] Approval rate by agent
  - [ ] Timeout rate
- [ ] RBAC enforcement (Week 15)
  - [ ] Role-based approver lists
  - [ ] Group-based approvals
- [ ] Approval delegation (Week 16)
- [ ] Mobile-optimized inbox UI (Week 16)

**Deliverables**:
- ✅ Production-ready inbox system
- ✅ Full feature set

### 6.2 Minimal Viable Product (MVP)

**Target**: 6 weeks
**Features**:
- ApprovalRequest CRD
- Basic operator controller
- Inbox UI (list + detail views)
- Single agent integration (GitHub Remediation)
- No Slack integration (inbox only)

**Scope**:
- Review pattern only (no notify or question patterns)
- Manual polling (no real-time updates)
- Basic timeout handling
- No RBAC, no batch operations

---

## 7. Operator Considerations

### 7.1 Should We Create a New Operator?

**Question**: Should we create a separate `kagenti-inbox-operator` or extend `kagenti-operator`?

**Option A: Extend kagenti-operator** ✅ RECOMMENDED

**Pros**:
- ✅ Simpler architecture (fewer operators to manage)
- ✅ Shared codebase and dependencies
- ✅ Easier to coordinate Agent + ApprovalRequest interactions
- ✅ Single RBAC setup
- ✅ Consistent deployment strategy

**Cons**:
- ❌ Larger operator binary
- ❌ Single point of failure (but mitigated by replicas)

**Option B: Create separate kagenti-inbox-operator**

**Pros**:
- ✅ Separation of concerns
- ✅ Can scale independently
- ✅ Easier to remove if inbox is deprecated

**Cons**:
- ❌ More complexity (2 operators to manage)
- ❌ Coordination challenges between operators
- ❌ Duplicate dependencies

**Recommendation**: **Extend kagenti-operator** with a new controller for ApprovalRequest. Keep it in the same codebase as the Agent controller.

### 7.2 Operator Architecture

```
kagenti-operator/
├── controllers/
│   ├── agent_controller.py          # Existing
│   ├── approval_request_controller.py  # NEW
│   └── __init__.py
├── api/
│   └── v1alpha1/
│       ├── agent.py                  # Existing
│       ├── approval_request.py       # NEW CRD
│       └── __init__.py
├── services/
│   ├── notification_service.py      # NEW
│   └── timeout_service.py           # NEW
└── main.py
```

### 7.3 Operator Deployment

**Deployment Manifest**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kagenti-operator
  namespace: kagenti-system
spec:
  replicas: 2  # HA for production
  template:
    spec:
      serviceAccountName: kagenti-operator
      containers:
        - name: operator
          image: quay.io/kagenti/kagenti-operator:v0.5.0
          env:
            - name: WATCH_NAMESPACE
              value: ""  # Watch all namespaces
            - name: SLACK_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: kagenti-operator-secrets
                  key: slack-bot-token
            - name: SMTP_HOST
              value: "smtp.sendgrid.net"
            - name: SMTP_PORT
              value: "587"
            - name: SMTP_USERNAME
              valueFrom:
                secretKeyRef:
                  name: kagenti-operator-secrets
                  key: smtp-username
            - name: SMTP_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: kagenti-operator-secrets
                  key: smtp-password
```

### 7.4 CRD Registration

**Add ApprovalRequest CRD to kagenti-operator**:

```yaml
# config/crd/approval_request.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: approvalrequests.kagenti.dev
spec:
  group: kagenti.dev
  names:
    kind: ApprovalRequest
    listKind: ApprovalRequestList
    plural: approvalrequests
    singular: approvalrequest
    shortNames:
      - apr
  scope: Namespaced
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              # ... (see section 3.2 for full spec)
            status:
              # ... (see section 3.2 for full status)
      subresources:
        status: {}
      additionalPrinterColumns:
        - name: Phase
          type: string
          jsonPath: .status.phase
        - name: Agent
          type: string
          jsonPath: .spec.agentName
        - name: Type
          type: string
          jsonPath: .spec.requestType
        - name: Age
          type: date
          jsonPath: .metadata.creationTimestamp
```

---

## 8. Testing & Validation

### 8.1 Unit Tests

**Operator Tests**:
- [ ] ApprovalRequestController creation handling
- [ ] ApprovalRequestController response handling
- [ ] Timeout checking logic
- [ ] Notification sending (mocked Slack/email)

**API Tests**:
- [ ] List approvals endpoint
- [ ] Get approval endpoint
- [ ] Respond to approval endpoint
- [ ] Notification preferences endpoint

**Frontend Tests**:
- [ ] Inbox list rendering
- [ ] Approval detail rendering
- [ ] Approve/reject/edit actions
- [ ] Filtering and search

### 8.2 Integration Tests

**End-to-End Workflows**:
- [ ] Agent creates ApprovalRequest → Human approves via inbox → Agent resumes
- [ ] Agent creates ApprovalRequest → Human approves via Slack → Agent resumes
- [ ] Agent creates ApprovalRequest → Timeout reached → Agent handles rejection
- [ ] Agent creates ApprovalRequest → Human edits → Agent uses edited action

**Slack Integration**:
- [ ] ApprovalRequest creation sends Slack notification
- [ ] Slack button click updates ApprovalRequest CR
- [ ] Slack message updated after response
- [ ] Slack thread-based discussions

### 8.3 Load Testing

**Scenarios**:
- [ ] 100 concurrent ApprovalRequests
- [ ] 1000 approvals in inbox (pagination performance)
- [ ] High-frequency approval creation (100/min)
- [ ] Timeout checking at scale (1000 pending approvals)

### 8.4 User Acceptance Testing

**Test Cases**:
- [ ] Platform engineer receives approval request, reviews in inbox, approves
- [ ] On-call engineer receives Slack notification, approves via Slack
- [ ] Team lead receives critical approval, edits proposed action, submits
- [ ] Approval request times out after 24h, agent handles rejection
- [ ] User changes notification preferences, receives notifications via new channels

---

## 9. Timeline & Resources

### 9.1 Timeline

**MVP (6 weeks)**:
- Weeks 1-3: Foundation (CRD, operator, API)
- Weeks 4-6: Frontend (inbox UI)

**Full Implementation (16 weeks)**:
- Weeks 1-6: MVP
- Weeks 7-9: Slack integration
- Weeks 10-12: Monitoring agents integration
- Weeks 13-16: Enhancements (batch approvals, analytics, RBAC)

### 9.2 Team Resources

**Minimum Team**:
- 1 Backend Engineer (operator + API)
- 1 Frontend Engineer (kagenti-ui)
- 1 DevOps Engineer (deployment, testing)
- 1 QA Engineer (testing, validation)

**Optimal Team**:
- 2 Backend Engineers (operator + API + Slack integration)
- 2 Frontend Engineers (inbox UI + real-time updates)
- 1 DevOps Engineer
- 1 QA Engineer

### 9.3 Dependencies

**External Dependencies**:
- Slack API (for Slack integration)
- SMTP service (for email notifications)
- Kubernetes cluster with CRD support

**Internal Dependencies**:
- kagenti-operator (extend with ApprovalRequest controller)
- kagenti-ui (add inbox tab)
- Monitoring agents (integrate approval requests)

---

## 10. Recommendations

### 10.1 Key Decisions

1. **✅ DO NOT adopt LangChain Agent Inbox directly**
   - Build Kagenti-native solution
   - Use LangChain inbox as reference architecture only

2. **✅ Extend kagenti-operator (DO NOT create new operator)**
   - Add ApprovalRequestController to existing operator
   - Simpler architecture, easier to maintain

3. **✅ Implement dual-channel notifications (Inbox + Slack)**
   - Inbox as primary (full context, rich UI)
   - Slack as secondary (quick actions, mobile-friendly)
   - Allow response via either channel

4. **✅ Use ApprovalRequest CRD for state management**
   - Kubernetes-native, GitOps-friendly
   - Persistent, survives operator restarts
   - Easy for agents to poll and read

5. **✅ Start with Review pattern, add Notify/Question later**
   - Review pattern (PR approvals) has highest value
   - Notify and Question can be added incrementally

### 10.2 Implementation Priority

**High Priority** (MVP):
1. ApprovalRequest CRD
2. ApprovalRequestController (operator)
3. Inbox API endpoints
4. Inbox UI (list + detail views)
5. GitHub Remediation Agent integration

**Medium Priority** (Full Release):
6. Slack integration
7. Notification preferences
8. Timeout handling
9. RBAC enforcement

**Low Priority** (Enhancements):
10. Batch approvals
11. Email notifications
12. Analytics dashboard
13. Approval templates

### 10.3 Success Criteria

**MVP Success**:
- ✅ Monitoring agents can create approval requests
- ✅ Platform engineers can review and respond via inbox
- ✅ Agents resume execution after approval/rejection
- ✅ End-to-end workflow: detection → RCA → approval → PR

**Full Release Success**:
- ✅ Dual-channel notifications working (Inbox + Slack)
- ✅ Average approval response time < 2 hours
- ✅ 90%+ of approvals responded before timeout
- ✅ Zero approval request data loss (CRD persistence)
- ✅ Mobile-friendly Slack integration for on-call engineers

---

## Appendix

### A. Related Research

- [TODO_monitoring_agents.md](../TODO_monitoring_agents.md) - Monitoring agents system plan
- LangChain Agent Inbox: https://github.com/langchain-ai/agent-inbox
- LangChain Interrupt Blog: https://blog.langchain.com/making-it-easier-to-build-human-in-the-loop-agents-with-interrupt/
- HumanLayer SDK: https://www.humanlayer.dev/

### B. Glossary

- **HITL**: Human-in-the-Loop
- **ApprovalRequest**: Kubernetes CRD for agent approval requests
- **Inbox**: UI component in kagenti-ui for viewing and responding to approvals
- **Notify**: Approval pattern for informing humans (no action required)
- **Question**: Approval pattern for asking humans for input
- **Review**: Approval pattern for requesting approval before action
- **Dual-channel**: Supporting both inbox and Slack for notifications/responses

### C. Future Enhancements

- **Agent Learning**: Store approval history, learn from human feedback
- **Confidence-based Auto-approval**: Auto-approve high-confidence (>0.95) requests
- **Approval Templates**: Reusable templates for common approval types
- **Multi-approver Workflows**: Require N approvals from M approvers
- **Approval Delegation**: Delegate approvals to other users
- **Mobile App**: Native mobile app for approval management
- **Voice Interface**: Approve via voice command (Alexa, Google Assistant)
