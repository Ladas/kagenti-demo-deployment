# Production Issues Found - 2025-11-08

This document tracks production-grade issues discovered during the ArgoCD GitOps architecture verification.

## Status: BLOCKED - Critical Issues Found

### Issue 1: CRITICAL - Duplicate Tekton Pipeline ConfigMaps

**Severity**: CRITICAL
**Status**: NOT PRODUCTION-READY
**Impact**: Resource duplication, ArgoCD SharedResourceWarnings

**Description**:
Both `kagenti-operator` and `platform-operator` Helm charts deploy identical Tekton pipeline ConfigMaps to the same namespace (`kagenti-system`), causing resource conflicts.

**Duplicate Resources**:
- `ConfigMap/check-subfolder-step`
- `ConfigMap/github-clone-step`
- `ConfigMap/kaniko-docker-build-step`
- `ConfigMap/kaniko-docker-build-step-external`
- `ConfigMap/kaniko-docker-build-step-local`
- `ConfigMap/pipeline-template-dev`
- `ConfigMap/pipeline-template-dev-external`
- `ConfigMap/pipeline-template-dev-local`

**Root Cause**:
Both operator charts contain identical Tekton pipeline templates without conditional rendering:
- `charts/kagenti-operator/templates/tekton/*.yaml`
- `charts/platform-operator/templates/tekton/*.yaml`

**Evidence**:
```bash
$ argocd app get kagenti-operator --port-forward --port-forward-namespace argocd --grpc-web
Conditions:
SharedResourceWarning  ConfigMap/check-subfolder-step is part of applications argocd/kagenti-operator and platform-operator
SharedResourceWarning  ConfigMap/github-clone-step is part of applications argocd/kagenti-operator and platform-operator
...
```

**Solutions**:

1. **Short-term (LOCAL DEPLOYMENT ONLY)**:
   - Remove `kagenti-operator` Application
   - Keep only `platform-operator` which deploys all necessary CRDs and pipelines
   - Document this as temporary workaround

2. **Long-term (UPSTREAM FIX REQUIRED)**:
   - File issue in `kagenti/kagenti-operator` repository
   - Add Helm value to disable Tekton templates (e.g., `tekton.enabled: false`)
   - Wrap templates in conditional: `{{- if .Values.tekton.enabled }}`
   - Deploy Tekton pipelines from ONE operator only

**Workaround Applied**:
- Removed `kagenti-operator.yaml` from `argocd/applications/helm/kustomization.yaml`
- platform-operator provides ALL required CRDs (Agent, AgentBuild, AgentCard, Platform, Component)

---

### Issue 2: CRITICAL - kagenti-operator Image Not Available

**Severity**: CRITICAL
**Status**: BLOCKER
**Impact**: Pod ImagePullBackOff, operator non-functional

**Description**:
The kagenti-operator pod fails to start due to missing container image.

**Error**:
```bash
$ kubectl get pods -n kagenti-system
NAME                                             READY   STATUS             RESTARTS   AGE
kagenti-controller-manager-7bbfb76c6-twm86       0/1     ImagePullBackOff   0          20h

$ kubectl describe pod kagenti-controller-manager-7bbfb76c6-twm86 -n kagenti-system
Events:
  Warning  Failed   Error: ImagePullBackOff
  Normal   Pulling  Pulling image "ghcr.io/kagenti/kagenti-operator/kagenti-operator:0.2.0-alpha.15"
```

**Investigation**:
- Release `v0.2.0-alpha.15` exists in GitHub releases
- Container package NOT found at `ghcr.io/kagenti/kagenti-operator/kagenti-operator:0.2.0-alpha.15`
- Package may be private, not published, or at different path

**Root Cause**:
- Image not published to GHCR during release process
- OR image path mismatch between chart and CI/CD
- OR image requires authentication

**Solutions**:

1. **Verify Image Exists**:
   ```bash
   docker pull ghcr.io/kagenti/kagenti-operator/kagenti-operator:0.2.0-alpha.15
   ```

2. **Check CI/CD Pipeline**:
   - Review `.github/workflows/*.yaml` in kagenti-operator repo
   - Verify image is being pushed to GHCR during release
   - Check if packages are public or require authentication

3. **Use Working Image**:
   - Identify last working image tag
   - Update ArgoCD Application to use known-good tag

**Workaround Applied**:
- Removed kagenti-operator Application entirely (also resolves Issue 1)
- platform-operator provides all required CRDs

---

### Issue 3: WARNING - Tekton CRD Shared Resources

**Severity**: WARNING
**Status**: NEEDS INVESTIGATION
**Impact**: ArgoCD SharedResourceWarnings, potential conflicts

**Description**:
Tekton CRDs are being managed by multiple ArgoCD Applications.

**Evidence**:
```bash
$ argocd app get tekton
Conditions:
SharedResourceWarning  CustomResourceDefinition/customruns.tekton.dev is part of applications argocd/tekton and default
SharedResourceWarning  CustomResourceDefinition/pipelineruns.tekton.dev is part of applications argocd/tekton and default
SharedResourceWarning  CustomResourceDefinition/pipelines.tekton.dev is part of applications argocd/tekton and default
...
```

**Root Cause**:
- Unknown "default" application also deploying Tekton CRDs
- Possibly from old infrastructure deployment

**Investigation Needed**:
```bash
# Find which application is the "default" one
argocd app list | grep -i tekton
kubectl get applications -A -o yaml | grep -C 10 "tekton"
```

**Solution**:
1. Identify the "default" application
2. Remove duplicate Tekton CRD deployment
3. Ensure Tekton CRDs deployed by `tekton` Application only

---

## Recommendations

### Immediate Actions (Local Development):

1. ✅ Remove `kagenti-operator` Application (resolves Issues 1 & 2)
2. ⏳ Investigate Tekton CRD duplication (Issue 3)
3. ⏳ Verify platform-operator provides all required functionality
4. ⏳ Test Agent CR creation with only platform-operator running

### Upstream Actions Required:

1. **kagenti-operator Repository**:
   - Fix: Make Tekton templates conditional
   - Fix: Publish container images to GHCR during releases
   - Add: Helm value `tekton.enabled: false` to disable pipeline templates
   - Document: Which operator should deploy Tekton pipelines

2. **Documentation**:
   - Clarify: When to use kagenti-operator vs platform-operator
   - Document: Whether both operators are intended to coexist
   - Specify: Which operator owns Tekton pipeline templates

---

## Production Readiness Checklist

- [ ] No resource duplications (SharedResourceWarnings)
- [ ] All container images available and tested
- [ ] All pods Running with 1/1 Ready
- [ ] No ImagePullBackOff or CrashLoopBackOff errors
- [ ] All CRDs managed by single authoritative source
- [ ] RBAC properly scoped
- [ ] Resource requests/limits set
- [ ] Health checks configured
- [ ] GitOps sync working for all Applications

**Current Status**: ❌ NOT PRODUCTION-READY

---

## Testing Plan

After applying workarounds:

1. Deploy platform-operator only
2. Verify all CRDs present:
   ```bash
   kubectl get crds | grep -E "agent|platform|component"
   ```
3. Create test Agent CR:
   ```bash
   kubectl apply -f examples/agent-test.yaml
   ```
4. Verify AgentBuild pipeline runs
5. Check for any remaining SharedResourceWarnings
6. Deploy full platform (Waves 15, 20, 25)
7. Validate end-to-end functionality

---

**Last Updated**: 2025-11-08
**Documented By**: Claude Code
**Next Review**: After upstream fixes merged
