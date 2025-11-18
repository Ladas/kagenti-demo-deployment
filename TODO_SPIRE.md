# TODO: SPIRE Integration for Kagenti Demo Deployment

**Date Created:** 2025-11-13
**Status:** Research Complete - Implementation Pending
**Priority:** HIGH
**Target:** Next PR after green redeploy

## Executive Summary

This document outlines the plan to fully integrate SPIRE (SPIFFE Runtime Environment) with the Kagenti platform to achieve unified identity management for both human and machine identities. The integration combines:

1. **SPIRE** - Machine/workload identity (SPIFFE IDs)
2. **Keycloak** - Human identity + OAuth2/OIDC access management
3. **Istio Ambient Mesh** - Service mesh with mTLS

**Current State:** SPIRE is deployed but not integrated with Keycloak. Agent workloads cannot use SPIRE-issued JWT SVIDs for Keycloak authentication.

**Goal:** Enable agents to authenticate to Keycloak using SPIRE JWT SVIDs and implement token exchange flows for multi-tier architectures.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Integration Architecture](#integration-architecture)
3. [Implementation Tasks](#implementation-tasks)
4. [Configuration Details](#configuration-details)
5. [Testing Plan](#testing-plan)
6. [References](#references)

---

## Current State Analysis

### What We Have

#### 1. SPIRE Deployment (Currently Deployed)

**Location:** `argocd/applications/helm/spire.yaml`

**Components:**
- SPIRE Server (spire-system namespace)
- SPIRE Agent (DaemonSet on each node)
- Controller Manager (ClusterSPIFFEID automation)
- Tornjak (Management UI)
- SPIFFE OIDC Discovery Provider

**Configuration:**
```yaml
# argocd/applications/helm/spire.yaml
trustDomain: kagenti.dev
clusterName: kagenti-demo
namespace: spire-system
```

**Health Checks:** ✅ Already configured in `argocd/config/argocd-cm-spire-health.yaml`

#### 2. Keycloak Deployment (Currently Deployed)

**Location:** `components/00-infrastructure/keycloak/`

**Current Version:** `quay.io/keycloak/keycloak:26.4.1`

**Current Configuration:**
```yaml
# keycloak-statefulset.yaml:87-102
args:
  - "--verbose"
  - "start"
  - "--hostname=https://keycloak.localtest.me:9443"
  - "--hostname-admin=https://keycloak.localtest.me:9443"
  - "--hostname-strict=false"
  - "--proxy-headers=xforwarded"
```

**MISSING:** SPIFFE preview features NOT enabled

#### 3. HTTPRoutes (Already Configured)

**SPIRE Services Exposed:**
- `https://spire-tornjak.localtest.me:9443` - Tornjak UI
- `https://spire-tornjak-api.localtest.me:9443` - Tornjak API
- `https://spiffe-oidc.localtest.me:9443` - OIDC Discovery

**Location:** `components/01-platform/spire/`

### What We Need

#### 1. Enable Keycloak SPIFFE Features

**Required:** Keycloak 26.4+ with preview features enabled

**Status:** ⚠️ We have 26.4.1 but features NOT enabled

#### 2. Configure SPIRE OIDC as Keycloak Identity Provider

**Required:** Register SPIRE OIDC endpoint in Keycloak

**Status:** ❌ Not configured

#### 3. Update Agent Deployments

**Required:** Agents need SPIRE agent socket access and OAuth2 configuration

**Status:** ❌ Not configured

---

## Integration Architecture

### Token Flow Architecture

```
┌─────────────┐          ┌──────────┐          ┌──────────┐
│   Workload  │─SPIFFE──▶│  SPIRE   │─JWT SVID─▶│ Keycloak │
│   (Agent)   │  Socket  │  Agent   │           │          │
└─────────────┘          └──────────┘          └──────────┘
       │                                              │
       │            OAuth2 Access Token              │
       └──────────────────────────────────────────────┘
```

### Multi-Tier Token Exchange

```
 ┌─────────┐      ┌────────────┐      ┌────────┐
 │  User   │──1──▶│  API Tier  │──2──▶│ Agent  │──3──▶│ Tool │
 └─────────┘      │ (Frontend) │      │  Tier  │      │ Tier │
                  └────────────┘      └────────┘      └──────┘

1. User logs in → API gets access token (aud: Agent)
2. API calls Agent → Agent receives token
3. Agent exchanges token for new token (aud: Tool)
```

### Key Components

1. **SPIRE Agent Socket:** `/run/spire/sockets/agent.sock`
2. **SPIFFE OIDC Discovery:** `http://spire-oidc-discovery.spire-system.svc:8080`
3. **Keycloak Realm:** `kubernetes` (existing)
4. **Trust Domain:** `kagenti.dev`

---

## Implementation Tasks

### Phase 1: Enable Keycloak SPIFFE Features (CRITICAL)

**Priority:** P0 - Blocker for all other tasks

**Estimated Effort:** 1 hour

**Files to Modify:**
- `components/00-infrastructure/keycloak/keycloak-statefulset.yaml`

**Changes Required:**

```yaml
# Add to args section (line 87)
args:
  - "-Djgroups.dns.query=keycloak-discovery.keycloak"
  - "--verbose"
  - "start"
  - "--hostname=https://keycloak.localtest.me:9443"
  - "--hostname-admin=https://keycloak.localtest.me:9443"
  - "--hostname-strict=false"
  - "--proxy-headers=xforwarded"
  # NEW: Enable SPIFFE preview features
  - "--features=client-auth-federated:v1"
  - "--features=spiffe:v1"
  - "--features=kubernetes-service-accounts:v1"
```

**Testing:**
```bash
# Verify Keycloak starts with new features
kubectl logs -n keycloak keycloak-0 | grep -i spiffe
kubectl logs -n keycloak keycloak-0 | grep -i "client-auth-federated"
```

**Documentation:** Update `docs/ENCRYPTION_ARCHITECTURE.md` section on Keycloak

---

### Phase 2: Configure SPIRE OIDC as Keycloak Identity Provider

**Priority:** P0

**Estimated Effort:** 4-6 hours

**Approach:** Create Kubernetes Job to configure Keycloak via Admin API

**Files to Create:**
- `components/00-infrastructure/keycloak/spiffe-idp-setup-job.yaml`

**Job Responsibilities:**

1. Wait for Keycloak to be ready
2. Get admin token
3. Create SPIFFE Identity Provider in `kubernetes` realm
4. Configure OIDC discovery URL
5. Set up JWKS endpoint

**Job Template:**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: spiffe-idp-setup
  namespace: keycloak
  annotations:
    argocd.argoproj.io/sync-wave: "15"  # After Keycloak, before agents
spec:
  template:
    spec:
      serviceAccountName: keycloak-admin
      containers:
      - name: setup
        image: bitnami/kubectl:latest
        env:
        - name: KEYCLOAK_URL
          value: "http://keycloak.keycloak.svc:8080"
        - name: KEYCLOAK_ADMIN_USER
          valueFrom:
            secretKeyRef:
              name: keycloak-initial-admin
              key: username
        - name: KEYCLOAK_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-initial-admin
              key: password
        - name: SPIRE_OIDC_URL
          value: "http://spire-oidc-discovery.spire-system.svc:8080"
        command: ["/bin/bash"]
        args:
        - -c
        - |
          #!/bin/bash
          set -e

          echo "=== Configuring SPIFFE Identity Provider in Keycloak ==="

          # Wait for Keycloak
          until curl -f ${KEYCLOAK_URL}/health/ready; do
            echo "Waiting for Keycloak..."
            sleep 5
          done

          # Get admin token
          TOKEN=$(curl -sX POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=${KEYCLOAK_ADMIN_USER}" \
            -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
            -d "grant_type=password" \
            -d "client_id=admin-cli" | jq -r '.access_token')

          # Create SPIFFE Identity Provider
          curl -sX POST "${KEYCLOAK_URL}/admin/realms/kubernetes/identity-provider/instances" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
              "alias": "spiffe",
              "displayName": "SPIFFE/SPIRE",
              "providerId": "oidc",
              "enabled": true,
              "config": {
                "issuer": "'${SPIRE_OIDC_URL}'",
                "authorizationUrl": "'${SPIRE_OIDC_URL}'/authorize",
                "tokenUrl": "'${SPIRE_OIDC_URL}'/token",
                "jwksUrl": "'${SPIRE_OIDC_URL}'/.well-known/jwks.json",
                "clientAuthMethod": "client_secret_post",
                "syncMode": "IMPORT",
                "useJwksUrl": "true"
              }
            }'

          echo "✓ SPIFFE identity provider configured successfully"
      restartPolicy: OnFailure
```

**RBAC Required:**

Create `components/00-infrastructure/keycloak/spiffe-idp-rbac.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keycloak-admin
  namespace: keycloak
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: keycloak-admin
  namespace: keycloak
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["keycloak-initial-admin"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: keycloak-admin
  namespace: keycloak
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: keycloak-admin
subjects:
- kind: ServiceAccount
  name: keycloak-admin
  namespace: keycloak
```

**Kustomization Update:**

```yaml
# components/00-infrastructure/keycloak/kustomization.yaml
resources:
  # ... existing resources ...
  - spiffe-idp-rbac.yaml
  - spiffe-idp-setup-job.yaml
```

---

### Phase 3: Configure Agent OAuth Clients

**Priority:** P1

**Estimated Effort:** 6-8 hours

**Approach:** Extend existing `oauth-secrets-extractor-job.yaml`

**Requirements:**

For each agent (research, code, orchestrator):
1. Create Keycloak client with SPIFFE ID as client_id
2. Configure "Signed JWT - Federated" authentication
3. Reference SPIFFE identity provider
4. Set up client scopes for token exchange
5. Create secrets with OAuth configuration

**Example SPIFFE IDs:**

```
spiffe://kagenti.dev/ns/team1/sa/research-agent-sa
spiffe://kagenti.dev/ns/team1/sa/code-agent-sa
spiffe://kagenti.dev/ns/team1/sa/orchestrator-agent-sa
```

**Client Configuration (via Keycloak Admin API):**

```bash
# For research-agent
SPIFFE_ID="spiffe://kagenti.dev/ns/team1/sa/research-agent-sa"

curl -X POST "${KEYCLOAK_URL}/admin/realms/kubernetes/clients" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "'${SPIFFE_ID}'",
    "name": "Research Agent",
    "enabled": true,
    "clientAuthenticatorType": "client-jwt-federated",
    "publicClient": false,
    "standardFlowEnabled": true,
    "directAccessGrantsEnabled": true,
    "attributes": {
      "jwt.credential.certificate": "",
      "use.jwks.url": "true",
      "jwks.url": "http://spire-oidc-discovery.spire-system.svc:8080/.well-known/jwks.json",
      "id.token.as.detached.signature": "false",
      "client_credentials.use_refresh_token": "false"
    }
  }'
```

**Client Scopes for Token Exchange:**

```bash
# Create client scope for inter-agent communication
curl -X POST "${KEYCLOAK_URL}/admin/realms/kubernetes/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "code-agent-audience",
    "protocol": "openid-connect",
    "attributes": {
      "include.in.token.scope": "true",
      "display.on.consent.screen": "false"
    }
  }'

# Add audience mapper
SCOPE_ID=$(curl -s "${KEYCLOAK_URL}/admin/realms/kubernetes/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.name=="code-agent-audience") | .id')

curl -X POST "${KEYCLOAK_URL}/admin/realms/kubernetes/client-scopes/${SCOPE_ID}/protocol-mappers/models" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "code-agent-audience",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-audience-mapper",
    "config": {
      "included.client.audience": "spiffe://kagenti.dev/ns/team1/sa/code-agent-sa",
      "id.token.claim": "false",
      "access.token.claim": "true"
    }
  }'
```

**Token Exchange Permissions:**

```bash
# Enable token exchange for code-agent client
CODE_AGENT_CLIENT_ID=$(curl -s "${KEYCLOAK_URL}/admin/realms/kubernetes/clients" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.clientId=="spiffe://kagenti.dev/ns/team1/sa/code-agent-sa") | .id')

# Enable permissions
curl -X PUT "${KEYCLOAK_URL}/admin/realms/kubernetes/clients/${CODE_AGENT_CLIENT_ID}/management/permissions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}'

# Create policy allowing research-agent to exchange tokens for code-agent
RESEARCH_SPIFFE_ID="spiffe://kagenti.dev/ns/team1/sa/research-agent-sa"

curl -X POST "${KEYCLOAK_URL}/admin/realms/kubernetes/clients/${CODE_AGENT_CLIENT_ID}/authz/resource-server/policy/client" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "research-to-code-exchange",
    "clients": ["'${RESEARCH_SPIFFE_ID}'"]
  }'

# Apply policy to token-exchange permission
POLICY_ID=$(curl -s "${KEYCLOAK_URL}/admin/realms/kubernetes/clients/${CODE_AGENT_CLIENT_ID}/authz/resource-server/policy" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.name=="research-to-code-exchange") | .id')

TOKEN_EXCHANGE_PERMISSION_ID=$(curl -s "${KEYCLOAK_URL}/admin/realms/kubernetes/clients/${CODE_AGENT_CLIENT_ID}/authz/resource-server/permission" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.name=="token-exchange.permission") | .id')

curl -X PUT "${KEYCLOAK_URL}/admin/realms/kubernetes/clients/${CODE_AGENT_CLIENT_ID}/authz/resource-server/permission/${TOKEN_EXCHANGE_PERMISSION_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "policies": ["'${POLICY_ID}'"]
  }'
```

---

### Phase 4: Update Agent Deployments

**Priority:** P1

**Estimated Effort:** 4-6 hours

**Files to Modify:**
- `components/03-applications/agents/research-agent.yaml`
- `components/03-applications/agents/code-agent.yaml`
- `components/03-applications/agents/orchestrator-agent.yaml`

**Changes Required:**

1. Mount SPIRE agent socket
2. Add SPIFFE_ENDPOINT_SOCKET environment variable
3. Add Keycloak OAuth configuration
4. Add ServiceAccount for SPIFFE ID

**Example (research-agent.yaml):**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: research-agent-sa
  namespace: team1
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: research-agent
  namespace: team1
spec:
  template:
    spec:
      serviceAccountName: research-agent-sa
      volumes:
      # NEW: SPIRE agent socket volume
      - name: spire-agent-socket
        hostPath:
          path: /run/spire/sockets
          type: Directory

      containers:
      - name: agent
        image: ghcr.io/kagenti/kagenti/agents/research-agent:v0.1.0-alpha.7

        # NEW: Mount SPIRE socket
        volumeMounts:
        - name: spire-agent-socket
          mountPath: /run/spire/sockets
          readOnly: true

        env:
        # NEW: SPIRE configuration
        - name: SPIFFE_ENDPOINT_SOCKET
          value: "unix:///run/spire/sockets/agent.sock"
        - name: SPIFFE_ID
          value: "spiffe://kagenti.dev/ns/team1/sa/research-agent-sa"

        # NEW: Keycloak OAuth configuration
        - name: KEYCLOAK_URL
          value: "https://keycloak.localtest.me:9443"
        - name: KEYCLOAK_REALM
          value: "kubernetes"
        - name: KEYCLOAK_CLIENT_ID
          value: "spiffe://kagenti.dev/ns/team1/sa/research-agent-sa"

        # Existing environment variables...
```

**SPIRE ClusterSPIFFEID Configuration:**

Create `components/03-applications/agents/cluster-spiffeid.yaml`:

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: agents
spec:
  spiffeIDTemplate: "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
  podSelector:
    matchLabels:
      app.kubernetes.io/component: agent
  namespaceSelector:
    matchLabels:
      kagenti.io/agent-namespace: "true"
  dnsNameTemplates:
  - "{{ .PodMeta.Name }}.{{ .PodMeta.Namespace }}.svc.cluster.local"
  workloadSelectorTemplates:
  - "k8s:ns:{{ .PodMeta.Namespace }}"
  - "k8s:sa:{{ .PodSpec.ServiceAccountName }}"
  - "k8s:pod-name:{{ .PodMeta.Name }}"
```

**Namespace Label:**

```yaml
# Label team1 namespace for agent SPIFFE IDs
apiVersion: v1
kind: Namespace
metadata:
  name: team1
  labels:
    kagenti.io/agent-namespace: "true"
    istio-injection: enabled
```

---

### Phase 5: Create OAuth Helper Library

**Priority:** P2

**Estimated Effort:** 8-10 hours

**Purpose:** Simplify agent OAuth operations

**Files to Create:**
- `kagenti/agents/common/oauth.py` (in kagenti repo)

**Functionality:**

```python
class SPIFFEOAuthClient:
    """OAuth client that uses SPIRE JWT SVID for authentication"""

    def __init__(
        self,
        keycloak_url: str,
        realm: str,
        spiffe_socket: str = "unix:///run/spire/sockets/agent.sock"
    ):
        self.keycloak_url = keycloak_url
        self.realm = realm
        self.spiffe_socket = spiffe_socket

    def get_spire_jwt_svid(self, audience: str) -> str:
        """Fetch JWT SVID from SPIRE agent"""
        # Use py-spiffe library
        from pyspiffe.workloadapi import WorkloadApiClient

        with WorkloadApiClient(self.spiffe_socket) as client:
            svid = client.fetch_jwt_svid(audience=[audience])
            return svid.token

    def authenticate(self, username: str, password: str, scope: str = None) -> dict:
        """Authenticate user and get access token using SPIRE JWT"""
        client_assertion = self.get_spire_jwt_svid(
            audience=f"{self.keycloak_url}/realms/{self.realm}"
        )

        data = {
            "client_assertion": client_assertion,
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "grant_type": "password",
            "username": username,
            "password": password,
            "client_id": os.environ["SPIFFE_ID"]
        }

        if scope:
            data["scope"] = scope

        response = requests.post(
            f"{self.keycloak_url}/realms/{self.realm}/protocol/openid-connect/token",
            data=data
        )
        response.raise_for_status()
        return response.json()

    def exchange_token(
        self,
        subject_token: str,
        target_audience: str
    ) -> dict:
        """Exchange token for new token with different audience"""
        client_assertion = self.get_spire_jwt_svid(
            audience=f"{self.keycloak_url}/realms/{self.realm}"
        )

        data = {
            "client_id": os.environ["SPIFFE_ID"],
            "client_assertion": client_assertion,
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "requested_token_type": "urn:ietf:params:oauth:token-type:refresh_token",
            "subject_token": subject_token,
            "audience": target_audience
        }

        response = requests.post(
            f"{self.keycloak_url}/realms/{self.realm}/protocol/openid-connect/token",
            data=data
        )
        response.raise_for_status()
        return response.json()
```

**Dependencies:**

Add to `kagenti/agents/requirements.txt`:
```
py-spiffe>=0.7.0
```

---

## Configuration Details

### SPIRE Configuration

**Current State:** ✅ Properly configured

**Trust Domain:** `kagenti.dev`
**Cluster Name:** `kagenti-demo`
**Namespace:** `spire-system`

**Key Files:**
- `argocd/applications/helm/spire.yaml` - Helm Application
- `components/00-infrastructure/spire/spire-helm-values.yaml` - Helm values
- `argocd/config/argocd-cm-spire-health.yaml` - Health checks

**No changes needed** - SPIRE is correctly deployed

### Keycloak Configuration

**Current Version:** 26.4.1 ✅
**Namespace:** keycloak
**Realm:** kubernetes (existing)

**Required Changes:**
1. Enable SPIFFE preview features (Phase 1)
2. Configure SPIFFE IDP (Phase 2)
3. Create agent OAuth clients (Phase 3)

### Agent Configuration

**Namespaces:** team1, team2, ...
**ServiceAccounts:** research-agent-sa, code-agent-sa, orchestrator-agent-sa

**Required Changes:**
1. Mount SPIRE socket (Phase 4)
2. Add OAuth environment variables (Phase 4)
3. Create ClusterSPIFFEID (Phase 4)

---

## Testing Plan

### Phase 1 Testing: Keycloak Features

```bash
# 1. Deploy updated Keycloak
kubectl apply -k components/00-infrastructure/keycloak/

# 2. Wait for Keycloak to restart
kubectl rollout status statefulset/keycloak -n keycloak

# 3. Verify SPIFFE features enabled
kubectl logs -n keycloak keycloak-0 | grep -i "spiffe"
kubectl logs -n keycloak keycloak-0 | grep -i "client-auth-federated"

# 4. Check Keycloak admin UI
# Navigate to: https://keycloak.localtest.me:9443/admin/master/console
# Verify SPIFFE features appear in Client Authentication settings
```

### Phase 2 Testing: SPIFFE IDP

```bash
# 1. Run SPIFFE IDP setup job
kubectl create job --from=cronjob/spiffe-idp-setup manual-run -n keycloak

# 2. Check job logs
kubectl logs -n keycloak job/manual-run

# 3. Verify IDP in Keycloak UI
# Navigate to: Realm: kubernetes → Identity Providers
# Should see "SPIFFE/SPIRE" provider

# 4. Test OIDC discovery endpoint
curl -k http://spire-oidc-discovery.spire-system.svc:8080/.well-known/openid-configuration | jq
```

### Phase 3 Testing: Agent OAuth Clients

```bash
# 1. Check that agent clients were created
kubectl get secrets -n team1 | grep oauth

# 2. Verify client configuration via Keycloak API
TOKEN=$(kubectl exec -n keycloak keycloak-0 -- /bin/bash -c \
  'curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -d "username=admin" -d "password=admin123" -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r .access_token')

kubectl exec -n keycloak keycloak-0 -- /bin/bash -c \
  "curl -s http://localhost:8080/admin/realms/kubernetes/clients \
  -H 'Authorization: Bearer ${TOKEN}' | jq '.[] | select(.clientId | startswith(\"spiffe://\"))'"
```

### Phase 4 Testing: Agent SPIFFE IDs

```bash
# 1. Deploy updated agents
kubectl apply -k components/03-applications/agents/

# 2. Verify SPIRE socket is mounted
kubectl exec -n team1 research-agent-<pod-id> -- ls -la /run/spire/sockets/

# 3. Fetch JWT SVID from SPIRE
kubectl exec -n team1 research-agent-<pod-id> -- \
  /opt/spire/bin/spire-agent api fetch jwt \
  -socketPath /run/spire/sockets/agent.sock \
  -audience https://keycloak.localtest.me:9443/realms/kubernetes

# 4. Verify SPIFFE ID is correct
# Decode JWT (copy output from above command) at jwt.io
# Check 'sub' claim matches: spiffe://kagenti.dev/ns/team1/sa/research-agent-sa
```

### Phase 5 Testing: End-to-End OAuth Flow

**Create test script:** `tests/integration/test_spire_oauth_flow.sh`

```bash
#!/bin/bash
set -e

echo "=== Testing SPIRE + Keycloak OAuth Integration ==="

# 1. Get research-agent pod
RESEARCH_POD=$(kubectl get pod -n team1 -l app=research-agent -o jsonpath='{.items[0].metadata.name}')

echo "Using pod: $RESEARCH_POD"

# 2. Fetch SPIRE JWT SVID
echo "Fetching SPIRE JWT SVID..."
SPIFFE_JWT=$(kubectl exec -n team1 $RESEARCH_POD -- \
  /opt/spire/bin/spire-agent api fetch jwt \
  -socketPath /run/spire/sockets/agent.sock \
  -audience https://keycloak.localtest.me:9443/realms/kubernetes | grep -o 'token  : .*' | cut -d' ' -f3)

echo "Got SPIRE JWT (first 50 chars): ${SPIFFE_JWT:0:50}..."

# 3. Authenticate to Keycloak using SPIRE JWT
echo "Authenticating to Keycloak with SPIRE JWT..."
ACCESS_TOKEN=$(curl -k -sX POST "https://keycloak.localtest.me:9443/realms/kubernetes/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_assertion=$SPIFFE_JWT" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "grant_type=password" \
  -d "username=testuser" \
  -d "password=testpass" \
  -d "scope=code-agent-audience" \
  -d "client_id=spiffe://kagenti.dev/ns/team1/sa/research-agent-sa" | jq -r .access_token)

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Failed to get access token"
  exit 1
fi

echo "✓ Got access token (first 50 chars): ${ACCESS_TOKEN:0:50}..."

# 4. Decode and verify access token
echo "Decoding access token..."
PAYLOAD=$(echo $ACCESS_TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq)
AUDIENCE=$(echo $PAYLOAD | jq -r .aud)

echo "Access token audience: $AUDIENCE"

if [ "$AUDIENCE" != "spiffe://kagenti.dev/ns/team1/sa/code-agent-sa" ]; then
  echo "❌ Incorrect audience. Expected: spiffe://kagenti.dev/ns/team1/sa/code-agent-sa"
  exit 1
fi

echo "✓ Access token has correct audience"

# 5. Test token exchange (research → code agent)
echo "Testing token exchange..."
CODE_AGENT_POD=$(kubectl get pod -n team1 -l app=code-agent -o jsonpath='{.items[0].metadata.name}')
CODE_SPIFFE_JWT=$(kubectl exec -n team1 $CODE_AGENT_POD -- \
  /opt/spire/bin/spire-agent api fetch jwt \
  -socketPath /run/spire/sockets/agent.sock \
  -audience https://keycloak.localtest.me:9443/realms/kubernetes | grep -o 'token  : .*' | cut -d' ' -f3)

EXCHANGED_TOKEN=$(curl -k -sX POST "https://keycloak.localtest.me:9443/realms/kubernetes/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=spiffe://kagenti.dev/ns/team1/sa/code-agent-sa" \
  -d "client_assertion=$CODE_SPIFFE_JWT" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "requested_token_type=urn:ietf:params:oauth:token-type:refresh_token" \
  -d "subject_token=$ACCESS_TOKEN" \
  -d "audience=tool-service" | jq -r .access_token)

if [ "$EXCHANGED_TOKEN" == "null" ] || [ -z "$EXCHANGED_TOKEN" ]; then
  echo "❌ Token exchange failed"
  exit 1
fi

echo "✓ Token exchange successful (first 50 chars): ${EXCHANGED_TOKEN:0:50}..."

# 6. Verify exchanged token audience
EXCHANGED_PAYLOAD=$(echo $EXCHANGED_TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq)
EXCHANGED_AUDIENCE=$(echo $EXCHANGED_PAYLOAD | jq -r .aud)

echo "Exchanged token audience: $EXCHANGED_AUDIENCE"

if [ "$EXCHANGED_AUDIENCE" != "tool-service" ]; then
  echo "❌ Incorrect exchanged token audience"
  exit 1
fi

echo "✓ Exchanged token has correct audience"

echo ""
echo "=== ✅ All SPIRE + Keycloak OAuth tests passed! ==="
```

**Run test:**
```bash
chmod +x tests/integration/test_spire_oauth_flow.sh
./tests/integration/test_spire_oauth_flow.sh
```

---

## References

### Official Documentation

1. **SPIRE:**
   - [SPIRE Documentation](https://spiffe.io/docs/latest/spire-about/)
   - [SPIRE Controller Manager](https://github.com/spiffe/spire-controller-manager)
   - [ClusterSPIFFEID CRD](https://github.com/spiffe/spire-controller-manager/blob/main/docs/clusterspiffeid-crd.md)
   - [py-spiffe Library](https://github.com/spiffe/py-spiffe)

2. **Keycloak + SPIFFE:**
   - [Keycloak 26.4 SPIFFE Support](https://www.cncf.io/blog/2025/11/07/self-hosted-human-and-machine-identities-in-keycloak-26-4/)
   - [Keycloak Token Exchange](https://www.keycloak.org/docs/latest/securing_apps/#_token-exchange)
   - [Client Authentication with JWT](https://www.keycloak.org/docs/latest/securing_apps/#_client_authentication_adapter)

3. **Istio + SPIRE:**
   - [Istio SPIRE Integration](https://istio.io/latest/docs/ops/integrations/spire/)
   - [SPIRE and Istio Ambient](https://www.solo.io/blog/kubernetes-identity-the-right-way-with-spire-and-ambient)

### Kagenti Resources

1. **Upstream Repo:**
   - [TODO_FIX_SPIRE.md](../kagenti/TODO_FIX_SPIRE.md) - Comprehensive SPIRE research
   - [Keycloak Token Exchange Example](../kagenti/kagenti/examples/identity/keycloak_token_exchange/)
   - [SPIRE Component](../kagenti/kagenti/installer/app/components/spire.py)

2. **Current Deployment:**
   - `argocd/applications/helm/spire.yaml` - SPIRE Helm Application
   - `components/00-infrastructure/spire/` - SPIRE HTTPRoutes
   - `argocd/config/argocd-cm-spire-health.yaml` - Health checks
   - `components/00-infrastructure/keycloak/` - Keycloak deployment

---

## Implementation Checklist

### Pre-Implementation

- [ ] Review this document with team
- [ ] Confirm green redeploy (all ArgoCD apps Healthy)
- [ ] Create feature branch: `git checkout -b feature/spire-keycloak-integration`

### Phase 1: Keycloak SPIFFE Features (Day 1)

- [ ] Update `keycloak-statefulset.yaml` with SPIFFE features
- [ ] Test Keycloak restart
- [ ] Verify features enabled in logs
- [ ] Commit: "feat: Enable Keycloak SPIFFE preview features"

### Phase 2: SPIFFE IDP Configuration (Day 2-3)

- [ ] Create `spiffe-idp-rbac.yaml`
- [ ] Create `spiffe-idp-setup-job.yaml`
- [ ] Update `kustomization.yaml`
- [ ] Test job execution
- [ ] Verify IDP created in Keycloak UI
- [ ] Test OIDC discovery endpoint
- [ ] Commit: "feat: Configure SPIRE OIDC as Keycloak Identity Provider"

### Phase 3: Agent OAuth Clients (Day 4-5)

- [ ] Extend `oauth-secrets-extractor-job.yaml` with agent logic
- [ ] Create agent client configurations
- [ ] Set up client scopes for token exchange
- [ ] Configure token exchange permissions
- [ ] Test client creation
- [ ] Verify secrets created
- [ ] Commit: "feat: Configure OAuth clients for agents with SPIRE auth"

### Phase 4: Agent Deployments (Day 6-7)

- [ ] Create `cluster-spiffeid.yaml`
- [ ] Update `research-agent.yaml` with SPIRE socket
- [ ] Update `code-agent.yaml` with SPIRE socket
- [ ] Update `orchestrator-agent.yaml` with SPIRE socket
- [ ] Label team1 namespace for SPIFFE IDs
- [ ] Test SPIRE socket mount
- [ ] Verify SPIFFE ID assignment
- [ ] Test JWT SVID fetch
- [ ] Commit: "feat: Enable SPIRE authentication for agents"

### Phase 5: OAuth Helper Library (Day 8-9)

- [ ] Create `kagenti/agents/common/oauth.py` (in kagenti repo)
- [ ] Add py-spiffe dependency
- [ ] Implement SPIFFEOAuthClient class
- [ ] Write unit tests
- [ ] Update agent code to use helper
- [ ] Submit PR to kagenti repo
- [ ] Commit: "feat: Add SPIRE OAuth helper library for agents"

### Testing & Documentation (Day 10)

- [ ] Run Phase 1-4 tests
- [ ] Create and run end-to-end test script
- [ ] Update `docs/ENCRYPTION_ARCHITECTURE.md`
- [ ] Create `docs/SPIRE_KEYCLOAK_INTEGRATION.md`
- [ ] Update README.md with SPIRE integration info
- [ ] Commit: "docs: Document SPIRE + Keycloak integration"

### Finalization

- [ ] Full platform redeploy test
- [ ] Verify all ArgoCD apps Healthy
- [ ] Create PR with all changes
- [ ] Team review
- [ ] Merge to main

---

## Success Criteria

✅ **Phase 1 Complete:**
- Keycloak starts with SPIFFE features enabled
- No errors in Keycloak logs

✅ **Phase 2 Complete:**
- SPIFFE identity provider visible in Keycloak admin UI
- OIDC discovery endpoint responds correctly

✅ **Phase 3 Complete:**
- Agent OAuth clients created in Keycloak
- Client authentication set to "Signed JWT - Federated"
- Token exchange permissions configured

✅ **Phase 4 Complete:**
- Agents can access SPIRE agent socket
- Agents can fetch JWT SVIDs from SPIRE
- SPIFFE IDs match expected pattern

✅ **Phase 5 Complete:**
- Agents can authenticate to Keycloak using SPIRE JWT
- Token exchange works between agent tiers
- Access tokens have correct audience claims

✅ **Overall Integration Success:**
- End-to-end test script passes
- All ArgoCD applications Healthy
- No manual interventions required
- Documentation complete

---

**Next Steps:**
1. ✅ Wait for green redeploy
2. ✅ Review this TODO with team
3. ✅ Create feature branch
4. ✅ Begin Phase 1 implementation

---

**Document Version:** 1.0
**Last Updated:** 2025-11-13
**Maintained By:** Kagenti Platform Team
