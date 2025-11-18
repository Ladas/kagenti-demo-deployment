# BUG REPORT: Webhook Certificate Validation Failure

**Date**: 2025-11-18
**Severity**: CRITICAL - Blocks all AgentBuild CRD creation
**Component**: kagenti-operator webhook validation
**Status**: UNRESOLVED

---

## Summary

AgentBuild CRD creation fails with misleading webhook certificate validation error despite all certificates being correctly configured.

## Error Message

```
Error from server (InternalError): error when creating "STDIN": Internal error occurred:
failed calling webhook "magentbuild.kb.io": failed to call webhook:
Post "https://kagenti-operator-webhook-service.kagenti-system.svc:443/mutate-agent-kagenti-dev-v1alpha1-agentbuild?timeout=10s":
tls: failed to verify certificate: x509: certificate is not valid for any names,
but wanted to match kagenti-operator-webhook-service.kagenti-system.svc
```

## Impact

- **Blocks**: All AgentBuild CRD creation
- **Affects**: Dynamic agent import via Tekton pipelines
- **Workaround**: None found (static manifests only)
- **Phase 0.5**: Cannot complete agent e2e testing

---

## Reproduction Steps

1. Deploy kagenti platform via ArgoCD/GitOps
2. Attempt to create AgentBuild CRD:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: agent.kagenti.dev/v1alpha1
   kind: AgentBuild
   metadata:
     name: test-build
     namespace: team1
   spec:
     mode: dev
     pipeline:
       namespace: kagenti-system
       parameters:
         - name: SOURCE_URL
           value: "https://github.com/redhat-et/agent-examples.git"
         - name: SOURCE_CONTEXT_DIR
           value: "a2a/weather_service"
     buildOutput:
       image: "test-agent"
       imageTag: "latest"
       imageRegistry: "localhost:5000"
   EOF
   ```
3. Observe webhook validation error

---

## Investigation Results

### ✅ Verified Components Working Correctly

#### 1. Certificate Exists and Ready

```bash
$ kubectl get certificate -n kagenti-system | grep kagenti-operator
kagenti-operator-serving-cert   True    webhook-server-cert   97m
```

**Status**: Ready (True)
**Secret**: `webhook-server-cert`
**Validity**: 90 days

#### 2. Certificate Has Correct SANs

```bash
$ kubectl get secret webhook-server-cert -n kagenti-system -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -text | grep -A 5 "Subject Alternative Name"
```

**Output**:
```
X509v3 Subject Alternative Name: critical
    DNS:kagenti-operator-webhook-service.kagenti-system.svc
    DNS:kagenti-operator-webhook-service.kagenti-system.svc.cluster.local
```

**✅ Certificate DOES have the required DNS SANs**

#### 3. Webhook Configuration Correct

```bash
$ kubectl get mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration \
  -o jsonpath='{.metadata.annotations}'
```

**Output**:
```json
{
    "cert-manager.io/inject-ca-from": "kagenti-system/kagenti-operator-serving-cert"
}
```

**✅ Cert-manager CA injection configured**

#### 4. CA Bundle Properly Injected

```bash
$ kubectl get mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | base64 -d | openssl x509 -noout -text \
  | grep -A 3 "Subject Alternative Name"
```

**Output**:
```
X509v3 Subject Alternative Name: critical
    DNS:kagenti-operator-webhook-service.kagenti-system.svc
    DNS:kagenti-operator-webhook-service.kagenti-system.svc.cluster.local
```

**✅ Webhook caBundle matches certificate SANs**

#### 5. Deployment Configured Correctly

```bash
$ kubectl get deployment kagenti-operator-controller-manager -n kagenti-system \
  -o yaml | grep -A 5 "volumeMounts:\|volumes:" | grep -A 3 "cert"
```

**Output**:
```yaml
- mountPath: /tmp/k8s-webhook-server/serving-certs
  name: cert
  readOnly: true
---
- name: cert
  secret:
    secretName: webhook-server-cert
```

**✅ Certificate secret mounted in operator pod**

### ❌ What's Broken

Despite ALL components being correctly configured, the error persists:

**Error says**: "certificate is not valid for any names"
**Reality**: Certificate HAS valid SANs for the exact service name

**This indicates**:
- Misleading error message OR
- Bug in webhook server certificate validation OR
- Kubernetes API server webhook validation issue OR
- Cert-manager/operator integration issue

---

## Attempted Fixes (All Failed)

### 1. Restart Operator Pod ❌
```bash
kubectl delete pod -n kagenti-system <kagenti-operator-pod>
```
**Result**: Error persisted

### 2. Delete and Recreate Webhook Configuration ❌
```bash
kubectl delete mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration
kubectl rollout restart deployment/kagenti-operator-controller-manager -n kagenti-system
```
**Result**: Webhook recreated with correct config, error persisted

### 3. Regenerate Certificate ❌
```bash
kubectl delete certificate kagenti-operator-serving-cert -n kagenti-system
kubectl wait --for=condition=Ready certificate/kagenti-operator-serving-cert -n kagenti-system
kubectl rollout restart deployment/kagenti-operator-controller-manager -n kagenti-system
```
**Result**: New certificate generated with same SANs, error persisted

---

## Environment

- **Cluster**: Kind v0.20+ (local development)
- **Kubernetes**: v1.27+
- **cert-manager**: Deployed via ArgoCD
- **kagenti-operator**: Deployed via ArgoCD/Helm
- **Platform**: macOS (Darwin 24.6.0)

### Relevant Component Versions

```bash
$ kubectl get deployment -n kagenti-system kagenti-operator-controller-manager \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Output needed from deployment

$ kubectl get deployment -n cert-manager cert-manager \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Output needed from deployment
```

---

## Diagnostic Commands

### Check Certificate Status
```bash
kubectl get certificate -n kagenti-system kagenti-operator-serving-cert -o yaml
kubectl describe certificate -n kagenti-system kagenti-operator-serving-cert
```

### Check Webhook Configuration
```bash
kubectl get mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration -o yaml
```

### Check Operator Logs
```bash
kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager -c manager --tail=100
```

### Verify Certificate SANs
```bash
kubectl get secret webhook-server-cert -n kagenti-system -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -text | grep -A 5 "Subject Alternative Name"
```

### Test AgentBuild Creation
```bash
# Use scripts/import-agents-via-ui.sh
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"
```

---

## Possible Root Causes

### Theory 1: Operator Webhook Server Bug
The operator's webhook server may not be correctly presenting the TLS certificate during the handshake, even though the certificate file is mounted correctly.

**Evidence**:
- Certificate file exists and has correct SANs
- Error message is misleading ("not valid for any names" when SANs exist)
- Multiple certificate regenerations don't fix the issue

### Theory 2: Kubernetes API Server Issue
The Kubernetes API server's webhook admission controller may have a bug in how it validates webhook certificates.

**Evidence**:
- Other webhooks (tekton, istio) work fine
- Only kagenti-operator webhook affected

### Theory 3: Cert-Manager Integration Issue
The cert-manager certificate generation or injection may have a subtle bug that causes validation failures despite certificates appearing correct.

**Evidence**:
- CA bundle is injected correctly
- Certificate appears valid when inspected
- Issue persists across certificate regenerations

### Theory 4: Deployment/ArgoCD Timing Issue
The operator may start before the certificate is fully available, caching an invalid state.

**Evidence**:
- Multiple restarts don't fix the issue
- Certificate ready before operator starts

---

## Workarounds

### Option 1: Temporary Disable Webhook for Testing (DEVELOPMENT ONLY)

**⚠️ WARNING**: This bypasses validation entirely. Use ONLY for development testing.

```bash
# 1. Check current failure policy
kubectl get mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration \
  -o jsonpath='{.webhooks[0].failurePolicy}'
# Output: Fail

# 2. Change to Ignore (allows requests to proceed even if webhook fails)
kubectl patch mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Ignore"}]'

# 3. Test AgentBuild creation
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"

# 4. RESTORE original policy after testing
kubectl patch mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Fail"}]'
```

**Risks**:
- Invalid AgentBuilds may be accepted
- Webhook mutations (defaulting, validation logic) are skipped
- NOT suitable for production or CI

**When to use**:
- Local development testing only
- To verify import script functionality
- To unblock Phase 0.5 testing temporarily

### Option 2: Disable Webhook Entirely (DEVELOPMENT ONLY)

**⚠️ EVEN MORE DANGEROUS**: Completely removes webhook validation.

```bash
# 1. Delete webhook configuration
kubectl delete mutatingwebhookconfigurations kagenti-operator-mutating-webhook-configuration

# 2. Test AgentBuild creation
./scripts/import-agents-via-ui.sh \
  "https://github.com/redhat-et/agent-examples.git" \
  "a2a/weather_service" \
  "weather-agent" \
  "team1"

# 3. Restore webhook (requires operator restart or ArgoCD sync)
argocd app sync kagenti-operator --port-forward --port-forward-namespace argocd --grpc-web
```

**Risks**:
- ALL webhook functionality lost
- No validation, no defaulting, no mutation
- May cause operator or platform issues

**NOT RECOMMENDED** - Use Option 1 instead

### Alternative: Static Agent Deployment
Use static Kubernetes manifests instead of AgentBuild CRDs:
- Deploy agents via ArgoCD Application
- Skip Tekton pipeline builds
- **Limitation**: No automated builds from Git repositories

---

## Next Steps

### For Platform Team

1. **Check operator logs during webhook call**:
   ```bash
   kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager \
     -c manager -f
   # Then trigger AgentBuild creation
   ```

2. **Compare with working webhook** (e.g., platform-operator):
   ```bash
   kubectl get mutatingwebhookconfigurations kagenti-mutating-webhook-configuration -o yaml
   kubectl get certificate -n kagenti-system kagenti-serving-cert -o yaml
   ```

3. **Test with minimal AgentBuild**:
   Create simplest possible AgentBuild to isolate the issue

4. **Check operator source code**:
   Review webhook server initialization and certificate loading

### For Users (Blocked)

**Phase 0.5 Status**: ❌ **BLOCKED**
- Cannot test agent import script
- Cannot complete e2e agent testing
- Can only proceed with documentation tasks

**Recommendation**:
- Report issue to kagenti-operator maintainers
- Request full platform redeployment test
- Consider static agent deployment as temporary workaround

---

## Related Files

- `scripts/import-agents-via-ui.sh` - Agent import script (blocked by this issue)
- `TODO_PHASE_0_5_STATUS.md` - Phase 0.5 progress tracking
- `TODO_monitoring_agents.md` - Phase 0.5 detailed tasks

---

## Update History

- **2025-11-18**: Initial investigation and bug report created
- **Attempts**: 3 different fix approaches, all unsuccessful
- **Status**: Awaiting platform team investigation or full redeployment
