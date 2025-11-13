# Deployment Issues Report - 2025-11-11

**Status**: Multiple deployment failures detected
**Impact**: Kind cluster deployment script fails at steps 5-6
**Priority**: HIGH - Blocks deployment

---

## Issues Detected

### Issue 1: kubectl --enable-helm Flag Not Supported ❌

**Symptom**:
```bash
error: unknown flag: --enable-helm
See 'kubectl apply --help' for usage.
```

**Details**:
- kubectl version: v1.34.1
- kustomize version: v5.7.1
- The `--enable-helm` flag was removed or never existed in kubectl

**Root Cause**:
The deployment script `scripts/deploy/deploy-kind.sh` is using `kubectl apply --enable-helm`, but this flag doesn't exist in the current kubectl version.

**Impact**:
- Deployment fails at Step 6/7 (Deploying Kagenti stack)
- Kustomize with Helm integration doesn't work
- Cannot deploy platform components

**Fix**:
Option 1: Use `kubectl kustomize` separately then apply:
```bash
# Instead of:
kubectl apply --enable-helm -k overlays/kind-local/

# Use:
kubectl kustomize --enable-helm overlays/kind-local/ | kubectl apply -f -
```

Option 2: Use `kustomize` CLI directly:
```bash
kustomize build --enable-helm overlays/kind-local/ | kubectl apply -f -
```

**Files to Update**:
- `scripts/deploy/deploy-kind.sh` - Line ~150-160 (Kagenti stack deployment)

---

### Issue 2: Gateway HTTPS Listener Missing TLS Mode ❌

**Symptom**:
```bash
The Gateway "external-gateway" is invalid:
spec.listeners: Invalid value: "array": tls mode must be Terminate for protocol HTTPS
```

**Details**:
- Gateway API version: v1.2.1
- Istio version: 1.24.2
- Protocol: HTTPS listener configured without TLS termination mode

**Root Cause**:
Gateway HTTPS listener must specify `tls.mode: Terminate` when using protocol HTTPS.

**Impact**:
- Gateway creation fails
- No HTTPS ingress for services
- Deployment fails at Step 5/7

**Fix**:
Update gateway configuration to specify TLS mode:

```yaml
# Current (broken):
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external-gateway
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      protocol: HTTPS
      port: 9443
      # Missing TLS configuration!

# Fixed:
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external-gateway
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      protocol: HTTPS
      port: 9443
      tls:
        mode: Terminate  # Required for HTTPS!
        certificateRefs:
          - name: external-gateway-cert
            kind: Secret
```

**Alternative Fix** (for local development without TLS):
```yaml
# Use HTTP instead of HTTPS for local dev
listeners:
  - name: http
    protocol: HTTP
    port: 8080
```

**Files to Update**:
- `components/01-infrastructure/istio/gateway.yaml` (or similar)
- `overlays/kind-local/gateway-patch.yaml` (if exists)

**Source**: [Gateway API TLS Configuration](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.GatewayTLSConfig)

---

### Issue 3: Gateway Readiness Timeout ❌

**Symptom**:
```bash
error: timed out waiting for the condition on gateways/external-gateway
```

**Details**:
- Timeout: Default kubectl wait timeout (likely 30-60s)
- Gateway status: Not ready due to TLS configuration error

**Root Cause**:
Gateway cannot become ready because of Issue #2 (TLS mode missing).

**Impact**:
- Deployment hangs at Step 5/7
- Script fails with timeout error

**Fix**:
Fix Issue #2 above. Once TLS mode is specified correctly, gateway will become ready.

**Verification**:
```bash
# Check gateway status
kubectl get gateway external-gateway -n istio-system -o yaml

# Look for status conditions
kubectl describe gateway external-gateway -n istio-system
```

---

### Issue 4: Prometheus Not Deployed ⚠️

**Symptom**:
```bash
⚠ Prometheus not found - Grafana datasource will fail
```

**Details**:
- Expected namespace: `observability` or `monitoring`
- Grafana expects Prometheus datasource

**Root Cause**:
Prometheus is either:
1. Not included in the Kustomize deployment
2. Not yet deployed due to earlier failures
3. Configured in a different namespace

**Impact**:
- Warning only (not blocking)
- Grafana won't have metrics datasource
- Cannot view metrics in Grafana dashboards

**Fix**:
Add Prometheus to deployment or verify it's included:

```bash
# Check if Prometheus exists
kubectl get pods -A | grep prometheus

# If missing, add to kustomization.yaml:
# overlays/kind-local/kustomization.yaml
resources:
  - ../../components/02-observability/prometheus/
```

**Note**: This is a warning, not a critical error. Fix after resolving Issues #1 and #2.

---

## Deployment Timeline

All three deployment attempts show identical failure patterns:

### Bash 461384
- ✅ Steps 1-4: Prerequisites, cluster, Gateway API, Istio (SUCCESS)
- ⚠️  Step 5: Gateway creation (WARNING - TLS mode error)
- ❌ Step 6: Kustomize deployment (FAILED - kubectl flag error)

### Bash 947e7c
- ✅ Steps 1-4: SUCCESS
- ❌ Step 5: Gateway creation (FAILED - invalid TLS config)
- ⏹️ Step 6: Not reached

### Bash 9c0aca
- ✅ Steps 1-4: SUCCESS
- ❌ Step 5: Gateway readiness timeout (FAILED - 60s timeout)
- ⏹️ Step 6: Not reached

---

## Immediate Action Items

### Priority 1: Fix Gateway TLS Configuration

**Task**: Update Gateway YAML to specify TLS mode

**Steps**:
1. Find Gateway configuration file
   ```bash
   grep -r "kind: Gateway" components/ overlays/
   ```
2. Add TLS mode specification
3. Test with:
   ```bash
   kubectl apply -f <gateway-file>
   kubectl wait --for=condition=Programmed gateway/external-gateway --timeout=60s
   ```

---

### Priority 2: Fix kubectl Command

**Task**: Update deployment script to use correct kubectl/kustomize syntax

**Steps**:
1. Edit `scripts/deploy/deploy-kind.sh`
2. Replace `kubectl apply --enable-helm` with:
   ```bash
   kubectl kustomize --enable-helm overlays/kind-local/ | kubectl apply -f -
   ```
3. Test deployment

---

### Priority 3: Add Prometheus (Optional)

**Task**: Ensure Prometheus is included in deployment

**Steps**:
1. Verify Prometheus component exists: `ls components/02-observability/prometheus/`
2. Add to kustomization if missing
3. Verify after fixing Issues #1 and #2

---

## Testing Plan

After fixes:

1. **Clean slate test**:
   ```bash
   # Delete existing cluster
   kind delete cluster --name kagenti-demo

   # Run deployment
   ./scripts/deploy/deploy-kind.sh
   ```

2. **Verify Gateway**:
   ```bash
   kubectl get gateway -A
   kubectl describe gateway external-gateway -n istio-system
   ```

3. **Verify all pods running**:
   ```bash
   kubectl get pods -A
   ```

4. **Test HTTPRoute connectivity**:
   ```bash
   kubectl get httproute -A
   ```

---

## Related Documentation

This report complements the newly created documentation:
- [Quick Start Guide](docs/00-getting-started/quick-start.md)
- [Troubleshooting](docs/00-getting-started/quick-start.md#troubleshooting)

Consider adding these issues to the troubleshooting section once resolved.

---

## Environment Details

- **kubectl**: v1.34.1
- **kustomize**: v5.7.1
- **helm**: v3.18.6+gb76a950
- **kind**: (version not shown in logs)
- **Istio**: 1.24.2 (with ambient mode)
- **Gateway API**: v1.2.1
- **Node**: kindest/node:v1.34.0

---

**Report Generated**: 2025-11-11
**Generated By**: Claude Code (Automated Analysis)
**Status**: Open - Requires Fixes
