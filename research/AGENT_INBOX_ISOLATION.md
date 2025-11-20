# Agent Inbox User Isolation & Multi-Tenancy

**Date**: 2025-11-19
**Related**: AGENT_INBOX_RESEARCH.md
**Focus**: User/team isolation strategy for agent inbox system

---

## Problem Statement

**Question**: How do we ensure proper user/team isolation for the agent inbox system?

**Key Concerns**:
1. Prevent User A from seeing User B's approval requests
2. Prevent Team 1 from responding to Team 2's approvals
3. Ensure agents can only be controlled by authorized users/teams
4. Handle both platform-wide agents and team-specific agents

---

## Table of Contents

1. [Use Cases Analysis](#1-use-cases-analysis)
2. [Isolation Strategies](#2-isolation-strategies)
3. [Recommended Architecture](#3-recommended-architecture)
4. [RBAC Configuration](#4-rbac-configuration)
5. [Inbox UI Filtering](#5-inbox-ui-filtering)
6. [Cross-Namespace Scenarios](#6-cross-namespace-scenarios)
7. [Security Considerations](#7-security-considerations)

---

## 1. Use Cases Analysis

### 1.1 Use Case 1: Platform Monitoring Agents

**Scenario**: Platform team operates monitoring agents (from TODO_monitoring_agents.md)

**Characteristics**:
- **Namespace**: `monitoring-agents` (single, shared namespace)
- **Operators**: Platform team members only
- **Agents**: Metrics monitor, trace analyzer, log analyzer, correlation RCA, GitHub remediation
- **Approvals**: PRs to `kagenti-demo-deployment`, infrastructure fixes
- **Access Pattern**: All platform team members see all approval requests

**Isolation Needs**:
- ⚠️ Low isolation required (trusted platform team)
- ✅ RBAC to prevent non-platform users from accessing
- ✅ Audit trail for compliance

**Current Architecture Fit**:
- ✅ All agents in `monitoring-agents` namespace
- ✅ ApprovalRequests in `monitoring-agents` namespace
- ✅ Platform team has RBAC access to namespace
- ✅ Keycloak SSO for authentication

### 1.2 Use Case 2: Team-Specific Agents

**Scenario**: Multiple teams deploy their own agents for their applications

**Characteristics**:
- **Namespace**: Per-team namespaces (`team1`, `team2`, `team-finance`, etc.)
- **Operators**: Team members only (isolated per team)
- **Agents**: Custom agents built by teams (e.g., team1's deployment agent, team2's data pipeline agent)
- **Approvals**: Team-specific actions (deploy to team1's namespace, modify team2's database)
- **Access Pattern**: Team members see only their team's approval requests

**Isolation Needs**:
- 🔴 **High isolation required** (different teams, different trust boundaries)
- ✅ Namespace-level isolation (hard boundary)
- ✅ RBAC to enforce permissions
- ✅ Prevent cross-team access

**Architecture Requirements**:
- ✅ Each team gets own namespace
- ✅ ApprovalRequests scoped to namespace
- ✅ Agents run with team-specific ServiceAccount
- ✅ Inbox UI filters by user's K8s permissions

### 1.3 Use Case 3: User-Specific Agents

**Scenario**: Individual users deploy personal agents (development, experimentation)

**Characteristics**:
- **Namespace**: Per-user namespaces (`user-alice`, `user-bob`) OR shared namespace with labels
- **Operators**: Individual user only
- **Agents**: Personal agents (research agent, code review agent, etc.)
- **Approvals**: User-specific actions (commit to user's branch, send user's email)
- **Access Pattern**: User sees only their own approval requests

**Isolation Needs**:
- 🔴 **Highest isolation required** (personal data, individual trust)
- ✅ Namespace-level isolation (preferred)
- ✅ OR label-based filtering (if shared namespace)
- ✅ RBAC enforcement
- ✅ Privacy guarantees

**Architecture Requirements**:
- ✅ Per-user namespace (recommended)
- ✅ OR shared namespace with owner labels + RBAC
- ✅ ApprovalRequests have owner field
- ✅ Inbox UI strict filtering by owner

---

## 2. Isolation Strategies

### 2.1 Strategy A: Namespace-Level Isolation (Recommended ✅)

**Principle**: Use Kubernetes namespaces as the primary isolation boundary

**How It Works**:
```
team1 namespace:
  - team1-agent-1
  - team1-agent-2
  - ApprovalRequest: team1-approval-1
  - ApprovalRequest: team1-approval-2

team2 namespace:
  - team2-agent-1
  - ApprovalRequest: team2-approval-1

monitoring-agents namespace:
  - metrics-monitor-agent
  - github-remediation-agent
  - ApprovalRequest: platform-approval-1
```

**Isolation Mechanism**:
- Agents in `team1` namespace can only create ApprovalRequests in `team1` namespace
- Team1 users have RBAC `get`, `list`, `update` permissions on ApprovalRequests in `team1` namespace ONLY
- Team2 users cannot see Team1's ApprovalRequests (namespace boundary)
- Platform team may have cross-namespace read access (optional)

**Pros**:
- ✅ **Hard isolation** (Kubernetes-native boundary)
- ✅ **Simple RBAC** (namespace-scoped roles)
- ✅ **Clear ownership** (namespace = team)
- ✅ **No label filtering needed** (namespace is the filter)
- ✅ **Audit trail** (namespace in all K8s events)

**Cons**:
- ❌ More namespaces to manage
- ❌ Quota management per namespace
- ❌ Harder to implement "shared" approvals (if needed)

**Implementation**:
```yaml
# Team1 RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team1-approval-access
  namespace: team1
subjects:
  - kind: Group
    name: team1-members
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: approval-manager
  apiGroup: rbac.authorization.k8s.io

---
# Role allowing approval management
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: approval-manager
  namespace: team1
rules:
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests/status"]
    verbs: ["update", "patch"]
```

### 2.2 Strategy B: Label-Based Filtering (Alternative)

**Principle**: Share namespace but use labels + RBAC for isolation

**How It Works**:
```
shared-agents namespace:
  - team1-agent-1
    labels: {team: team1, owner: alice@example.com}
  - team2-agent-1
    labels: {team: team2, owner: bob@example.com}
  - ApprovalRequest: approval-1
    labels: {team: team1, owner: alice@example.com}
  - ApprovalRequest: approval-2
    labels: {team: team2, owner: bob@example.com}
```

**Isolation Mechanism**:
- ApprovalRequests have `owner` and `team` labels
- Inbox API filters by user's identity (from Keycloak token)
- RBAC uses label selectors (if supported by K8s admission controllers)
- **Soft isolation** (relies on application-level filtering)

**Pros**:
- ✅ Fewer namespaces to manage
- ✅ Easier to implement "shared" approvals
- ✅ Flexible filtering (by owner, team, project, etc.)

**Cons**:
- ❌ **Soft isolation** (not Kubernetes-enforced, relies on app logic)
- ❌ **Security risk** (misconfigured API could leak data)
- ❌ **Complex RBAC** (need admission controllers for label-based RBAC)
- ❌ **Harder to audit** (labels can be changed)

**When to Use**:
- ⚠️ Only if namespace-level isolation is too restrictive
- ⚠️ Only for low-security use cases (e.g., user-specific agents within trusted org)

**Implementation**:
```python
# Inbox API filtering by labels
@app.route('/api/v1/inbox/approvals')
def list_approvals():
    # Get user identity from Keycloak token
    user_email = get_user_from_token(request.headers['Authorization'])
    user_teams = get_user_teams(user_email)

    # Fetch ApprovalRequests from K8s API
    all_approvals = k8s_client.list_namespaced_custom_object(
        group='kagenti.dev',
        version='v1alpha1',
        namespace='shared-agents',
        plural='approvalrequests'
    )

    # Filter by ownership (APPLICATION-LEVEL, not K8s-enforced!)
    filtered_approvals = [
        approval for approval in all_approvals['items']
        if approval['metadata']['labels'].get('owner') == user_email
        or approval['metadata']['labels'].get('team') in user_teams
    ]

    return jsonify(filtered_approvals)
```

⚠️ **Warning**: This is **not Kubernetes-enforced**. A user with direct K8s API access can bypass this filtering.

### 2.3 Strategy C: Hybrid Approach

**Principle**: Combine namespace isolation + label filtering

**How It Works**:
```
# High-security: Namespace per team
team1 namespace:
  - team1-agent-1
  - ApprovalRequest: approval-1
    labels: {approver: alice@example.com}

team2 namespace:
  - team2-agent-1
  - ApprovalRequest: approval-2
    labels: {approver: bob@example.com}

# Low-security: Shared namespace for platform agents
monitoring-agents namespace:
  - metrics-monitor-agent
  - ApprovalRequest: platform-approval-1
    labels: {team: platform, severity: high}
```

**Isolation Mechanism**:
- **Namespace-level** for team/user agents (hard isolation)
- **Label-based** within platform namespace (soft isolation, for filtering/sorting only)

**Pros**:
- ✅ **Best of both worlds**
- ✅ Hard isolation where needed (team/user agents)
- ✅ Flexible filtering within platform namespace
- ✅ Scalable architecture

**Cons**:
- ❌ Mixed isolation models (complexity)
- ❌ Need to document when to use which approach

---

## 3. Recommended Architecture

### 3.1 Proposed Model: Namespace-Level Isolation

**Decision**: Use **namespace-level isolation** as the primary mechanism ✅

**Rationale**:
1. **Security**: Hard isolation boundary (Kubernetes-enforced)
2. **Simplicity**: RBAC is straightforward (namespace-scoped)
3. **Auditability**: Clear ownership in K8s events
4. **Best Practice**: Aligns with Kubernetes multi-tenancy patterns

### 3.2 Namespace Design

**For Platform Monitoring Agents**:
- **Namespace**: `monitoring-agents`
- **Access**: Platform team only (via RBAC)
- **ApprovalRequests**: All in `monitoring-agents` namespace
- **Inbox View**: Platform team sees all approvals

**For Team-Specific Agents**:
- **Namespace**: Per-team (e.g., `team-finance`, `team-data`)
- **Access**: Team members only (via RBAC)
- **ApprovalRequests**: Scoped to team namespace
- **Inbox View**: Team members see only their team's approvals

**For User-Specific Agents**:
- **Namespace**: Per-user (e.g., `user-alice`, `user-bob`)
- **Access**: User only (via RBAC)
- **ApprovalRequests**: Scoped to user namespace
- **Inbox View**: User sees only their own approvals

### 3.3 Namespace Provisioning

**Option 1: Manual Namespace Creation**
```bash
# Platform team creates namespaces
kubectl create namespace team-finance
kubectl create namespace user-alice

# Apply RBAC
kubectl apply -f rbac/team-finance-rolebinding.yaml
kubectl apply -f rbac/user-alice-rolebinding.yaml
```

**Option 2: Automated Namespace Provisioning** (Recommended for scale)
```yaml
# Use a namespace provisioner operator or GitOps
apiVersion: v1
kind: Namespace
metadata:
  name: team-finance
  labels:
    team: finance
    managed-by: kagenti
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-finance-approval-access
  namespace: team-finance
subjects:
  - kind: Group
    name: finance-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kagenti-approval-manager
  apiGroup: rbac.authorization.k8s.io
```

### 3.4 Cross-Namespace Access (Optional)

**Use Case**: Platform admins need to see all approvals across all namespaces

**Solution**: ClusterRole with namespace-scoped access
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kagenti-platform-admin
rules:
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests/status"]
    verbs: ["update", "patch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins-approval-access
subjects:
  - kind: Group
    name: platform-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kagenti-platform-admin
  apiGroup: rbac.authorization.k8s.io
```

**Inbox UI Behavior**:
- Platform admins see dropdown: "All Namespaces" or "namespace selector"
- Regular users see only their accessible namespaces

---

## 4. RBAC Configuration

### 4.1 Roles

**ClusterRole: kagenti-approval-manager**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kagenti-approval-manager
rules:
  # Read approvals
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests"]
    verbs: ["get", "list", "watch"]

  # Respond to approvals (update status)
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests/status"]
    verbs: ["update", "patch"]

  # Read agents (optional, for context)
  - apiGroups: ["kagenti.dev"]
    resources: ["agents"]
    verbs: ["get", "list"]
```

**ClusterRole: kagenti-agent-operator**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kagenti-agent-operator
rules:
  # Create and manage approvals (for agents)
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests"]
    verbs: ["create", "get", "list", "watch", "delete"]

  # Read approval status (to check for responses)
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests/status"]
    verbs: ["get", "list", "watch"]
```

### 4.2 RoleBindings

**For Team Members** (namespace-scoped):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-finance-members-approval-access
  namespace: team-finance
subjects:
  # Bind to Keycloak group
  - kind: Group
    name: finance-team  # Synced from Keycloak
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kagenti-approval-manager
  apiGroup: rbac.authorization.k8s.io
```

**For Agents** (namespace-scoped):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-remediation-agent
  namespace: team-finance

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-remediation-agent-approval-creator
  namespace: team-finance
subjects:
  - kind: ServiceAccount
    name: github-remediation-agent
    namespace: team-finance
roleRef:
  kind: ClusterRole
  name: kagenti-agent-operator
  apiGroup: rbac.authorization.k8s.io
```

### 4.3 Keycloak Group Sync

**Integration**: Sync Keycloak groups to Kubernetes RBAC

**Tools**:
- **Keycloak OIDC**: Use OIDC token with group claims
- **Kubernetes OIDC Auth**: Configure K8s API server to trust Keycloak
- **Group Claim Mapping**: Map Keycloak groups to K8s groups

**Example Keycloak Group**:
```json
{
  "name": "finance-team",
  "members": ["alice@example.com", "bob@example.com"],
  "attributes": {
    "kubernetes_namespace": "team-finance",
    "kagenti_role": "approval-manager"
  }
}
```

**Kubernetes API Server Configuration**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
spec:
  containers:
    - name: kube-apiserver
      command:
        - kube-apiserver
        - --oidc-issuer-url=https://keycloak.localtest.me:9443/realms/master
        - --oidc-client-id=kubernetes
        - --oidc-username-claim=email
        - --oidc-groups-claim=groups  # Map Keycloak groups to K8s groups
```

**Result**: User logs in via Keycloak → Token contains groups → K8s RBAC checks groups → Access granted/denied

---

## 5. Inbox UI Filtering

### 5.1 Backend API Filtering

**Approach**: Inbox API respects K8s RBAC

**Implementation**:
```python
from kubernetes import client, config
from kubernetes.client.rest import ApiException

@app.route('/api/v1/inbox/approvals')
def list_approvals():
    # Get user's K8s token from Keycloak SSO
    k8s_token = get_k8s_token_from_keycloak(request.headers['Authorization'])

    # Create K8s client with user's token (impersonation)
    k8s_config = client.Configuration()
    k8s_config.api_key['authorization'] = f'Bearer {k8s_token}'
    k8s_api = client.CustomObjectsApi(client.ApiClient(k8s_config))

    # Get namespace filter (from query param or user's accessible namespaces)
    namespace = request.args.get('namespace', None)

    approvals = []

    if namespace:
        # List approvals in specific namespace
        try:
            result = k8s_api.list_namespaced_custom_object(
                group='kagenti.dev',
                version='v1alpha1',
                namespace=namespace,
                plural='approvalrequests'
            )
            approvals = result['items']
        except ApiException as e:
            if e.status == 403:
                return jsonify({'error': 'Access denied to namespace'}), 403
            raise

    else:
        # List approvals across all accessible namespaces
        # (This requires listing namespaces user has access to)
        accessible_namespaces = get_user_accessible_namespaces(k8s_api)

        for ns in accessible_namespaces:
            try:
                result = k8s_api.list_namespaced_custom_object(
                    group='kagenti.dev',
                    version='v1alpha1',
                    namespace=ns,
                    plural='approvalrequests'
                )
                approvals.extend(result['items'])
            except ApiException:
                # User may have lost access, skip namespace
                continue

    return jsonify(approvals)

def get_user_accessible_namespaces(k8s_api):
    """Get list of namespaces user can access (via RBAC check)"""
    v1 = client.CoreV1Api(k8s_api.api_client)

    try:
        # List all namespaces
        all_namespaces = v1.list_namespace()

        accessible = []
        for ns in all_namespaces.items:
            # Check if user can list approvalrequests in this namespace
            auth_v1 = client.AuthorizationV1Api(k8s_api.api_client)
            access_review = client.V1SelfSubjectAccessReview(
                spec=client.V1SelfSubjectAccessReviewSpec(
                    resource_attributes=client.V1ResourceAttributes(
                        namespace=ns.metadata.name,
                        verb='list',
                        group='kagenti.dev',
                        resource='approvalrequests'
                    )
                )
            )

            result = auth_v1.create_self_subject_access_review(access_review)
            if result.status.allowed:
                accessible.append(ns.metadata.name)

        return accessible

    except ApiException:
        # Fallback: return empty list
        return []
```

**Key Points**:
- ✅ **API uses user's K8s token** (from Keycloak SSO)
- ✅ **K8s RBAC enforced** (user sees only what K8s allows)
- ✅ **No application-level filtering** (relies on K8s)
- ✅ **Secure by default** (can't bypass RBAC)

### 5.2 Frontend UI Filtering

**Namespace Selector**:
```typescript
// React component for namespace filtering
function InboxPage() {
  const [namespaces, setNamespaces] = useState<string[]>([]);
  const [selectedNamespace, setSelectedNamespace] = useState<string | null>(null);
  const { approvals, loading } = useApprovals(selectedNamespace);

  useEffect(() => {
    // Fetch accessible namespaces from backend
    fetch('/api/v1/inbox/namespaces')
      .then(res => res.json())
      .then(data => setNamespaces(data.namespaces));
  }, []);

  return (
    <div className="inbox-page">
      <InboxHeader>
        <NamespaceSelector
          namespaces={namespaces}
          selected={selectedNamespace}
          onChange={setSelectedNamespace}
        />
      </InboxHeader>

      <ApprovalList approvals={approvals} loading={loading} />
    </div>
  );
}
```

**UI Behavior**:
- Regular users: See only their namespace(s)
- Platform admins: See "All Namespaces" option + namespace selector
- Empty state: "No approvals in this namespace"

---

## 6. Cross-Namespace Scenarios

### 6.1 Scenario: Platform Agent Creates Team-Specific Approval

**Problem**: Monitoring agent in `monitoring-agents` namespace detects issue in `team-finance` namespace. Should approval go to platform team or finance team?

**Solution**: Agent creates approval in the **affected team's namespace**

```python
# Monitoring agent code
def create_approval_for_team_issue(issue_data):
    affected_namespace = issue_data['affected_namespace']  # e.g., "team-finance"

    # Create ApprovalRequest in affected team's namespace (not monitoring-agents namespace)
    approval = {
        'apiVersion': 'kagenti.dev/v1alpha1',
        'kind': 'ApprovalRequest',
        'metadata': {
            'name': f"platform-detected-{issue_data['correlation_id']}",
            'namespace': affected_namespace,  # team-finance
            'labels': {
                'source-agent': 'monitoring-agents/metrics-monitor',
                'severity': 'high'
            }
        },
        'spec': {
            'agentName': 'metrics-monitor-agent',
            'agentNamespace': 'monitoring-agents',
            'title': f"Issue detected in {affected_namespace}",
            # ... rest of spec
        }
    }

    # Agent needs RBAC permission to create ApprovalRequests in other namespaces
    k8s_client.create_namespaced_custom_object(
        group='kagenti.dev',
        version='v1alpha1',
        namespace=affected_namespace,
        plural='approvalrequests',
        body=approval
    )
```

**RBAC for Cross-Namespace Creation**:
```yaml
# Allow monitoring agents to create approvals in any namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-agent-cross-namespace-approval
rules:
  - apiGroups: ["kagenti.dev"]
    resources: ["approvalrequests"]
    verbs: ["create"]
    # No namespace restriction = all namespaces

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-agents-approval-creator
subjects:
  - kind: ServiceAccount
    name: metrics-monitor-agent
    namespace: monitoring-agents
roleRef:
  kind: ClusterRole
  name: monitoring-agent-cross-namespace-approval
  apiGroup: rbac.authorization.k8s.io
```

### 6.2 Scenario: Shared Approval (Multiple Teams)

**Problem**: Infrastructure change affects multiple teams. All teams need to approve.

**Solution 1: Multi-Approver ApprovalRequest**
```yaml
apiVersion: kagenti.dev/v1alpha1
kind: ApprovalRequest
metadata:
  name: shared-infrastructure-change
  namespace: monitoring-agents  # Platform namespace
spec:
  title: "Database upgrade requires approval from all teams"

  # Multi-approver configuration
  approvers:
    - group: team-finance
      required: true
    - group: team-data
      required: true
    - group: platform-team
      required: true

  # Approval logic: require ALL approvers
  approvalPolicy: all  # Options: all, any, majority

status:
  responses:
    - group: team-finance
      decision: approved
      respondedBy: alice@example.com
      respondedAt: "2025-11-19T10:00:00Z"
    - group: team-data
      decision: pending
    - group: platform-team
      decision: approved
      respondedBy: charlie@example.com
      respondedAt: "2025-11-19T10:05:00Z"

  phase: Pending  # Still pending until team-data approves
```

**RBAC**: Each team has read access to `monitoring-agents` namespace for this specific approval

**Solution 2: Create Separate Approvals Per Team**
```python
# Agent creates one approval per affected team
for team in affected_teams:
    create_approval_request(
        namespace=f"team-{team}",
        title=f"[{team}] Database upgrade approval needed",
        # ... rest of spec
    )

# Agent waits for ALL approvals
all_approved = wait_for_all_approvals(approval_ids)
```

---

## 7. Security Considerations

### 7.1 Agent Isolation

**Problem**: Agent in `team1` namespace shouldn't control agents in `team2` namespace

**Solution**: ServiceAccount scoping
```yaml
# team1's agent uses team1's ServiceAccount
apiVersion: apps/v1
kind: Deployment
metadata:
  name: team1-agent
  namespace: team1
spec:
  template:
    spec:
      serviceAccountName: team1-agent-sa  # Scoped to team1 namespace
      containers:
        - name: agent
          image: team1-agent:v1.0.0
```

**RBAC**: `team1-agent-sa` can only create ApprovalRequests in `team1` namespace

### 7.2 Approval Response Authentication

**Problem**: How do we verify the human responding is authorized?

**Solution**: Keycloak SSO + K8s RBAC
1. User logs into kagenti-ui via Keycloak
2. kagenti-ui gets Keycloak token
3. Backend API exchanges Keycloak token for K8s token (via OIDC)
4. Backend API calls K8s API with user's K8s token
5. K8s RBAC checks if user has `update` permission on ApprovalRequest
6. If authorized, update succeeds; otherwise, 403 Forbidden

**Audit Trail**:
```yaml
status:
  response:
    decision: approved
    respondedBy: alice@example.com  # From Keycloak token
    respondedByUid: "keycloak-uid-12345"  # From Keycloak token
    respondedAt: "2025-11-19T10:00:00Z"
    respondedFrom: "kagenti-ui"  # or "slack"
    sourceIP: "10.0.1.15"  # From K8s audit log
```

### 7.3 Slack Response Verification

**Problem**: Slack user clicks "Approve" - how do we verify they're authorized?

**Solution**: Slack user → Keycloak user mapping
```python
@app.route('/api/v1/slack/interactions', methods=['POST'])
def handle_slack_interaction():
    payload = json.loads(request.form['payload'])
    slack_user_id = payload['user']['id']

    # Map Slack user ID to Keycloak user
    keycloak_user = get_keycloak_user_by_slack_id(slack_user_id)

    if not keycloak_user:
        return jsonify({'error': 'Slack user not linked to Keycloak account'}), 403

    # Get K8s token for this user
    k8s_token = get_k8s_token_for_user(keycloak_user['email'])

    # Update ApprovalRequest using user's K8s token (RBAC check happens here)
    try:
        update_approval_request(
            approval_id=approval_id,
            decision='approved',
            responded_by=keycloak_user['email'],
            k8s_token=k8s_token
        )
    except ApiException as e:
        if e.status == 403:
            slack_client.chat_postEphemeral(
                channel=payload['channel']['id'],
                user=slack_user_id,
                text="❌ You don't have permission to approve this request."
            )
            return jsonify({'error': 'Forbidden'}), 403
        raise

    return jsonify({'ok': True})
```

**User Linking**: Keycloak profile includes `slack_user_id` attribute

### 7.4 Preventing Privilege Escalation

**Problem**: Can an agent create an approval that grants itself more permissions?

**Answer**: No, because:
1. **Agents can't modify RBAC** - Only cluster admins can modify Roles/RoleBindings
2. **ApprovalRequests are data** - They don't grant K8s permissions directly
3. **Approval response requires human** - Human must have RBAC permission to respond

**Example Attack Attempt**:
```yaml
# Malicious agent tries to create approval to modify RBAC
apiVersion: kagenti.dev/v1alpha1
kind: ApprovalRequest
spec:
  title: "Approve RBAC change"
  proposedAction:
    type: "kubectl_apply"
    manifest: |
      apiVersion: rbac.authorization.k8s.io/v1
      kind: RoleBinding
      metadata:
        name: malicious-binding
      ...
```

**Defense**:
1. Agent can create ApprovalRequest (allowed)
2. Human reviews and rejects (suspicious request)
3. Even if approved, **agent has no RBAC permission to apply RBAC manifests**
4. Agent would need `create/update` on `rolebindings` resource (not granted)

---

## Summary & Recommendations

### Recommended Isolation Strategy

**✅ Use Namespace-Level Isolation**:
- Each team/user gets their own namespace
- ApprovalRequests are namespace-scoped
- K8s RBAC enforces access control
- Inbox UI respects K8s RBAC (uses user's token)

**Architecture**:
```
Namespaces:
  - monitoring-agents (platform team)
  - team-finance (finance team)
  - team-data (data team)
  - user-alice (individual user)

RBAC:
  - Platform team: ClusterRole (all namespaces)
  - Team members: RoleBinding (team namespace only)
  - Users: RoleBinding (user namespace only)

Agents:
  - Run with namespace-scoped ServiceAccount
  - Can create ApprovalRequests in own namespace
  - Platform agents can create in any namespace (if needed)

Inbox UI:
  - Uses user's K8s token (from Keycloak SSO)
  - Lists approvals across accessible namespaces
  - Namespace selector for multi-namespace users
```

### Security Checklist

- ✅ Namespace-level isolation enforced
- ✅ K8s RBAC for approval access
- ✅ Keycloak SSO for user authentication
- ✅ K8s token verification for all API calls
- ✅ Slack user → Keycloak user mapping
- ✅ Audit trail for all approval responses
- ✅ ServiceAccount scoping for agents
- ✅ No application-level filtering (rely on K8s RBAC)

### Implementation Priority

1. **Phase 1**: Single namespace (`monitoring-agents`) with platform team RBAC
2. **Phase 2**: Per-team namespaces with team RBAC
3. **Phase 3**: Cross-namespace approval creation (platform agents → team namespaces)
4. **Phase 4**: Multi-approver support (shared approvals)

**Start simple, add multi-tenancy incrementally as needed** ✅
