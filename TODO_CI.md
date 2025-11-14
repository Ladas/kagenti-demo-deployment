# CI/CD Improvement Tasks

**Last Updated**: 2025-11-14

## Current Status

### ✅ Completed
1. **Operator Applications Creation** - All 17 Applications now created in CI (was 14)
   - Moved operator Applications from `kustomize/` to `base/` directory
   - Both kagenti-operator and platform-operator reach Healthy status
   - Discovered monorepo structure: `Ladas/kagenti-operator/{kagenti-operator,platform-operator}/config/default`

2. **Image Loading** - Operator images load successfully in CI
   - Fixed grep filter bug causing false failures
   - Tar file export/import working correctly

3. **REQUIRED_APPS List** - Removed non-existent "infrastructure" app

### 🔄 In Progress

#### CI Run #19367994555 Analysis
- **Status**: Failed (but operators working!)
- **Apps Created**: 17/17 ✅
- **Operators**: Both Healthy ✅
- **Issue**: Other apps failing health checks (timing-related)

### ❌ Remaining Issues

#### 1. Timing Issues - Apps Not Ready When Tests Run
**Problem**: Tests run before applications finish deploying

**Failed Apps in Latest Run**:
- gateway-api
- istio-base
- istiod
- keycloak
- keycloak-operator
- kagenti-platform-operator (marked unhealthy in test, but logs show Healthy)

**Root Cause**:
- Intelligent wait loop may be exiting too early
- Some apps marked as "Progressing" when tests run
- Need to wait for Healthy status, not just Synced

**Solution Options**:
1. Increase wait timeout (currently 10 minutes)
2. Add per-app readiness checks
3. Wait for ALL critical apps to be Healthy before running tests
4. Add retry logic to test execution

#### 2. Test Report Shows APP_FAILED=0 But Tests Actually Failed
**Problem**: Parse step shows `APP_FAILED=0` but tests failed

**Evidence**:
```
APP_FAILED=$(jq -r '.summary.failed // 0' app-state-report.json)
APP_FAILED=0
```

Yet pytest output shows:
```
FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[gateway-api]
FAILED tests/validation/test_app_state.py::TestArgocdAppState::test_critical_app_healthy[istiod]
...
```

**Investigation Needed**:
- Check if app-state-report.json is being generated correctly
- Verify jq parsing logic
- Ensure pytest JSON report format is correct

#### 3. GitHub PR Comment Permission Error
**Error**: `HttpError: Resource not accessible by integration`

**Context**: Workflow tries to comment on PR but lacks permissions

**Solution**:
- Update workflow permissions to allow PR comments
- Or remove PR comment step if not needed

## Action Items

### Priority 1: Fix Timing Issues
- [ ] Review wait loop logic in `.github/workflows/app-state-validation.yml`
- [ ] Ensure wait continues until ALL critical apps are Healthy
- [ ] Add detailed logging of app states during wait
- [ ] Consider increasing timeout from 10 to 15 minutes

### Priority 2: Fix Test Result Parsing
- [ ] Investigate app-state-report.json generation
- [ ] Verify pytest JSON report plugin configuration
- [ ] Test jq parsing logic locally
- [ ] Add error handling for missing report files

### Priority 3: Fix PR Comment Permission
- [ ] Add `pull-requests: write` permission to workflow
- [ ] Or remove comment step if not critical

### Priority 4: Documentation
- [ ] Document operator monorepo structure discovery
- [ ] Update ArgoCD application architecture docs
- [ ] Add troubleshooting guide for CI issues

## Recent Commits

1. `dab2f76` - Remove non-existent "infrastructure" from REQUIRED_APPS
2. `08cc197` - Fix grep filter causing false failures in image loading
3. `ffb521f` - **KEY FIX**: Move operator Applications to base/ directory
4. `f2aad7c` - Incorrect URL "fix" (reverted in next commit)
5. `107caaa` - Revert to correct operator overlay URLs

## CI Run History

| Run ID | Status | Apps Created | Operators Healthy | Notes |
|--------|--------|--------------|-------------------|-------|
| 19366497819 | Failed | 17/17 ✅ | Degraded | Apps created but operators crashing |
| 19367233425 | Failed | 17/17 ✅ | Failed | Broke URLs - all apps failed |
| 19367994555 | Failed | 17/17 ✅ | **Healthy** ✅ | Timing issues only |

## Next Steps

1. Analyze wait loop to understand why it exits before apps are healthy
2. Check logs from run #19367994555 for exact timing of when tests ran vs when apps became healthy
3. Implement fix for wait logic
4. Test locally with quick-redeploy.sh to verify timing
5. Push fix and monitor new CI run
