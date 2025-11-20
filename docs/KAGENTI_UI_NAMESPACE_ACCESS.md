# Kagenti UI Namespace Access Configuration

**Last Updated**: 2025-11-20
**Status**: ✅ CONFIGURED

---

## Overview

This document explains how the Kagenti UI controls namespace visibility and how `kagenti-admin` user access is configured.

---

## Architecture

### Authentication vs Authorization

**User Authentication** (Keycloak OAuth):
- Users log in via Keycloak (`kagenti` realm)
- OAuth flow: Kagenti UI → Keycloak → User credentials → Access token

**Kubernetes Authorization** (Service Account):
- ALL Kubernetes API calls use `kagenti-ui-service-account` token
- User's Keycloak identity is NOT passed to Kubernetes API
- All authenticated users share the same K8s permissions

**Key Insight**:
```
Keycloak User Identity ≠ Kubernetes User Identity
```

The UI doesn't implement per-user Kubernetes RBAC. Instead, it uses **label-based namespace filtering**.

---

## Namespace Filtering Mechanism

### How It Works

The Kagenti UI filters namespaces using Kubernetes labels (source: `kagenti/ui/lib/kube.py:165-170`):

```python
def get_enabled_namespaces(
    generic_api_client: Optional[kubernetes.client.ApiClient],
) -> List[str]:
    """Lists all enabled namespaces for listing or deploying agents/tools."""
    selector = f"{constants.ENABLED_NAMESPACE_LABEL_KEY}={constants.ENABLED_NAMESPACE_LABEL_VALUE}"
    return get_all_namespaces(generic_api_client, label_selector=selector)
```

**Required Label** (from `constants.py:39-40`):
```python
ENABLED_NAMESPACE_LABEL_KEY = "kagenti-enabled"
ENABLED_NAMESPACE_LABEL_VALUE = "true"
```

**Result**: Only namespaces with label `kagenti-enabled=true` appear in the UI.

---

## Current Configuration

### ✅ team1 Namespace (VISIBLE)

```bash
kubectl get namespace team1 -o jsonpath='{.metadata.labels}'
```

**Output**:
```json
{
  "app.kubernetes.io/part-of": "kagenti",
  "istio-injection": "enabled",
  "kagenti-enabled": "true",          ← VISIBLE IN UI
  "kubernetes.io/metadata.name": "team1",
  "name": "team1"
}
```

### ✅ default Namespace (HIDDEN)

```bash
kubectl get namespace default -o jsonpath='{.metadata.labels}'
```

**Output**:
```json
{
  "kubernetes.io/metadata.name": "default"
}
```

**No `kagenti-enabled` label** → **NOT visible in UI**

---

## User Access

### kagenti-admin User

**Created In**: `components/00-infrastructure/keycloak/realm-import-job.yaml:309`

```bash
create_user "kagenti" "kagenti-admin" "kagenti-admin@kagenti.local" "Kagenti" "Admin" "admin123"
```

**Credentials**:
- **Username**: `kagenti-admin`
- **Password**: `admin123`
- **Realm**: `kagenti`

**Access URL**: https://kagenti.localtest.me:9443

**Namespaces Visible After Login**:
- ✅ `team1` (has `kagenti-enabled=true` label)
- ❌ `default` (no `kagenti-enabled` label)
- ✅ Any other namespace with `kagenti-enabled=true` label

---

## Verification

### Test Namespace Visibility

```bash
# List all namespaces visible in Kagenti UI
kubectl get namespaces -l kagenti-enabled=true -o custom-columns=NAME:.metadata.name

# Expected output:
# NAME
# team1
```

### Test UI Access

1. Open Kagenti UI: https://kagenti.localtest.me:9443
2. Log in with `kagenti-admin` / `admin123`
3. Navigate to namespace selector
4. **Expected**: Only `team1` appears in dropdown (not `default`)

---

## Limitations

### No Per-User Namespace Access Control

**Current Behavior**:
- ALL authenticated users see the same namespaces (those with `kagenti-enabled=true`)
- Cannot restrict `team1` to only `kagenti-admin` (all users will see it)

**Why**:
- UI uses service account (`kagenti-ui-service-account`) for K8s API calls
- No user impersonation implemented
- Keycloak roles not mapped to Kubernetes RBAC

**Example**: If you add another user `developer-bob`:
- Bob logs in via Keycloak ✅
- Bob also sees `team1` namespace ✅ (same as kagenti-admin)

---

## Adding More Namespaces

To make a namespace visible in the UI:

```bash
# Add label to namespace
kubectl label namespace <namespace-name> kagenti-enabled=true

# Verify
kubectl get namespace <namespace-name> -o jsonpath='{.metadata.labels.kagenti-enabled}'
# Expected: true
```

To hide a namespace:

```bash
# Remove label
kubectl label namespace <namespace-name> kagenti-enabled-

# Verify
kubectl get namespace <namespace-name> -o jsonpath='{.metadata.labels.kagenti-enabled}'
# Expected: (empty)
```

---

## Future Enhancements (If Per-User Access Control Needed)

### Option 1: Application-Level Filtering

**Approach**: Add Keycloak role-based filtering in UI code

**Implementation**:
1. Add roles to Keycloak realm (e.g., `team1-user`, `team2-user`)
2. Assign roles to users
3. Modify UI to filter namespaces based on user's Keycloak roles
4. Map Keycloak roles to namespace access in ConfigMap

**Effort**: ~1-2 days development

**Example**:
```yaml
# ConfigMap: kagenti-ui-namespace-roles
apiVersion: v1
kind: ConfigMap
metadata:
  name: kagenti-ui-namespace-roles
  namespace: kagenti-system
data:
  role-mappings.yaml: |
    team1-user:
      - team1
    team2-user:
      - team2
    admin:
      - team1
      - team2
```

### Option 2: Kubernetes User Impersonation

**Approach**: Make K8s API calls on behalf of Keycloak users

**Implementation**:
1. Configure K8s API server with OIDC authentication
2. Modify UI to pass user tokens to K8s API (impersonation)
3. Create per-user RoleBindings in each namespace
4. Use Kubernetes native RBAC

**Effort**: ~1 week (complex in Kind clusters)

**Example**:
```yaml
# RoleBinding for kagenti-admin in team1
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kagenti-admin-team1-access
  namespace: team1
subjects:
- kind: User
  name: kagenti-admin@kagenti.local  # From OIDC token
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kagenti-ui-role
  apiGroup: rbac.authorization.k8s.io
```

---

## References

### Source Code

- **Namespace filtering**: `/Users/ladas/Projects/OCTO/research/kagenti/kagenti/ui/lib/kube.py:165-170`
- **Label constants**: `/Users/ladas/Projects/OCTO/research/kagenti/kagenti/ui/lib/constants.py:39-40`
- **K8s client config**: `/Users/ladas/Projects/OCTO/research/kagenti/kagenti/ui/lib/kube.py:33-79`

### Deployment Config

- **UI deployment**: `components/01-platform/kagenti-ui/deployment.yaml`
- **Service account**: `components/01-platform/kagenti-ui/deployment.yaml:5-8`
- **ClusterRole**: `components/01-platform/kagenti-ui/deployment.yaml:10-29`
- **Keycloak user creation**: `components/00-infrastructure/keycloak/realm-import-job.yaml:309`

---

## Summary

**✅ Current Configuration**:
- `kagenti-admin` user exists in Keycloak
- `team1` namespace has `kagenti-enabled=true` label → **Visible in UI**
- `default` namespace has no label → **NOT visible in UI**
- Requirements met: kagenti-admin can access team1, cannot see default

**⚠️ Limitation**:
- All authenticated users see the same namespaces (label-based filtering only)
- No per-user namespace access control

**🔄 To Enable Per-User Access**:
- Requires UI code changes (Option 1 or Option 2 above)
- Estimated effort: 1-2 days (app-level) or 1 week (K8s impersonation)
