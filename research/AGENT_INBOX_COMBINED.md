# Agent Inbox: Combined Approach

**Date**: 2025-11-19
**Focus**: How to combine GitHub, Slack, and Custom Inbox for complete solution

---

## Executive Summary

**Best approach**: Start with **GitHub Issues + Slack** (MVP), migrate to **Custom Kagenti Inbox** as scale increases.

**Why this works**:
- ✅ **Low initial cost** - GitHub + Slack already exist, no dev needed
- ✅ **Fast to implement** - Working solution in 1-2 days
- ✅ **Migration path** - Can add custom inbox later without breaking existing workflows
- ✅ **User choice** - Users pick their preferred channel (GitHub, Slack, or Inbox)

---

## Solution Comparison Matrix

| Feature | GitHub Issues | Slack Interactive | Custom Kagenti Inbox | Hybrid (All 3) |
|---------|--------------|-------------------|---------------------|----------------|
| **Dev Time** | 1-2 days | 3-5 days | 6-16 weeks | 8-20 weeks (incremental) |
| **Notifications** | ✅ Email, Slack, Mobile | ✅ Real-time, Mobile | ⚠️ Need to build | ✅ All channels |
| **RBAC** | ✅ GitHub permissions | ⚠️ Channel-based | ✅ K8s RBAC | ✅ Multi-layer RBAC |
| **Persistence** | ✅ Issues stored forever | ❌ Messages scroll away | ✅ Database/K8s | ✅ Multiple sources |
| **Rich Context** | ⚠️ Markdown only | ❌ Limited formatting | ✅ Full UI/UX | ✅ Full UI/UX |
| **Batch Approvals** | ❌ One at a time | ❌ One at a time | ✅ Bulk operations | ✅ Bulk operations |
| **Search** | ✅ GitHub search | ⚠️ Slack search limited | ✅ Full-text search | ✅ Cross-source search |
| **Mobile** | ✅ GitHub app | ✅ Slack app | ⚠️ Need mobile app | ✅ Multiple apps |
| **Audit Trail** | ✅ Issue history | ⚠️ Limited retention | ✅ Full audit | ✅ Comprehensive |
| **User Isolation** | ✅ Repo permissions | ⚠️ Channel membership | ✅ Namespace + RBAC | ✅ Multi-layer isolation |

**Verdict**: **Hybrid approach wins** for production, **GitHub-only** for MVP.

---

## Hybrid Architecture: GitHub + Slack + Custom Inbox

### How All Three Work Together

```
Agent creates approval request
    ↓
┌─────────────────────────────────────────────────────┐
│  Approval Coordinator (kagent i-operator)            │
│  - Creates ApprovalRequest CRD (K8s)                │
│  - Publishes to all channels simultaneously         │
└─────────────────────────────────────────────────────┘
    ↓           ↓                    ↓
    ↓           ↓                    ↓
┌───────┐  ┌────────┐      ┌─────────────────┐
│GitHub │  │ Slack  │      │ Kagenti Inbox   │
│Issue  │  │Message │      │ (kagenti-ui)    │
└───┬───┘  └───┬────┘      └────────┬────────┘
    │          │                     │
    │          │                     │
    └──────────┴─────────────────────┘
                    ↓
         Human responds via ANY channel
                    ↓
    ┌───────────────────────────────────┐
    │  Response Sync Service            │
    │  - Collects responses from all    │
    │    channels                       │
    │  - Updates ApprovalRequest CRD    │
    │  - Closes other channels          │
    └───────────────────────────────────┘
                    ↓
              Agent resumes
```

### ApprovalRequest CRD (Central State)

**Single source of truth**: Kubernetes ApprovalRequest CR

```yaml
apiVersion: kagenti.dev/v1alpha1
kind: ApprovalRequest
metadata:
  name: github-pr-12345
  namespace: monitoring-agents
spec:
  # Core approval data
  agentName: github-remediation-agent
  title: "Review PR: Fix database connection pool"
  description: "..."
  proposedAction: {...}

  # Multi-channel configuration
  channels:
    github:
      enabled: true
      repo: "redhat-et/kagenti-demo-deployment"
      issueNumber: null  # Filled after creation
    slack:
      enabled: true
      channel: "#platform-alerts"
      messageTs: null  # Filled after sending
    inbox:
      enabled: true
      # No additional config needed (always available in kagenti-ui)

status:
  phase: Pending

  # Responses from all channels (first wins)
  response:
    decision: approved
    respondedBy: "alice@example.com"
    respondedVia: github  # or slack, inbox
    respondedAt: "2025-11-19T10:45:00Z"
    githubComment: "https://github.com/.../issues/123#issuecomment-456"
    slackThread: "1637000000.123456"

  # Channel tracking
  channelStatus:
    github:
      issueNumber: 123
      status: closed
      url: "https://github.com/.../issues/123"
    slack:
      messageTs: "1637000000.123456"
      status: updated
      url: "https://yourworkspace.slack.com/archives/..."
    inbox:
      status: closed
      url: "https://kagenti.localtest.me:9443/inbox/github-pr-12345"
```

### Coordinator Service (in kagenti-operator)

```python
class ApprovalCoordinator:
    """Manages multi-channel approval requests"""

    @kopf.on.create('kagenti.dev', 'v1alpha1', 'approvalrequests')
    def approval_created(spec, meta, **kwargs):
        """Publish to all enabled channels"""

        # 1. Create GitHub issue (if enabled)
        if spec['channels']['github']['enabled']:
            issue_number = github_publisher.create_issue(spec, meta)
            patch_status(meta['name'], meta['namespace'], {
                'channelStatus': {
                    'github': {
                        'issueNumber': issue_number,
                        'status': 'open',
                        'url': f"https://github.com/{spec['channels']['github']['repo']}/issues/{issue_number}"
                    }
                }
            })

        # 2. Send Slack message (if enabled)
        if spec['channels']['slack']['enabled']:
            message_ts = slack_publisher.send_message(spec, meta)
            patch_status(meta['name'], meta['namespace'], {
                'channelStatus': {
                    'slack': {
                        'messageTs': message_ts,
                        'status': 'sent',
                        'url': slack_publisher.get_message_url(spec['channels']['slack']['channel'], message_ts)
                    }
                }
            })

        # 3. Inbox automatically available (no action needed)
        patch_status(meta['name'], meta['namespace'], {
            'channelStatus': {
                'inbox': {
                    'status': 'available',
                    'url': f"https://kagenti.localtest.me:9443/inbox/{meta['name']}"
                }
            }
        })

    @kopf.timer('kagenti.dev', 'v1alpha1', 'approvalrequests', interval=30)
    def poll_github_responses(spec, status, meta, **kwargs):
        """Poll GitHub for responses"""

        if status.get('phase') != 'Pending':
            return  # Already responded

        if not spec['channels']['github']['enabled']:
            return

        issue_number = status['channelStatus']['github']['issueNumber']
        repo = spec['channels']['github']['repo']

        # Check for new comments
        comments = github_client.get_issue_comments(repo, issue_number)

        for comment in reversed(comments):
            # Check if this is a response we haven't seen
            if comment['created_at'] > meta['creationTimestamp']:
                decision = parse_github_response(comment['body'])

                if decision:
                    # Update ApprovalRequest with response
                    update_approval_response(
                        meta['name'],
                        meta['namespace'],
                        decision=decision['action'],
                        respondedBy=comment['user']['email'],
                        respondedVia='github',
                        githubComment=comment['html_url']
                    )

                    # Close other channels
                    close_slack_message(status['channelStatus']['slack'])
                    # Inbox will show "Approved via GitHub"

                    return

def parse_github_response(comment_body):
    """Parse GitHub comment for approval decision"""
    body = comment_body.lower()

    if '@agent approve' in body:
        return {'action': 'approved'}
    elif '@agent reject' in body:
        reason = body.split('@agent reject')[1].strip()
        return {'action': 'rejected', 'reason': reason}
    elif '@agent defer' in body:
        return {'action': 'deferred'}

    return None
```

### Response Sync Logic

**Key principle**: **First response wins**, other channels get closed/updated

```python
def update_approval_response(name, namespace, decision, respondedBy, respondedVia, **kwargs):
    """Update ApprovalRequest with human response"""

    approval = k8s_client.get_namespaced_custom_object(
        group='kagenti.dev',
        version='v1alpha1',
        namespace=namespace,
        plural='approvalrequests',
        name=name
    )

    # Check if already responded
    if approval['status'].get('phase') != 'Pending':
        logger.warning(f"Approval {name} already responded via {approval['status']['response']['respondedVia']}")
        return

    # Update with response
    patch_status(name, namespace, {
        'phase': 'Approved' if decision == 'approved' else 'Rejected',
        'response': {
            'decision': decision,
            'respondedBy': respondedBy,
            'respondedVia': respondedVia,
            'respondedAt': datetime.utcnow().isoformat() + 'Z',
            **kwargs  # githubComment, slackThread, etc.
        }
    })

    # Close/update other channels
    close_other_channels(approval, respondedVia)

def close_other_channels(approval, winning_channel):
    """Close or update other channels after response"""

    # Close GitHub issue
    if winning_channel != 'github' and approval['spec']['channels']['github']['enabled']:
        issue_number = approval['status']['channelStatus']['github']['issueNumber']
        github_client.create_issue_comment(
            repo=approval['spec']['channels']['github']['repo'],
            issue_number=issue_number,
            body=f"✅ This approval was responded to via **{winning_channel}** by {approval['status']['response']['respondedBy']}. Closing this issue."
        )
        github_client.update_issue(
            repo=approval['spec']['channels']['github']['repo'],
            issue_number=issue_number,
            state='closed',
            labels=['responded-via-' + winning_channel]
        )

    # Update Slack message
    if winning_channel != 'slack' and approval['spec']['channels']['slack']['enabled']:
        message_ts = approval['status']['channelStatus']['slack']['messageTs']
        slack_client.chat_update(
            channel=approval['spec']['channels']['slack']['channel'],
            ts=message_ts,
            text=f"✅ Responded via {winning_channel}",
            blocks=[{
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"✅ *{approval['status']['response']['decision'].capitalize()}* by {approval['status']['response']['respondedBy']} via **{winning_channel}**"
                }
            }]
        )

    # Inbox automatically shows response (reads from ApprovalRequest CR)
```

---

## Implementation Phases

### Phase 1: GitHub-Only (Week 1)

**Scope**: MVP with GitHub Issues only

```python
# Agent code (minimal)
class GitHubRemediationAgent:
    def create_pr_with_approval(self, pr_data):
        # Create GitHub issue
        issue_number = github_client.create_issue(
            repo="redhat-et/kagenti-demo-deployment",
            title=f"[APPROVAL] {pr_data['title']}",
            body=self.generate_approval_template(pr_data),
            labels=["approval-request"],
            assignees=["platform-admin"]
        )

        # Poll for response
        response = self.wait_for_github_response(issue_number, timeout_hours=24)

        if response['decision'] == 'approved':
            # Create PR
            self.create_github_pr(pr_data)

        return response
```

**Benefits**:
- ✅ Working HITL in 1 day
- ✅ Zero infrastructure changes
- ✅ Notifications already work (GitHub emails)

### Phase 2: Add Slack (Week 2-3)

**Scope**: Slack notifications + quick actions

```python
class ApprovalCoordinator:
    def publish_approval(self, pr_data):
        # 1. Create GitHub issue (primary)
        issue_number = self.create_github_issue(pr_data)

        # 2. Send Slack notification (secondary)
        self.send_slack_notification(pr_data, issue_number)

        # 3. Poll both channels
        return self.wait_for_response_any_channel(issue_number, slack_ts)
```

**Benefits**:
- ✅ Faster approvals (Slack mobile notifications)
- ✅ Still have GitHub audit trail
- ✅ User can choose channel

### Phase 3: Add ApprovalRequest CRD (Week 4-6)

**Scope**: Kubernetes-native approval tracking

```python
# Agent creates ApprovalRequest CR instead of GitHub issue directly
def create_approval_request(self, pr_data):
    approval_cr = {
        'apiVersion': 'kagenti.dev/v1alpha1',
        'kind': 'ApprovalRequest',
        'metadata': {'name': f"pr-{pr_data['correlation_id']}"},
        'spec': {
            'agentName': 'github-remediation-agent',
            'proposedAction': pr_data,
            'channels': {
                'github': {'enabled': True},
                'slack': {'enabled': True},
                'inbox': {'enabled': False}  # Not built yet
            }
        }
    }

    k8s_client.create_namespaced_custom_object(..., body=approval_cr)

    # Operator handles GitHub + Slack publishing
    # Agent polls ApprovalRequest CR status
    return self.wait_for_approval_cr_response(approval_cr['metadata']['name'])
```

**Benefits**:
- ✅ Centralized state (K8s CRD)
- ✅ Multi-channel sync handled by operator
- ✅ Better audit trail (K8s events)
- ✅ Foundation for custom inbox

### Phase 4: Add Custom Kagenti Inbox (Week 7-16)

**Scope**: Rich UI in kagenti-ui

```typescript
// kagenti-ui: Inbox page
function InboxPage() {
  const { approvals } = useApprovals();  // Fetches ApprovalRequests from K8s API

  return (
    <div className="inbox">
      {approvals.map(approval => (
        <ApprovalCard
          key={approval.metadata.name}
          approval={approval}
          onApprove={() => updateApprovalRequest(approval.metadata.name, 'approved')}
          onReject={() => updateApprovalRequest(approval.metadata.name, 'rejected')}
        />
      ))}
    </div>
  );
}
```

**Benefits**:
- ✅ Rich UI (embedded charts, traces, logs)
- ✅ Batch approvals
- ✅ Advanced filtering/search
- ✅ Still have GitHub + Slack fallback

---

## User Experience Comparison

### Scenario: Platform engineer receives approval request

**Via GitHub**:
1. Email notification: "New issue assigned to you"
2. Click email link → GitHub issue page
3. Read context, evidence, RCA
4. Comment `@agent approve` on issue
5. Agent sees comment, creates PR

**Via Slack**:
1. Mobile push notification: "🔔 Approval needed"
2. Open Slack app → See interactive message
3. Tap "Approve" button
4. Slack message updates: "✅ Approved"
5. GitHub issue auto-closes

**Via Kagenti Inbox**:
1. Badge in kagenti-ui navbar: "(1 pending)"
2. Click inbox tab → See rich approval card
3. Expand evidence → View trace graph, metric charts inline
4. Click "Approve" button
5. GitHub issue auto-closes, Slack message updates

---

## Recommendation: Phased Hybrid Approach

**Week 1**: GitHub Issues only (MVP)
- Agent creates issues, polls for `@agent approve` comments
- Platform team uses familiar GitHub interface

**Week 2-3**: Add Slack integration
- Operator sends Slack notifications for each GitHub issue
- Slack button clicks → Comment on GitHub issue
- Faster mobile approvals

**Week 4-6**: Add ApprovalRequest CRD
- Centralize state in Kubernetes
- Operator coordinates GitHub + Slack
- Agents poll CRD instead of GitHub directly

**Week 7-16**: Add Custom Inbox UI
- Build rich UI in kagenti-ui
- Embedded visualizations, batch approvals
- GitHub + Slack still work (user choice)

**Result**: Complete solution with migration path, no breaking changes.

---

## Final Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Agent                          │
│  (github-remediation-agent, correlation-rca-agent, etc.)    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓ creates
         ┌───────────────────────────────┐
         │   ApprovalRequest CRD (K8s)   │  ← Single source of truth
         └───────────────┬───────────────┘
                         │
          ┌──────────────┼──────────────┐
          ↓ watched by   ↓              ↓
┌─────────────────┐ ┌────────────┐ ┌───────────────┐
│ kagenti-operator│ │GitHub      │ │  Slack Bot    │
│ (Coordinator)   │ │Publisher   │ │  Publisher    │
└────────┬────────┘ └─────┬──────┘ └───────┬───────┘
         │                │                 │
         │ publishes to:  │                 │
         └────────────────┼─────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ↓                 ↓                  ↓
   ┌────────┐      ┌──────────┐      ┌──────────────┐
   │ GitHub │      │  Slack   │      │ Kagenti Inbox│
   │ Issues │      │ Messages │      │ (kagenti-ui) │
   └────┬───┘      └─────┬────┘      └──────┬───────┘
        │                │                   │
        │ Human responds via any channel    │
        └────────────────┼───────────────────┘
                         ↓
              ┌──────────────────────┐
              │ Response Sync Service│
              │ (first response wins)│
              └──────────┬───────────┘
                         ↓ updates
         ┌───────────────────────────────┐
         │   ApprovalRequest CRD Status  │
         │   phase: Approved             │
         │   respondedVia: slack         │
         └───────────────┬───────────────┘
                         ↓ agent polls
         ┌───────────────────────────────┐
         │    Agent Resumes Execution    │
         │   (creates PR, deploys, etc.) │
         └───────────────────────────────┘
```

**Key points**:
- ✅ ApprovalRequest CRD = single source of truth
- ✅ Multiple channels published simultaneously
- ✅ First response wins, others auto-close
- ✅ Agent only polls CRD (simpler code)
- ✅ Users pick their preferred channel

---

## Cost-Benefit Analysis

| Approach | Dev Cost | Infra Cost | Maintenance | User Experience |
|----------|----------|------------|-------------|-----------------|
| **GitHub Only** | 1 day | $0 | Low | Good (familiar) |
| **GitHub + Slack** | 3 days | $0 | Low | Better (mobile) |
| **GitHub + Slack + CRD** | 2 weeks | Low (K8s) | Medium | Better (centralized) |
| **All + Custom Inbox** | 3-4 months | Medium | High | Best (rich UI) |

**Recommendation**: **Start with GitHub + Slack (3 days of dev)**, evaluate after 1 month, add custom inbox if needed.
