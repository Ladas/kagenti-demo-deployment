# GitHub Issues Draft for Kagenti Platform

This file contains draft GitHub issues for problems discovered during platform deployment. Copy and paste these into the appropriate GitHub repository issue tracker.

---

## Issue 1: kagenti-operator Container Image Not Published

**Repository**: `kagenti/kagenti-operator`
**Labels**: `bug`, `priority:critical`, `infrastructure`

### Title
Container image for kagenti-operator is not published by CI/CD pipeline

### Description

The `kagenti-operator` Helm chart is published and defines CRDs (Agent, AgentBuild, AgentCard), but the container image for the operator controller is not being built or published by the CI/CD pipeline.

### Current Behavior

When deploying the kagenti-operator Helm chart, the operator pod fails with `ImagePullBackOff`:

```
Failed to pull image "ghcr.io/kagenti/kagenti-operator:latest":
rpc error: code = Unknown desc = failed to pull and unpack image "ghcr.io/kagenti/kagenti-operator:latest":
failed to resolve reference "ghcr.io/kagenti/kagenti-operator:latest":
pulling from host ghcr.io failed with status code [manifests latest]: 403 Forbidden
```

### Root Cause

The `.goreleaser.yaml` configuration only builds the `platform-operator` image:

```yaml
kos:
  - id: "platform-operator-ko"
    repositories:
    - ghcr.io/kagenti/kagenti-operator/platform-operator  # ONLY platform-operator
```

There is no build configuration for the `kagenti-operator` image.

### Expected Behavior

The CI/CD pipeline should build and publish both operator images:
- `ghcr.io/kagenti/kagenti-operator/kagenti-operator:VERSION`
- `ghcr.io/kagenti/kagenti-operator/platform-operator:VERSION`

### Reproduction Steps

1. Clone the repository: `git clone https://github.com/kagenti/kagenti-operator.git`
2. Check `.goreleaser.yaml` - only `platform-operator-ko` is defined
3. Try to pull the image: `docker pull ghcr.io/kagenti/kagenti-operator:latest`
4. Result: 403 Forbidden

### Impact

- Cannot deploy kagenti-operator in production or local environments
- Agent CRD reconciliation not functioning
- AgentBuild automation not working
- Blocks GitOps-based deployments that require both operators

### Environment

- **Cluster**: kind v0.20.0
- **Kubernetes**: v1.27.3
- **Helm Chart**: kagenti-operator v0.2.0-alpha.15
- **Attempted Image Paths** (all failed):
  - `ghcr.io/kagenti/kagenti-operator/kagenti-operator:0.2.0-alpha.15`
  - `ghcr.io/kagenti/kagenti-operator:latest`
  - `ghcr.io/kagenti/kagenti-operator:0.2.0-alpha.15`

### Proposed Solution

Update `.goreleaser.yaml` to include kagenti-operator build configuration:

```yaml
kos:
  - id: "platform-operator-ko"
    repositories:
      - ghcr.io/kagenti/kagenti-operator/platform-operator
    build: ./platform-operator
    main: ./cmd/main.go
    bare: true
    preserve_import_paths: false
    base_import_paths: true

  # ADD THIS:
  - id: "kagenti-operator-ko"
    repositories:
      - ghcr.io/kagenti/kagenti-operator/kagenti-operator
    build: ./kagenti-operator
    main: ./cmd/main.go
    bare: true
    preserve_import_paths: false
    base_import_paths: true
```

### Workaround

Currently using `platform-operator` only, which provides all 5 CRDs (Platform, Component, Agent, AgentBuild, AgentCard). The kagenti-operator pod remains in ImagePullBackOff but CRDs are functional.

### Additional Context

- Last commit checked: `82e5753` (2025-01-08)
- Recent commit message includes "fix-image-reference" but only addresses platform-operator
- Both Helm charts (platform-operator and kagenti-operator) are published successfully
- Issue affects local kind clusters and production deployments

---

## Issue 2: SPIRE Helm Chart Missing Controller Manager CRDs

**Repository**: `spiffe/helm-charts-hardened`
**Labels**: `bug`, `helm`, `crd`

### Title
SPIRE Helm chart sync fails: ClusterSPIFFEID CRD not installed

### Description

When deploying the SPIRE Helm chart (v0.21.0), the deployment fails because the `ClusterSPIFFEID` CRD from spire-controller-manager is not included in the chart.

### Current Behavior

ArgoCD sync fails with:

```
The Kubernetes API could not find spire.spiffe.io/ClusterSPIFFEID
for requested resource spire-system/spire-system-spire-default.
Make sure the "ClusterSPIFFEID" CRD is installed on the destination cluster.
```

### Root Cause

The SPIRE Helm chart includes ClusterSPIFFEID resources but does not include the CRD definition. The CRD must be installed separately from the spire-controller-manager project.

### Expected Behavior

The SPIRE Helm chart should include all required CRDs, or document the manual CRD installation requirement in the README.

### Reproduction Steps

1. Install SPIRE Helm chart:
   ```bash
   helm install spire spiffe/spire --version 0.21.0 \
     --namespace spire-system --create-namespace
   ```
2. Observe error about missing ClusterSPIFFEID CRD
3. Check chart templates - CRD not included

### Impact

- SPIRE cannot be deployed using Helm/ArgoCD without manual intervention
- Breaks GitOps workflows that expect self-contained Helm charts
- Not following Helm best practices for CRD management

### Environment

- **Helm Chart**: spiffe/spire v0.21.0
- **Chart Repository**: https://spiffe.github.io/helm-charts-hardened
- **Kubernetes**: v1.27.3
- **Deployment Tool**: ArgoCD v2.9.3

### Proposed Solution

**Option 1**: Include CRDs in Helm chart (preferred)
- Add `crds/` directory with ClusterSPIFFEID CRD
- Follow Helm CRD best practices

**Option 2**: Document manual installation requirement
- Update README with clear instructions:
  ```bash
  # Install CRDs first
  kubectl apply -f https://raw.githubusercontent.com/spiffe/spire-controller-manager/main/config/crd/bases/spire.spiffe.io_clusterspiffeids.yaml

  # Then install chart
  helm install spire spiffe/spire
  ```

**Option 3**: Create separate CRD-only chart
- Publish `spiffe/spire-crds` chart
- Document dependency in main chart

### Workaround

Manually install the CRD before deploying SPIRE:

```bash
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/spiffe/spire-controller-manager/main/config/crd/bases/spire.spiffe.io_clusterspiffeids.yaml
```

Then deploy the SPIRE Helm chart.

### Additional Context

- Similar issue may affect other SPIRE controller-manager CRDs
- This is a common pattern issue with Kubebuilder/Operator SDK projects
- Other charts in the ecosystem (Istio, Cert-Manager) handle CRDs correctly

### References

- SPIRE Controller Manager CRDs: https://github.com/spiffe/spire-controller-manager/tree/main/config/crd/bases
- Helm CRD Best Practices: https://helm.sh/docs/chart_best_practices/custom_resource_definitions/

---

## Issue 3: Grafana Pod Failing Due to Missing OIDC Secret

**Repository**: `kagenti/kagenti-demo-deployment`
**Labels**: `bug`, `observability`, `keycloak-integration`

### Title
Grafana deployment fails with missing grafana-oidc-secret

### Description

The Grafana pod in the observability stack fails to start due to a missing `grafana-oidc-secret` that should be created by the Keycloak configuration Job.

### Current Behavior

```
Error: secret "grafana-oidc-secret" not found
Pod Status: CreateContainerConfigError
```

### Root Cause

The Grafana deployment references a secret that is supposed to be generated by `keycloak-config` Job, but either:
1. The Job hasn't run yet (dependency ordering issue)
2. The Job failed silently
3. The secret name mismatch between Job and Deployment

### Expected Behavior

1. Keycloak configuration Job runs (Wave 15)
2. Job creates OAuth2 client in Keycloak
3. Job creates `grafana-oidc-secret` with client credentials
4. Grafana pod starts successfully using the secret

### Reproduction Steps

1. Deploy observability stack: `argocd app sync observability`
2. Check Grafana pod: `kubectl get pod -n observability -l app=grafana`
3. Observe CreateContainerConfigError
4. Check secret: `kubectl get secret grafana-oidc-secret -n observability`
5. Result: Not found

### Impact

- Grafana UI not accessible
- Metrics dashboards unavailable
- Observability stack degraded
- Blocks end-to-end platform verification

### Environment

- **Cluster**: kind-kagenti-demo
- **Namespace**: observability
- **Grafana Version**: 11.4.0
- **Keycloak**: Running and healthy

### Proposed Solution

**Option 1**: Fix Job dependency ordering
- Ensure keycloak-config Job runs before Grafana deployment
- Use ArgoCD sync waves:
  ```yaml
  # keycloak-config-job.yaml
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "15"

  # grafana-deployment.yaml
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "20"
  ```

**Option 2**: Add init container to Grafana deployment
- Wait for secret to exist before starting main container

**Option 3**: Make secret optional
- Allow Grafana to start without OIDC initially
- Configure OIDC dynamically after secret creation

### Workaround

Manually trigger keycloak-config Job:

```bash
kubectl create job --from=job/keycloak-config keycloak-config-manual -n keycloak
kubectl wait --for=condition=complete job/keycloak-config-manual -n keycloak
```

Then restart Grafana:

```bash
kubectl rollout restart deployment/grafana -n observability
```

### Additional Context

- Similar pattern works for `kagenti-ui-oauth-config` Job
- May need to check if keycloak-config Job RBAC has permissions for observability namespace
- Secret should contain: `client_id`, `client_secret`, `issuer_url`

### Files Affected

- `components/02-observability/grafana/deployment.yaml` (references secret)
- `components/01-platform/keycloak/post-install-job.yaml` (should create secret)
- `components/01-platform/keycloak/kustomization.yaml` (sync wave)

---

## Issue 4: Keycloak Admin Credentials Cross-Namespace Access

**Repository**: `kagenti/kagenti-demo-deployment`
**Labels**: `security`, `enhancement`, `keycloak`

### Title
Platform components have overly broad Keycloak admin access

### Description

The `oauth-secret-job` in platform namespaces requires Keycloak admin credentials to retrieve auto-generated OAuth client secrets via the Keycloak Admin API. Currently, we copy the `keycloak-initial-admin` secret from the `keycloak` namespace to platform namespaces (e.g., `kagenti-system`). This violates the **principle of least privilege** by granting full Keycloak admin access to platform components that only need to read client configurations.

### Current Implementation

**File**: `components/00-infrastructure/keycloak/copy-admin-secret-job.yaml`

The `copy-keycloak-admin-secret` Job:
1. Reads `keycloak-initial-admin` secret from `keycloak` namespace
2. Copies admin credentials to `kagenti-system` namespace
3. Allows `oauth-secret-job` to mount the secret and call Keycloak Admin API

**RBAC Permissions**:
- Read secret from `keycloak` namespace
- Create/update secrets in `kagenti-system` namespace

**Why This Works**:
- Kubernetes doesn't allow cross-namespace secret mounts
- Jobs need credentials mounted as environment variables
- Simple solution for development/Kind environments

### Security Concern

**Overly Broad Permissions**:
- Platform components get **full Keycloak admin access** (create realms, delete users, etc.)
- They only need: `view-clients` and `view-realm` permissions
- Admin credentials exposed in multiple namespaces increases attack surface

**Risk Assessment**:
- ⚠️ **Medium Risk** for development/Kind clusters
- 🔴 **High Risk** for production environments
- Acceptable for local testing, **must be addressed before production**

### Better Approach (Future Enhancement)

**Option 1: Keycloak Service Account with Minimal Permissions** (Recommended)

1. Create a dedicated Keycloak service account:
   ```yaml
   # In realm-import-kagenti.yaml
   clients:
     - clientId: oauth-secret-reader
       name: "OAuth Secret Reader Service Account"
       serviceAccountsEnabled: true
       clientAuthenticatorType: client-secret
   ```

2. Grant only necessary roles:
   ```yaml
   # Assign minimal roles to service account
   serviceAccountClientRoles:
     realm-management:
       - view-clients
       - view-realm
   ```

3. Update `oauth-secret-job` to use service account credentials instead of admin credentials

**Option 2: External Secrets Operator** (Production)

- Store client secrets in HashiCorp Vault or AWS Secrets Manager
- Use External Secrets Operator to sync secrets to Kubernetes
- No credentials in-cluster at all

**Option 3: Keycloak Operator Enhancement**

- Request feature in Keycloak Operator to create Kubernetes secrets for client credentials
- Eliminates need for manual secret retrieval

### Impact

**Current State**:
- ✅ Works correctly for development
- ✅ Follows GitOps workflow
- ⚠️ Security posture degraded
- ❌ Not suitable for production

**After Fix**:
- ✅ Minimal permissions (least privilege)
- ✅ Reduced attack surface
- ✅ Production-ready security
- ✅ Maintains GitOps workflow

### Reproduction Steps

1. Deploy platform: `argocd app sync keycloak platform`
2. Check copied secret: `kubectl get secret keycloak-initial-admin -n kagenti-system -o yaml`
3. Decode credentials: `kubectl get secret keycloak-initial-admin -n kagenti-system -o jsonpath='{.data.password}' | base64 -d`
4. Observe: Full admin credentials available to platform namespace

### Environment

- **Cluster**: kind-kagenti-demo
- **Keycloak Operator**: v26.0.7
- **Affected Namespaces**: kagenti-system (future: observability for Grafana)

### Proposed Solution

**Phase 1: Document and Track** (Completed)
- ✅ Document security concern in ISSUES.md
- ✅ Add comments in code explaining temporary approach
- ✅ Mark as acceptable for development only

**Phase 2: Implement Service Account** (Future)
1. Update `realm-import-kagenti.yaml` with service account client
2. Create `oauth-secret-reader-credentials` secret (manual or Job)
3. Update `oauth-secret-job` to use service account instead of admin
4. Remove `copy-admin-secret-job`
5. Update RBAC to remove admin secret access

**Phase 3: Production Hardening** (Production Deployment)
- Evaluate External Secrets Operator
- Integrate with enterprise secrets management (Vault, AWS Secrets Manager)
- Implement secret rotation

### Workaround

**Acceptable for**:
- Local development with Kind
- Non-production environments
- Trusted single-user clusters

**NOT acceptable for**:
- Production deployments
- Multi-tenant environments
- Security compliance requirements (SOC 2, PCI-DSS, etc.)

### Additional Context

**References**:
- NERC OCP Pattern: https://github.com/OCP-on-NERC/nerc-ocp-config
- Keycloak Admin API: https://www.keycloak.org/docs-api/latest/rest-api/
- Principle of Least Privilege: https://en.wikipedia.org/wiki/Principle_of_least_privilege
- External Secrets Operator: https://external-secrets.io/

**Related Files**:
- `components/00-infrastructure/keycloak/copy-admin-secret-job.yaml` (implements copy)
- `components/01-platform/kagenti-ui/oauth-secret-job.yaml` (consumes admin credentials)
- `components/00-infrastructure/keycloak/realm-import-kagenti.yaml` (defines OAuth clients)

**Decision Log**:
- 2025-11-11: Chose simple cross-namespace copy approach for development velocity
- Priority: Ship functional platform → Iterate on security hardening
- Tracked in: ISSUES.md Issue #4

---

## Summary of Issues

| Issue | Repository | Priority | Status | Workaround Available |
|-------|------------|----------|--------|---------------------|
| kagenti-operator image not published | kagenti/kagenti-operator | P0 Critical | Open | ✅ Yes (use platform-operator only) |
| SPIRE CRDs missing from Helm chart | spiffe/helm-charts-hardened | P1 High | Open | ✅ Yes (manual kubectl apply) |
| Grafana OIDC secret missing | kagenti/kagenti-demo-deployment | P2 Medium | Open | ✅ Yes (manual Job trigger) |
| Keycloak admin credentials cross-namespace | kagenti/kagenti-demo-deployment | P2 Medium | Open | ✅ Yes (acceptable for dev) |
| Keycloak Operator --optimized flag issue | kagenti/kagenti-demo-deployment | P1 High | Open | ✅ Yes (vanilla StatefulSet) |

---

**Instructions**:
1. Copy each issue section above
2. Create new issue in the appropriate GitHub repository
3. Paste the content
4. Adjust formatting if needed for repository-specific templates
5. Submit the issue
6. Link the issue URL back to this file for tracking
