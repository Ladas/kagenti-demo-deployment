# Kubernetes User Impersonation for Kagenti UI

**Last Updated**: 2025-11-20
**Status**: ❌ NOT IMPLEMENTED (Requires significant infrastructure changes)

---

## Overview

This document explains what Kubernetes user impersonation is, why it's not currently implemented, and what would be required to enable it.

---

## What is Kubernetes User Impersonation?

**User impersonation** allows a Kubernetes client (like the Kagenti UI) to make API calls **on behalf of authenticated users** instead of using a shared service account.

### Current Architecture (Service Account)

```
User (kagenti-admin) → Keycloak OAuth → Kagenti UI Pod
                                            ↓
                              Service Account Token (kagenti-ui-service-account)
                                            ↓
                                    Kubernetes API Server
                                            ↓
                              ALL users share same permissions
```

### Desired Architecture (User Impersonation)

```
User (kagenti-admin) → Keycloak OAuth → Kagenti UI Pod
                                            ↓
                              OIDC Token (user identity: kagenti-admin@kagenti.local)
                                            ↓
                                    Kubernetes API Server
                                            ↓
                              Per-user RBAC (RoleBindings for kagenti-admin)
```

**Key Difference**:
- **Service Account**: All users → Same K8s permissions
- **User Impersonation**: Each user → Individual K8s permissions

---

## Current State

### Investigation Results

**Kind Cluster Configuration** (`scripts/kind/01-create-cluster.sh`):
- ❌ No OIDC authentication configured in API server
- ❌ No `--oidc-*` flags in kubeadmConfigPatches
- Uses default Kind authentication (service accounts + certificates only)

**Kagenti UI Code** (`kagenti/ui/lib/kube.py:33-79`):
- ❌ No user impersonation logic
- ❌ No OIDC token usage for K8s API calls
- Uses `kubernetes.config.load_incluster_config()` (service account token)
- OAuth `access_token` stored in session state but NOT passed to K8s API

**Conclusion**: User impersonation is **NOT implemented** in any layer (cluster, UI code, RBAC).

---

## Why It Can't "Just Be Turned On"

Enabling user impersonation requires changes across **3 layers**:

### Layer 1: Kubernetes API Server (Cluster Rebuild Required)

**Required Changes**:
1. Configure API server with OIDC authentication flags
2. Point to Keycloak as OIDC provider
3. Recreate Kind cluster with new configuration

**Kind Cluster Configuration** (`scripts/kind/01-create-cluster.sh`):

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        # OIDC Authentication (Keycloak)
        oidc-issuer-url: "https://keycloak.localtest.me:9443/realms/kagenti"
        oidc-client-id: "kubernetes"
        oidc-username-claim: "preferred_username"
        oidc-username-prefix: ""
        oidc-groups-claim: "groups"
        oidc-groups-prefix: ""
```

**Complexity**: ⭐⭐⭐ **HIGH**
- Requires cluster recreation (downtime)
- Keycloak must be accessible during cluster bootstrap
- Self-signed certificates cause TLS verification issues

### Layer 2: Keycloak Configuration

**Required Changes**:
1. Create new OIDC client (`kubernetes`) in Keycloak
2. Configure client with appropriate scopes (openid, profile, groups)
3. Add group claims to tokens
4. Configure user group mappings

**Keycloak Client Configuration**:

```yaml
# components/00-infrastructure/keycloak/realm-import-kagenti.yaml
clients:
  - clientId: kubernetes
    enabled: true
    protocol: openid-connect
    publicClient: false
    directAccessGrantsEnabled: true
    serviceAccountsEnabled: true
    authorizationServicesEnabled: false
    standardFlowEnabled: true
    implicitFlowEnabled: false
    redirectUris:
      - "http://localhost:8001/*"  # kubectl oidc-login callback
    protocolMappers:
      - name: groups
        protocol: openid-connect
        protocolMapper: oidc-group-membership-mapper
        config:
          claim.name: groups
          full.path: "false"
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
```

**Complexity**: ⭐⭐ **MEDIUM**
- Requires realm configuration update
- Need to test token issuance

### Layer 3: Kagenti UI Code Changes

**Required Changes**:
1. Extract Keycloak OIDC token from session state
2. Pass token to Kubernetes API client
3. Configure client to use token for authentication
4. Handle token refresh/expiration

**Modified `get_kube_api_client_cached()` function**:

```python
import streamlit as st
from kubernetes import client, config

@st.cache_resource
def get_kube_api_client_with_user_token(access_token: str):
    """
    Creates Kubernetes API client with user's OIDC token (impersonation).
    """
    # Load in-cluster config
    config.load_incluster_config()

    # Create configuration with user token
    configuration = client.Configuration()
    configuration.host = "https://kubernetes.default.svc"
    configuration.verify_ssl = True
    configuration.ssl_ca_cert = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

    # Use user's OIDC token instead of service account token
    configuration.api_key = {"authorization": f"Bearer {access_token}"}

    return client.ApiClient(configuration)

def get_user_api_client():
    """
    Get Kubernetes API client authenticated as current user.
    """
    # Extract OIDC token from Streamlit session state
    if "access_token" not in st.session_state:
        raise ValueError("User not authenticated - no access_token in session")

    access_token = st.session_state["access_token"]
    return get_kube_api_client_with_user_token(access_token)
```

**Complexity**: ⭐⭐ **MEDIUM**
- Requires code changes in UI
- Need to handle token expiration
- Testing required for all K8s API calls

### Layer 4: Kubernetes RBAC Configuration

**Required Changes**:
1. Create RoleBindings for each user in each namespace
2. Map Keycloak users/groups to Kubernetes roles
3. Test per-user access control

**Example RoleBinding** (`components/03-applications/team1/rbac.yaml`):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kagenti-admin-team1-access
  namespace: team1
subjects:
  # User identity from OIDC token (oidc-username-claim)
  - kind: User
    name: kagenti-admin  # From Keycloak preferred_username
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kagenti-ui-role
  apiGroup: rbac.authorization.k8s.io
---
# No RoleBinding for kagenti-admin in default namespace
# → kagenti-admin cannot access default namespace
```

**Complexity**: ⭐ **LOW** (but requires Layers 1-3 first)

---

## Implementation Roadmap

### Phase 1: Keycloak OIDC Client Setup (1 day)

**Tasks**:
- [ ] Create `kubernetes` OIDC client in Keycloak realm
- [ ] Configure group claims and scopes
- [ ] Test token issuance via Keycloak API
- [ ] Verify token contains `preferred_username` and `groups`

**Validation**:
```bash
# Get OIDC token
TOKEN=$(curl -k -X POST "https://keycloak.localtest.me:9443/realms/kagenti/protocol/openid-connect/token" \
  -d "username=kagenti-admin" \
  -d "password=admin123" \
  -d "grant_type=password" \
  -d "client_id=kubernetes" \
  -d "client_secret=<client-secret>" \
  | jq -r '.access_token')

# Decode token and verify claims
echo $TOKEN | cut -d. -f2 | base64 -d | jq .
# Expected: { "preferred_username": "kagenti-admin", "groups": [...] }
```

### Phase 2: Kind Cluster Reconfiguration (2-3 days)

**Challenges**:
- Keycloak must be accessible during cluster bootstrap
- Self-signed certificates require `--oidc-ca-file` configuration
- Need to test OIDC authentication before destroying existing cluster

**Tasks**:
- [ ] Update `scripts/kind/01-create-cluster.sh` with OIDC flags
- [ ] Test Keycloak accessibility from Kind node
- [ ] Handle certificate validation (CA bundle)
- [ ] Recreate cluster and verify API server OIDC configuration

**Validation**:
```bash
# Check API server flags
docker exec kagenti-demo-control-plane \
  cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep oidc

# Expected:
# - --oidc-issuer-url=https://keycloak.localtest.me:9443/realms/kagenti
# - --oidc-client-id=kubernetes
# - --oidc-username-claim=preferred_username
```

### Phase 3: UI Code Changes (2-3 days)

**Tasks**:
- [ ] Modify `get_kube_api_client_cached()` to accept user token
- [ ] Extract `access_token` from Streamlit session state
- [ ] Configure Kubernetes client with user token
- [ ] Handle token expiration (refresh or re-authenticate)
- [ ] Test all K8s API calls with user authentication

**Testing**:
- Verify K8s API calls succeed with user token
- Verify K8s API calls fail when user lacks permissions (test RBAC)
- Test token expiration handling

### Phase 4: RBAC Configuration (1 day)

**Tasks**:
- [ ] Create RoleBindings for `kagenti-admin` in `team1` namespace
- [ ] Verify `kagenti-admin` can access `team1` resources
- [ ] Verify `kagenti-admin` CANNOT access `default` namespace
- [ ] Document RBAC patterns for adding new users/namespaces

### Phase 5: Testing & Documentation (1 day)

**Tasks**:
- [ ] End-to-end testing with multiple users
- [ ] Verify per-user namespace access control
- [ ] Document OIDC configuration
- [ ] Update deployment guides

---

## Estimated Total Effort

**Total Time**: ~1-2 weeks (7-10 business days)

**Breakdown**:
- Keycloak setup: 1 day
- Cluster reconfiguration: 2-3 days (including testing)
- UI code changes: 2-3 days
- RBAC configuration: 1 day
- Testing & docs: 1 day

**Risk Factors**:
- ⚠️ Certificate validation issues (Keycloak self-signed cert)
- ⚠️ Cluster downtime during recreation
- ⚠️ Token expiration edge cases
- ⚠️ Debugging OIDC authentication failures

---

## Alternative: Application-Level Filtering (Simpler)

If per-user namespace access control is needed but full Kubernetes user impersonation is too complex, consider **application-level filtering**:

### How It Works

1. Keep current service account authentication (no cluster changes)
2. Add Keycloak role mapping in UI
3. Filter namespaces based on user's Keycloak roles (not K8s RBAC)

### Implementation

**Keycloak Roles**:
```yaml
# realm-import-kagenti.yaml
roles:
  - name: team1-access
  - name: team2-access
  - name: admin

users:
  - username: kagenti-admin
    realmRoles:
      - admin
      - team1-access
```

**UI Code** (`kube.py`):
```python
def get_enabled_namespaces_for_user(
    generic_api_client: Optional[kubernetes.client.ApiClient],
    user_roles: List[str]
) -> List[str]:
    """Filter namespaces based on user's Keycloak roles."""
    all_namespaces = get_enabled_namespaces(generic_api_client)

    # Admin sees all namespaces
    if "admin" in user_roles:
        return all_namespaces

    # Filter based on role-namespace mapping
    allowed_namespaces = []
    for namespace in all_namespaces:
        if f"{namespace}-access" in user_roles:
            allowed_namespaces.append(namespace)

    return allowed_namespaces
```

**Pros**:
- ✅ No cluster reconfiguration needed
- ✅ No OIDC setup required
- ✅ Simpler implementation (~2-3 days)

**Cons**:
- ❌ Not "true" Kubernetes RBAC (UI-level only)
- ❌ Doesn't prevent direct `kubectl` access (users can still use service account if they have cluster access)
- ❌ Requires manual role-namespace mapping

**Estimated Effort**: 2-3 days (vs 1-2 weeks for full impersonation)

---

## Recommendation

**For current Kind cluster development**:
→ Use **Application-Level Filtering** (simpler, faster)

**For production deployment**:
→ Consider **Kubernetes User Impersonation** (true RBAC, more secure)

**Reasoning**:
- Kind clusters are ephemeral (frequent recreation)
- OIDC setup in Kind is complex (certificate issues)
- Application-level filtering provides 80% of benefit with 20% of effort
- Production clusters can use managed OIDC (EKS IRSA, AKS Workload Identity, etc.)

---

## References

### Official Documentation

- [Kubernetes OIDC Authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens)
- [Kubernetes User Impersonation](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation)
- [Keycloak OIDC Client Configuration](https://www.keycloak.org/docs/latest/server_admin/#_oidc_clients)

### Example Implementations

- [kubectl oidc-login plugin](https://github.com/int128/kubelogin) - Example of OIDC authentication flow
- [Dex + Kubernetes](https://dexidp.io/docs/kubernetes/) - Similar OIDC setup

### Internal Documentation

- **Current namespace filtering**: `docs/KAGENTI_UI_NAMESPACE_ACCESS.md`
- **Keycloak configuration**: `components/00-infrastructure/keycloak/realm-import-job.yaml`
- **Kind cluster setup**: `scripts/kind/01-create-cluster.sh`

---

## Summary

**Question**: "Can Kubernetes user impersonation just be turned on?"

**Answer**: ❌ **NO** - It requires:
1. Keycloak OIDC client setup
2. Kind cluster recreation with OIDC flags
3. UI code changes to use user tokens
4. Per-user RBAC configuration

**Estimated effort**: 1-2 weeks

**Alternative**: Application-level filtering (2-3 days, good enough for development)

**Current state**: Not implemented in any layer (cluster, Keycloak, UI code)
