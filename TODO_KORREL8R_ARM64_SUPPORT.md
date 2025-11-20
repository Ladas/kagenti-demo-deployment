# TODO: Korrel8r ARM64 Support

**Status**: BLOCKED - Requires upstream ARM64 image builds
**Priority**: MEDIUM (workaround available via Grafana native correlation)
**Created**: 2025-11-19
**Last Updated**: 2025-11-19

---

## Problem Statement

**Korrel8r does not provide ARM64 container images**, causing CrashLoopBackOff when deployed on ARM64 Kubernetes clusters (Apple Silicon development environments, AWS Graviton, Azure Ampere).

**Root Cause**:
- Korrel8r images on Quay.io are AMD64-only
- Running AMD64 images via QEMU emulation on ARM64 causes Go GC corruption
- Result: `runtime.gcBgMarkWorker()` panic during initialization

**Impact**:
- ⚠️ Signal correlation (trace↔log↔metric↔alert) not available via Korrel8r
- ✅ Workaround: Grafana native correlation works (trace↔log only)
- ⚠️ Missing: Advanced graph-based correlation features

---

## Investigation Results (2025-11-19)

### 1. Quay.io Image Availability ❌

**Verification Commands**:
```bash
# Check manifest for multi-arch support
docker manifest inspect quay.io/korrel8r/korrel8r:latest
# Result: ❌ Single-platform image (no manifest list)

# Verify architecture
docker inspect quay.io/korrel8r/korrel8r:latest --format '{{.Architecture}}'
# Result: amd64

# Attempt ARM64 pull
docker pull quay.io/korrel8r/korrel8r:latest --platform linux/arm64
# Result: ❌ Error - "wanted linux/arm64, actual: linux/amd64"
```

**Conclusion**: ❌ **NO ARM64 images available** on Quay.io

### 2. Upstream GitHub Issues ❌

**Search Conducted**: 100 most recent issues for keywords:
- `arm64`, `aarch64`, `apple silicon`, `m1`, `m2`, `m3`
- `multi-arch`, `multiarch`, `platform`, `architecture`

**Result**: ❌ **NO existing GitHub issues** requesting ARM64 support

**False Positive Found**:
- Issue #289: About trace correlation features (NOT ARM64)

### 3. Build System Analysis

**Containerfile** (`github.com/korrel8r/korrel8r/main/Containerfile`):

```dockerfile
# Stage 1: Builder (Red Hat UBI9 Go toolset)
FROM registry.access.redhat.com/ubi9/go-toolset AS builder

# Build environment
ENV CGO_ENABLED=1
ENV GOOS=linux
ENV GOFLAGS="-mod=readonly -tags=strictfipsruntime,openssl"
ENV GOEXPERIMENT=strictfipsruntime

# Build command
RUN go build -tags netgo ./cmd/korrel8r

# Stage 2: Runtime (Red Hat UBI9 minimal)
FROM registry.access.redhat.com/ubi9/ubi-minimal
```

**Issues**:
- ❌ No `GOARCH` specified (defaults to build platform)
- ❌ No `TARGETOS`/`TARGETARCH` variables (needed for multi-arch)
- ⚠️ CGO_ENABLED=1 (requires cross-compilation toolchain)
- ⚠️ FIPS-specific flags (may need ARM64 validation)

**Opportunities**:
- ✅ Red Hat UBI9 base images already support ARM64
- ✅ Go has excellent cross-compilation support

**Makefile** (`github.com/korrel8r/korrel8r/main/Makefile`):

```makefile
# Image building
IMGTOOL ?= $(shell which podman || which docker)

image-build:
	$(IMGTOOL) build -t $(IMG) .
```

**Issues**:
- ❌ No buildx or multi-arch support
- ❌ No cross-compilation targets
- Uses standard single-platform build

---

## Build Difficulty Assessment

**Complexity**: ⭐⭐ **MEDIUM**

### Required Changes

**1. Containerfile Modifications**:
```dockerfile
# Add build arguments for multi-arch
ARG TARGETOS=linux
ARG TARGETARCH=amd64

# Update build environment
ENV GOOS=${TARGETOS}
ENV GOARCH=${TARGETARCH}
```

**2. Makefile Additions**:
```makefile
# Multi-arch build with buildx
.PHONY: image-build-multiarch
image-build-multiarch:
	docker buildx build --platform linux/amd64,linux/arm64 \
	  -t $(IMG) --push .
```

**3. Testing Requirements**:
- Verify CGO cross-compilation works for ARM64
- Test FIPS build flags on ARM64 platform
- Validate Red Hat UBI9 ARM64 base images

### Obstacles

- ⚠️ **CGO_ENABLED=1**: Requires ARM64 C compiler for cross-compilation
- ⚠️ **FIPS flags**: May have ARM64-specific behaviors (needs validation)
- ⚠️ **OpenSSL library**: Red Hat FIPS mode compatibility on ARM64

### Estimated Effort

- **Initial ARM64 build**: 1-2 days
- **FIPS validation/testing**: 1 week
- **Total**: ~2 weeks for production-ready ARM64 support

---

## Action Items

### Option A: Request ARM64 Support from Upstream ✅ **RECOMMENDED**

**Steps**:
1. Open GitHub issue on `github.com/korrel8r/korrel8r`
2. Use issue template below
3. Monitor for upstream response
4. Offer to contribute if maintainers are receptive

**GitHub Issue Template**:

```markdown
**Title**: Add ARM64/aarch64 support for Apple Silicon and ARM servers

**Description**:

Korrel8r currently only provides AMD64 container images on Quay.io, which causes
CrashLoopBackOff when running on ARM64 Kubernetes clusters (e.g., Apple Silicon
development environments, AWS Graviton, Azure Ampere).

**Current Behavior**:
- Quay.io images: `linux/amd64` only
- ARM64 deployment: CrashLoopBackOff (Go GC worker panic via QEMU emulation)
- Verified architectures: `docker inspect` shows `amd64` only

**Expected Behavior**:
- Multi-arch images on Quay.io: `linux/amd64`, `linux/arm64`
- Native ARM64 execution (no emulation)

**Requested Changes**:

1. **Containerfile**: Add multi-arch build arguments
   ```dockerfile
   ARG TARGETOS=linux
   ARG TARGETARCH=amd64
   ENV GOOS=${TARGETOS}
   ENV GOARCH=${TARGETARCH}
   ```

2. **Makefile**: Add buildx support
   ```makefile
   .PHONY: image-build-multiarch
   image-build-multiarch:
       docker buildx build --platform linux/amd64,linux/arm64 \
         -t $(IMG) --push .
   ```

3. **CI/CD**: Update build pipeline to publish multi-arch images

**Benefits**:
- ✅ Native ARM64 support (no QEMU emulation crashes)
- ✅ Compatibility with Apple Silicon Macs (M1/M2/M3/M4)
- ✅ Support for ARM-based cloud instances (AWS Graviton, Azure Ampere)
- ✅ Follows multi-arch pattern of similar projects (Grafana, Loki, Tempo)

**Technical Details**:
- Red Hat UBI9 base images already support ARM64 ✅
- CGO cross-compilation may need attention (currently `CGO_ENABLED=1`)
- FIPS-specific build flags may require ARM64 validation
- Go cross-compilation support is excellent

**Environment**:
- Host: macOS Apple Silicon (M-series)
- Kubernetes: Kind cluster (ARM64)
- Current workaround: Disabled Korrel8r, using Grafana native correlation

**References**:
- Quay.io repository: https://quay.io/repository/korrel8r/korrel8r
- Similar multi-arch projects: Grafana, Loki, Tempo (all support ARM64)
```

**Expected Timeline**:
- Issue response: 1-2 weeks
- Implementation: 2-4 weeks (if accepted)
- Release: Depends on release cycle

---

### Option B: Contribute ARM64 Support (if upstream responsive)

**Prerequisites**:
- Maintainer approval/interest in ARM64 support
- Access to ARM64 testing environment
- Familiarity with Go cross-compilation + CGO

**Steps**:
1. Fork `github.com/korrel8r/korrel8r`
2. Create feature branch: `feat/arm64-support`
3. Implement multi-arch build changes
4. Test on ARM64 platform (local or CI)
5. Validate FIPS mode on ARM64
6. Submit pull request with:
   - Containerfile modifications
   - Makefile buildx support
   - CI/CD pipeline updates (if applicable)
   - Documentation updates

**Testing Checklist**:
- [ ] AMD64 build still works (no regression)
- [ ] ARM64 build compiles successfully
- [ ] ARM64 runtime works (no GC panics)
- [ ] FIPS mode functional on ARM64
- [ ] CGO dependencies resolved for ARM64
- [ ] Integration tests pass on both architectures

---

### Option C: Local ARM64 Build (Development/Testing)

**Use Case**: Test ARM64 feasibility before upstream contribution

**Steps**:
```bash
# 1. Clone repository
git clone https://github.com/korrel8r/korrel8r.git
cd korrel8r

# 2. Modify Containerfile (add TARGETARCH)
cat > Containerfile.arm64 <<'EOF'
ARG TARGETOS=linux
ARG TARGETARCH=arm64

FROM registry.access.redhat.com/ubi9/go-toolset AS builder
ENV CGO_ENABLED=1
ENV GOOS=${TARGETOS}
ENV GOARCH=${TARGETARCH}
ENV GOFLAGS="-mod=readonly -tags=strictfipsruntime,openssl"
ENV GOEXPERIMENT=strictfipsruntime

COPY . .
RUN go build -tags netgo ./cmd/korrel8r

FROM registry.access.redhat.com/ubi9/ubi-minimal
COPY --from=builder /opt/app-root/src/korrel8r /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/korrel8r"]
EOF

# 3. Build ARM64 image
docker buildx build --platform linux/arm64 \
  -f Containerfile.arm64 \
  -t localhost:5001/korrel8r:arm64-test \
  --load .

# 4. Load to Kind cluster
kind load docker-image localhost:5001/korrel8r:arm64-test --name kagenti-demo

# 5. Test deployment
kubectl apply -f components/02-observability/korrel8r/
kubectl rollout restart deployment/korrel8r -n observability

# 6. Verify no CrashLoopBackOff
kubectl get pods -n observability -l app=korrel8r
kubectl logs -n observability deployment/korrel8r
```

**Risk**: Unsupported/untested configuration, may have FIPS issues

---

### Option D: Continue with Grafana Native Correlation (Current Status)

**Status**: ✅ **OPERATIONAL** (active workaround)

**Configuration**:
- Grafana datasource correlation configured:
  - **Loki → Tempo**: `derivedFields` extract `trace_id` from logs
  - **Tempo → Loki**: `tracesToLogsV2` links spans to log streams
- Dashboard correlation: Simple comparison chart
  - File: `components/02-observability/grafana/dashboards/loki-logs.json` (panel ID 14)
  - Shows: Error logs vs firing alerts (aggregate trends)

**Capabilities**:
- ✅ Trace → Log correlation
- ✅ Log → Trace correlation
- ❌ Log → Metric → Alert correlation (requires Korrel8r)
- ❌ Graph-based correlation queries (requires Korrel8r)

**Limitations**:
- Cannot query correlation graphs (e.g., "find all alerts related to this trace")
- Cannot traverse relationships (e.g., "trace → logs → metrics → alerts")
- Simple dashboard comparisons instead of dynamic correlation

---

## Timeline & Milestones

### Immediate (Week 1)
- [ ] Open GitHub issue requesting ARM64 support
- [ ] Monitor issue for upstream response
- [ ] Document issue URL in this file

### Short-term (1-2 months)
- [ ] If upstream accepts: Collaborate on implementation
- [ ] If upstream declines: Decide between local build vs workaround
- [ ] Test ARM64 build locally (Option C)

### Long-term (3+ months)
- [ ] Deploy Korrel8r ARM64 if available
- [ ] Migrate from Grafana native correlation
- [ ] Enable advanced correlation features (Phase 4.3)
- [ ] Document correlation workflows

---

## References

**Documentation**:
- Main tracking: `TODO_TRACING.md` (Phase 4: Korrel8r deployment)
- Architecture: `docs/04-observability/distributed-tracing.md`
- Grafana correlation: `components/02-observability/grafana/datasources.yaml`

**Upstream Resources**:
- GitHub repository: https://github.com/korrel8r/korrel8r
- Quay.io repository: https://quay.io/repository/korrel8r/korrel8r
- Documentation: https://korrel8r.github.io/korrel8r/

**Deployment Files**:
- Korrel8r manifests (disabled): `components/02-observability/korrel8r/`
- ConfigMap (correlation rules): `components/02-observability/korrel8r/configmap.yaml`
- Kustomization (commented out): `components/02-observability/kustomization.yaml` (lines 29-33)

**Related Issues**:
- Kind cluster architecture: ARM64 (aarch64) native
- Docker Desktop: ARM64 native on Apple Silicon
- Host: macOS with Rosetta 2 for x86_64 emulation

---

## Success Criteria

- [ ] ARM64 images available on Quay.io (linux/amd64 + linux/arm64)
- [ ] Korrel8r deployment successful on ARM64 Kind cluster (no CrashLoopBackOff)
- [ ] All correlation features functional (trace↔log↔metric↔alert)
- [ ] Integration tests passing on both AMD64 and ARM64
- [ ] Documentation updated with multi-arch deployment instructions

---

**Status**: Awaiting upstream response to ARM64 support request
**Next Action**: Open GitHub issue using template above
**Blocked By**: Upstream ARM64 image builds
**Workaround**: Grafana native correlation (functional but limited)
