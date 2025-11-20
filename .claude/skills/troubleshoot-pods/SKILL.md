---
name: troubleshoot-pods
description: Troubleshoot pod issues - CrashLoopBackOff, ImagePullBackOff, connectivity, mTLS, and common pod failures in Kubernetes
---

# Troubleshoot Pods Skill

## When to Use

- Pods in CrashLoopBackOff, ImagePullBackOff, Error state
- Pod connectivity issues
- mTLS/network problems
- Service not accessible

## Common Pod Issues

### CrashLoopBackOff

```bash
# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check events
kubectl describe pod <pod-name> -n <namespace>

# Common causes: Application error, missing config, dependency unavailable
```

### ImagePullBackOff

```bash
# Check image availability in Kind
docker exec kagenti-demo-control-plane crictl images | grep <image>

# Load image if missing
./scripts/kind/04-load-agent-images.sh load

# Check pod events
kubectl describe pod <pod-name> -n <namespace> | grep -A10 "Events"
```

### Pending

```bash
# Check scheduling issues
kubectl describe pod <pod-name> -n <namespace>

# Common causes: Insufficient resources, unbound PVC, node selector
```

## Connectivity Testing

### Debug Pod (With Istio)

```bash
kubectl run debug-curl -n <namespace> \
  --image=curlimages/curl:latest \
  --restart=Never --rm -it -- sh

# Inside pod: Test service
curl http://<service-name>.<namespace>.svc:PORT
```

### Debug Pod (Without Istio)

```bash
kubectl run debug-curl -n <namespace> \
  --image=curlimages/curl:latest \
  --labels="sidecar.istio.io/inject=false" \
  --restart=Never --rm -it -- sh
```

## mTLS/Istio Issues

### TLS WRONG_VERSION_NUMBER

**Error**: `upstream connect error...TLS error: WRONG_VERSION_NUMBER`

**Cause**: STRICT mTLS + service expects plain HTTP

**Fix**: Add PERMISSIVE mTLS policy:
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: <service>-permissive
  namespace: <namespace>
spec:
  selector:
    matchLabels:
      app: <service>
  mtls:
    mode: PERMISSIVE
```

### Check mTLS Status

```bash
# Verify sidecar injection (should show 2/2)
kubectl get pods -n <namespace>

# Check namespace istio-injection
kubectl get namespace <namespace> -o jsonpath='{.metadata.labels.istio-injection}'

# Check mTLS policies
kubectl get peerauthentication -A

# Debug specific pod
istioctl x describe pod <pod-name> -n <namespace>
```

## Service Not Accessible

```bash
# 1. Check pod status
kubectl get pods -n <namespace> -l app=<service>

# 2. Check service endpoints
kubectl get endpoints -n <namespace> <service-name>

# 3. Check HTTPRoute/Gateway
kubectl get httproute -n <namespace>
kubectl describe httproute <route-name> -n <namespace>

# 4. Test from inside cluster
kubectl run test-curl -n <namespace> --image=curlimages/curl --rm -it \
  -- curl http://<service>.<namespace>.svc:PORT
```

## Resource Issues

```bash
# Check resource usage
kubectl top pods -n <namespace>

# Check limits
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Limits:"

# Check for OOM kills
kubectl get events -n <namespace> | grep OOM
```

## Related Skills

- **platform-health**: Overall health checks
- **investigate-incident**: Full RCA workflow
- **check-logs**: Query logs for errors

🤖 Generated with [Claude Code](https://claude.com/claude-code)
