# Operator Image Rebuild Instructions

## Problem Summary

The kagenti operator images are currently built for **ARM64** architecture, but GitHub Actions CI runners use **AMD64**. This causes the operators to crash with "exec format error" in CI.

**Evidence from CI run #19393467449**:
```
exec /manager: exec format error
```

**Verified locally**:
```bash
$ docker inspect localhost:5001/kagenti-operator:dev | jq '.[0].Architecture'
"arm64"  # ← Wrong architecture for CI!
```

## Solution: Rebuild for AMD64

You need to rebuild the operator images for AMD64 architecture so they work in CI.

---

## Option 1: Quick Fix - Rebuild Locally for AMD64 (Recommended)

This is the fastest way to unblock CI.

### Step 1: Navigate to Operator Repository

```bash
cd /Users/ladas/Projects/OCTO/research/ladas-kagenti-operator
```

### Step 2: Build kagenti-operator for AMD64

```bash
cd kagenti-operator

# Build for AMD64 using docker buildx
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t localhost:5001/kagenti-operator:dev \
  .

# Verify it's AMD64
docker inspect localhost:5001/kagenti-operator:dev | jq '.[0].Architecture'
# Should output: "amd64"
```

### Step 3: Build platform-operator for AMD64

```bash
cd ../platform-operator

# Build for AMD64 using docker buildx
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t localhost:5001/kagenti-platform-operator:dev \
  .

# Verify it's AMD64
docker inspect localhost:5001/kagenti-platform-operator:dev | jq '.[0].Architecture'
# Should output: "amd64"
```

### Step 4: Export New Images as Tar Files

```bash
cd ../../kagenti-demo-deployment

# Export the AMD64 images
./scripts/export-operator-images.sh
```

This will create:
- `.images/kagenti-operator-dev.tar` (AMD64 version)
- `.images/kagenti-platform-operator-dev.tar` (AMD64 version)

### Step 5: Commit and Push

```bash
git add .images/
git commit -m ":package: Rebuild operator images for AMD64 (fix CI architecture mismatch)

Problem: Operators built for ARM64 crash on AMD64 CI runners
- kagenti-operator: exec format error
- kagenti-platform-operator: exec format error

Solution: Rebuilt both operators for AMD64 using docker buildx
- Now compatible with GitHub Actions CI (AMD64)
- Verified architecture with docker inspect

Evidence: CI run #19393467449 crash logs
- tekton: Fixed by Kubernetes 1.28.0 upgrade ✅
- operators: Still failing with exec format error ❌

This commit fixes the operator architecture issue.
"

git push origin argocd-gitops-dev-phase-1
```

### Step 6: Verify CI Passes

Wait for new CI run to complete and verify operators start successfully.

---

## Option 2: Multi-Arch Builds (Better for Long-Term)

Build images for both ARM64 (local dev) and AMD64 (CI) using manifests.

### Create Multi-Arch Images

```bash
cd ladas-kagenti-operator/kagenti-operator

# Build and push multi-arch manifest
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t localhost:5001/kagenti-operator:dev \
  --push \
  .
```

**Note**: This requires a registry that supports manifests. For local Kind clusters, Option 1 is simpler.

---

## Option 3: Build in CI (Best Long-Term Solution)

Modify `.github/workflows/app-state-validation.yml` to build operators during CI:

```yaml
- name: Build operator images for CI
  if: steps.cluster_mode.outputs.mode == 'kind'
  run: |
    echo "Building operator images for AMD64..."
    
    # Clone operator repository
    git clone https://github.com/Ladas/kagenti-operator /tmp/kagenti-operator
    cd /tmp/kagenti-operator
    
    # Checkout correct branch
    git checkout fix/add-kagenti-operator-image-build
    
    # Build kagenti-operator
    cd kagenti-operator
    make docker-build IMG=localhost:5001/kagenti-operator:dev
    
    # Build platform-operator
    cd ../platform-operator
    make docker-build IMG=localhost:5001/kagenti-platform-operator:dev
    
    # Load into Kind cluster
    kind load docker-image localhost:5001/kagenti-operator:dev --name kagenti-demo
    kind load docker-image localhost:5001/kagenti-platform-operator:dev --name kagenti-demo
```

**Benefits**:
- No need to commit large tar files to git
- Always builds fresh with correct architecture
- Works for both AMD64 and ARM64 CI runners

**Drawbacks**:
- Slower CI runs (adds 2-5 minutes for builds)
- Requires operator repository to be public or accessible in CI

---

## Verification Steps

After rebuilding, verify the fix:

### 1. Check Local Image Architecture

```bash
docker inspect localhost:5001/kagenti-operator:dev | jq '.[0].Architecture'
# Should be: "amd64"

docker inspect localhost:5001/kagenti-platform-operator:dev | jq '.[0].Architecture'
# Should be: "amd64"
```

### 2. Check Tar File Architecture

```bash
cd kagenti-demo-deployment/.images

# Load and inspect
docker load -i kagenti-operator-dev.tar
docker inspect localhost:5001/kagenti-operator:dev | jq '.[0].Architecture'
# Should be: "amd64"
```

### 3. Monitor CI Run

After pushing, check the new CI run:
- Tekton should work ✅ (Kubernetes 1.28.0 fix)
- Operators should work ✅ (AMD64 fix)
- All apps should become Healthy ✅

---

## Current Status

**Completed**:
- ✅ Tekton Kubernetes version issue fixed (Kubernetes 1.28.0 upgrade)
- ✅ Root cause identified for operator crashes (ARM64 vs AMD64 mismatch)
- ✅ Debug logging added to capture crash logs
- ✅ Complete investigation documented in TODO_CI.md

**Remaining**:
- ❌ Rebuild operator images for AMD64
- ❌ Test in CI
- ❌ Verify all apps become Healthy

---

## Why This Happened

1. **Local Development**: You're on Apple Silicon (ARM64)
2. **Operator Build**: Operators built locally are ARM64
3. **Tar Export**: ARM64 images exported to `.images/` directory
4. **Git Commit**: ARM64 tar files committed to repository
5. **CI Deployment**: CI runs on AMD64, loads ARM64 images → crash!

The fix is simply to rebuild for the CI architecture (AMD64).

---

## Questions?

- Check `TODO_CI.md` for complete investigation timeline
- See crash logs in CI artifacts: `crash-debug-logs`
- Review commits:
  - `fce1b67`: Kubernetes 1.28.0 upgrade (Tekton fix)
  - `bdd0b4c`: Debug logging addition
  - Next: AMD64 operator rebuild

**Estimated time to rebuild**: 5-10 minutes
**Expected CI time after push**: 15-20 minutes
**Total time to fix**: ~30 minutes
