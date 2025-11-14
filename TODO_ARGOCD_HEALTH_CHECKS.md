# TODO: ArgoCD Health Checks - Comprehensive Implementation Guide

**Date Created:** 2025-11-10
**Status:** Research Complete - Implementation Pending
**Priority:** HIGH

## Executive Summary

This document provides a comprehensive, ultra-deep analysis of ArgoCD health check patterns and best practices for the kagenti-demo-deployment GitOps repository. Health checks are **critical** for production GitOps deployments as they determine whether ArgoCD reports applications as Healthy, Progressing, or Degraded.

**Key Findings:**
- ✅ **Built-in health checks** cover standard Kubernetes resources
- ⚠️ **Custom resources need Lua-based health checks** for accurate status reporting
- 🔴 **Missing health checks cause "Unknown" status** in ArgoCD UI (e.g., SPIRE ClusterSPIFFEID)
- ✅ **Centralized management** via argocd-cm ConfigMap recommended
- ✅ **Testing framework available** for validation

**Impact**: Without proper health checks, operators cannot determine actual application health, automated rollbacks may fail, and SLOs cannot be accurately measured.

---

## Table of Contents

1. [Why Health Checks Matter](#why-health-checks-matter)
2. [ArgoCD Health Check Architecture](#argocd-health-check-architecture)
3. [Health Status Types](#health-status-types)
4. [Built-in Health Assessments](#built-in-health-assessments)
5. [Custom Health Checks with Lua](#custom-health-checks-with-lua)
6. [Implementation Patterns and Best Practices](#implementation-patterns-and-best-practices)
7. [Health Checks for Kagenti Components](#health-checks-for-kagenti-components)
8. [Testing and Validation](#testing-and-validation)
9. [Deployment Strategy](#deployment-strategy)
10. [Troubleshooting](#troubleshooting)
11. [References](#references)

---

## Why Health Checks Matter

### The Problem

Without accurate health checks, ArgoCD cannot determine if an application is truly healthy:

```
ArgoCD UI shows:
┌─────────────────────────────────────┐
│ Application: spire                  │
│ Status: Unknown  ⚠️                  │
│ Health: Missing                     │
└─────────────────────────────────────┘

Actual state in cluster:
✅ SPIRE Server: Running
✅ SPIRE Agent: Running
✅ ClusterSPIFFEID: Applied to 15 pods
❌ ArgoCD: "I don't know if this is healthy"
```

### The Impact

| Scenario | Without Health Checks | With Health Checks |
|----------|----------------------|-------------------|
| **Deployment Rollout** | Proceeds even if broken | Blocks on failures |
| **Automated Rollback** | Cannot detect failures | Triggers on Degraded |
| **Monitoring/Alerting** | False positives/negatives | Accurate health metrics |
| **SLO Measurement** | Impossible to track | Precise availability data |
| **Progressive Delivery** | Unsafe to proceed | Canary waits for Healthy |
| **Multi-App Dependencies** | Apps sync regardless | Sync-waves wait for health |

### The Solution

Custom Lua-based health checks that understand resource-specific health semantics:

```lua
hs = {}
if obj.status ~= nil and obj.status.stats ~= nil then
  local failures = obj.status.stats.entryFailures or 0
  if failures > 0 then
    hs.status = "Degraded"
    hs.message = "SPIRE entry registration failed"
    return hs
  end
  hs.status = "Healthy"
  return hs
end
hs.status = "Progressing"
return hs
```

---

## ArgoCD Health Check Architecture

### Health Assessment Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    ArgoCD Application                        │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
        ┌────────────────────────────────────┐
        │  For each resource in Application  │
        └────────────────┬───────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌─────────────────┐           ┌──────────────────────┐
│ Built-in Health │           │ Custom Health Check  │
│ (Go code)       │           │ (Lua script)         │
└────────┬────────┘           └──────────┬───────────┘
         │                               │
         │ If found ─────────────────────┤
         │                               │
         └───────────────┬───────────────┘
                         │
                         ▼
            ┌────────────────────────────┐
            │   Return Health Status:    │
            │   • Healthy                │
            │   • Progressing            │
            │   • Degraded               │
            │   • Suspended              │
            │   • Unknown                │
            └────────────────────────────┘
                         │
                         ▼
       ┌──────────────────────────────────────┐
       │  Application Health = Worst Child    │
       │  (Degraded > Progressing > Healthy)  │
       └──────────────────────────────────────┘
```

### Health Check Sources

1. **Built-in Health Checks** (Go code in ArgoCD)
   - Location: `resource_customizations/` in argoproj/argo-cd repository
   - Examples: Deployment, StatefulSet, Service, Job, PersistentVolumeClaim
   - ~30 built-in resource types

2. **Custom Health Checks** (Lua scripts in ConfigMap)
   - Location: `argocd-cm` ConfigMap → `resource.customizations.health.<group>_<kind>`
   - For CRDs and resources without built-in checks
   - Override built-in checks if needed

3. **Default Behavior** (no health check configured)
   - Returns "Progressing" if resource has `.status` field
   - Returns "Healthy" if no `.status` field (assumes static resource)
   - **Problem**: Many CRDs have `.status` but stay "Progressing" forever

---

## Health Status Types

### Official Status Values

| Status | Meaning | UI Color | When to Use |
|--------|---------|----------|-------------|
| **Healthy** | Resource is functioning correctly | 🟢 Green | All conditions met, ready to serve traffic |
| **Progressing** | Resource is being created/updated | 🔵 Blue | Initialization, rolling update, scaling |
| **Degraded** | Resource encountered error | 🔴 Red | Failed conditions, errors, resource stuck |
| **Suspended** | Resource intentionally paused | ⚪ Gray | CronJob suspended, manual pause |
| **Unknown** | Cannot determine health | ⚫ Black | Missing health check, no status field |
| **Missing** | Resource not found in cluster | ❌ Red | Deleted resource, namespace mismatch |

### Status Hierarchy for Application Health

Application health is **worst-case** of all child resources:

```
Degraded > Missing > Unknown > Progressing > Suspended > Healthy
```

Example:
```
Application: platform
├─ Deployment (Healthy)
├─ Service (Healthy)
├─ ClusterSPIFFEID (Degraded) ← Determines app health
└─ ConfigMap (Healthy)

Result: Application status = Degraded
```

---

## Built-in Health Assessments

ArgoCD provides built-in health checks for core Kubernetes resources. Understanding these helps when writing custom checks.

### Deployment Health Check

**Logic**:
```go
// Simplified from ArgoCD source
if deployment.Generation > deployment.Status.ObservedGeneration {
  return Progressing  // Spec changed, waiting for rollout
}

unavailable := deployment.Status.Replicas - deployment.Status.AvailableReplicas
if unavailable > 0 {
  return Progressing  // Pods still starting
}

if deployment.Spec.Replicas != deployment.Status.UpdatedReplicas {
  return Progressing  // Old replica set still exists
}

return Healthy
```

**Key Takeaway**: Checks multiple conditions, not just pod count

### Job Health Check

**Logic**:
```go
if job.Status.Succeeded > 0 {
  return Healthy
}

if job.Spec.Suspend != nil && *job.Spec.Suspend {
  return Suspended
}

for _, condition := range job.Status.Conditions {
  if condition.Type == "Failed" && condition.Status == "True" {
    return Degraded
  }
}

return Progressing
```

**Key Takeaway**: Distinguishes between suspended, failed, and in-progress

### PersistentVolumeClaim Health Check

**Logic**:
```go
if pvc.Status.Phase == "Bound" {
  return Healthy
}

if pvc.Status.Phase == "Pending" {
  return Progressing
}

return Degraded  // Lost or other error state
```

### Service (LoadBalancer) Health Check

**Logic**:
```go
if service.Spec.Type != "LoadBalancer" {
  return Healthy  // ClusterIP/NodePort always healthy
}

if len(service.Status.LoadBalancer.Ingress) > 0 {
  return Healthy  // External IP/hostname assigned
}

return Progressing  // Waiting for cloud provider
```

---

## Custom Health Checks with Lua

### Lua Scripting Basics

**Global Variables Available**:
```lua
obj          -- The Kubernetes resource object (table)
             -- Contains .metadata, .spec, .status fields
```

**Required Return Value**:
```lua
hs = {
  status = "Healthy",        -- Required: one of Healthy/Progressing/Degraded/Suspended
  message = "Optional message"  -- Optional: shown in UI
}
return hs
```

**Lua Standard Libraries**: **DISABLED** for security
- No `os`, `io`, `debug`, `package`, `dofile`, `loadfile`
- Only basic string, table, math operations allowed

### Safe Nil Checking Pattern

**Problem**: Lua throws error if you access nil field

```lua
-- ❌ WRONG - will error if obj.status is nil
if obj.status.ready == true then

-- ✅ CORRECT - check each level
if obj.status ~= nil then
  if obj.status.ready ~= nil then
    if obj.status.ready == true then
```

**Best Practice**: Check existence before access

### Condition Checking Pattern

Most Kubernetes resources use `.status.conditions` array:

```lua
hs = {}

-- Check if conditions exist
if obj.status ~= nil and obj.status.conditions ~= nil then
  for i, condition in ipairs(obj.status.conditions) do

    -- Check for Ready condition
    if condition.type == "Ready" then
      if condition.status == "True" then
        hs.status = "Healthy"
        hs.message = "Resource is ready"
        return hs
      elseif condition.status == "False" then
        hs.status = "Degraded"
        hs.message = condition.message or "Not ready"
        return hs
      else  -- Unknown
        hs.status = "Progressing"
        hs.message = "Waiting for Ready condition"
        return hs
      end
    end
  end
end

-- No conditions or status yet
hs.status = "Progressing"
hs.message = "Waiting for status"
return hs
```

### Statistics-Based Health Pattern

For resources that track counts (like SPIRE ClusterSPIFFEID):

```lua
hs = {}

if obj.status ~= nil and obj.status.stats ~= nil then
  local stats = obj.status.stats

  -- Calculate failures
  local total_failures = (stats.podEntryRenderFailures or 0) + (stats.entryFailures or 0)

  if total_failures > 0 then
    hs.status = "Degraded"
    hs.message = string.format("%d failures detected", total_failures)
    return hs
  end

  -- Check if applied to any resources
  local total_selected = (stats.podsSelected or 0) + (stats.namespaceSelected or 0)
  if total_selected > 0 then
    hs.status = "Healthy"
    hs.message = string.format("Applied to %d resources", total_selected)
    return hs
  end
end

hs.status = "Progressing"
hs.message = "Waiting for resource selection"
return hs
```

---

## Implementation Patterns and Best Practices

### Pattern 1: Simple Boolean Check

**Use Case**: Resource with single boolean status field

```lua
hs = {}
if obj.status ~= nil then
  if obj.status.ready == true then
    hs.status = "Healthy"
    return hs
  elseif obj.status.ready == false then
    hs.status = "Degraded"
    hs.message = obj.status.message or "Resource not ready"
    return hs
  end
end
hs.status = "Progressing"
return hs
```

### Pattern 2: Phase-Based Health

**Use Case**: Resources with `.status.phase` (like Certificates, Volumes)

```lua
hs = {}
if obj.status ~= nil and obj.status.phase ~= nil then
  local phase = obj.status.phase

  if phase == "Ready" or phase == "Bound" or phase == "Active" then
    hs.status = "Healthy"
    return hs
  elseif phase == "Failed" or phase == "Error" then
    hs.status = "Degraded"
    hs.message = "Phase: " .. phase
    return hs
  else
    hs.status = "Progressing"
    hs.message = "Phase: " .. phase
    return hs
  end
end
hs.status = "Progressing"
return hs
```

### Pattern 3: Multi-Condition Aggregation

**Use Case**: Resources with multiple conditions that must all be true

```lua
hs = {}

-- Define required conditions
local required_conditions = {"Ready", "Initialized", "Available"}
local healthy_count = 0
local degraded_conditions = {}

if obj.status ~= nil and obj.status.conditions ~= nil then
  for i, condition in ipairs(obj.status.conditions) do
    -- Check if this is a required condition
    for j, req_type in ipairs(required_conditions) do
      if condition.type == req_type then
        if condition.status == "True" then
          healthy_count = healthy_count + 1
        elseif condition.status == "False" then
          table.insert(degraded_conditions, condition.type)
        end
        break
      end
    end
  end

  -- All required conditions are True
  if healthy_count == #required_conditions then
    hs.status = "Healthy"
    return hs
  end

  -- Some conditions are False
  if #degraded_conditions > 0 then
    hs.status = "Degraded"
    hs.message = "Failed conditions: " .. table.concat(degraded_conditions, ", ")
    return hs
  end
end

hs.status = "Progressing"
return hs
```

### Pattern 4: Replica Count Validation

**Use Case**: Operators/controllers that manage replicas

```lua
hs = {}

if obj.status ~= nil then
  local desired = obj.spec.replicas or 1
  local ready = obj.status.readyReplicas or 0
  local available = obj.status.availableReplicas or 0

  if ready >= desired and available >= desired then
    hs.status = "Healthy"
    hs.message = string.format("%d/%d replicas ready", ready, desired)
    return hs
  elseif ready > 0 then
    hs.status = "Progressing"
    hs.message = string.format("%d/%d replicas ready", ready, desired)
    return hs
  else
    hs.status = "Degraded"
    hs.message = "No replicas ready"
    return hs
  end
end

hs.status = "Progressing"
return hs
```

### Pattern 5: Error Counting Threshold

**Use Case**: Resources that tolerate some errors but degrade above threshold

```lua
hs = {}

if obj.status ~= nil then
  local errors = obj.status.errors or 0
  local warnings = obj.status.warnings or 0
  local total = obj.status.total or 1

  local error_rate = errors / total

  if error_rate == 0 then
    hs.status = "Healthy"
    hs.message = string.format("%d/%d successful", total - errors, total)
    return hs
  elseif error_rate < 0.1 then  -- Less than 10% errors
    hs.status = "Progressing"
    hs.message = string.format("%d errors (%.1f%%)", errors, error_rate * 100)
    return hs
  else
    hs.status = "Degraded"
    hs.message = string.format("%d errors (%.1f%%)", errors, error_rate * 100)
    return hs
  end
end

hs.status = "Progressing"
return hs
```

### Best Practices

#### 1. Always Check for Nil

```lua
-- ❌ BAD
if obj.status.ready == true then

-- ✅ GOOD
if obj.status ~= nil then
  if obj.status.ready ~= nil then
    if obj.status.ready == true then
```

#### 2. Provide Meaningful Messages

```lua
-- ❌ BAD
hs.message = "Not ready"

-- ✅ GOOD
hs.message = string.format(
  "Waiting for %d/%d pods to be ready",
  obj.status.readyReplicas or 0,
  obj.spec.replicas or 1
)
```

#### 3. Default to Progressing

```lua
-- Always return something, default to Progressing
hs = {}
-- ... health check logic ...
if not hs.status then
  hs.status = "Progressing"
  hs.message = "Evaluating resource health"
end
return hs
```

#### 4. Keep Scripts Concise

- Aim for < 50 lines of Lua
- Extract complex logic into helper functions (within same script)
- Comment non-obvious logic

#### 5. Test Edge Cases

- Resource with no `.status` field
- Resource with empty `.status.conditions`
- Negative numbers in stats
- Nil vs 0 vs false

---

## Health Checks for Kagenti Components

### 1. SPIRE ClusterSPIFFEID

**File**: `argocd/config/argocd-cm-health-checks.yaml`

```yaml
resource.customizations.health.spire.spiffe.io_ClusterSPIFFEID: |
  hs = {}

  -- Check if status and stats exist
  if obj.status ~= nil and obj.status.stats ~= nil then
    local stats = obj.status.stats

    -- Calculate total failures
    local render_failures = stats.podEntryRenderFailures or 0
    local entry_failures = stats.entryFailures or 0
    local total_failures = render_failures + entry_failures

    -- Degraded if any failures
    if total_failures > 0 then
      hs.status = "Degraded"
      hs.message = string.format(
        "Failures detected - Render: %d, Entry: %d",
        render_failures,
        entry_failures
      )
      return hs
    end

    -- Healthy if applied to resources
    local pods_selected = stats.podsSelected or 0
    local ns_selected = stats.namespaceSelected or 0

    if pods_selected > 0 or ns_selected > 0 then
      hs.status = "Healthy"
      hs.message = string.format(
        "Applied to %d namespaces, %d pods",
        ns_selected,
        pods_selected
      )
      return hs
    end
  end

  -- Still waiting for status
  hs.status = "Progressing"
  hs.message = "Waiting for ClusterSPIFFEID to be processed"
  return hs
```

### 2. SPIRE ClusterStaticEntry

```yaml
resource.customizations.health.spire.spiffe.io_ClusterStaticEntry: |
  hs = {}

  if obj.status ~= nil then
    if obj.status.set == true then
      hs.status = "Healthy"
      hs.message = "Entry registered with SPIRE Server"
      return hs
    elseif obj.status.set == false then
      hs.status = "Degraded"
      hs.message = "Entry registration failed"
      return hs
    end
  end

  hs.status = "Progressing"
  hs.message = "Waiting for entry registration"
  return hs
```

### 3. Kagenti Component CR

```yaml
resource.customizations.health.kagenti.operator.dev_Component: |
  hs = {}

  -- Check if component is suspended
  if obj.spec.suspend == true then
    hs.status = "Suspended"
    hs.message = "Component deployment suspended by Platform controller"
    return hs
  end

  -- Check deployment status
  if obj.status ~= nil then
    -- Check for Ready condition
    if obj.status.conditions ~= nil then
      for i, condition in ipairs(obj.status.conditions) do
        if condition.type == "Ready" then
          if condition.status == "True" then
            hs.status = "Healthy"
            hs.message = "Component deployed successfully"
            return hs
          elseif condition.status == "False" then
            hs.status = "Degraded"
            hs.message = condition.message or "Component deployment failed"
            return hs
          end
        end
      end
    end

    -- Check phase if available
    if obj.status.phase ~= nil then
      if obj.status.phase == "Deployed" then
        hs.status = "Healthy"
        return hs
      elseif obj.status.phase == "Failed" then
        hs.status = "Degraded"
        hs.message = "Phase: Failed"
        return hs
      end
    end
  end

  hs.status = "Progressing"
  hs.message = "Component deployment in progress"
  return hs
```

### 4. Kagenti Agent CR

```yaml
resource.customizations.health.kagenti.operator.dev_Agent: |
  hs = {}

  if obj.status ~= nil then
    local desired_replicas = obj.spec.replicas or 1
    local ready_replicas = obj.status.readyReplicas or 0
    local available_replicas = obj.status.availableReplicas or 0

    -- All replicas ready and available
    if ready_replicas >= desired_replicas and available_replicas >= desired_replicas then
      hs.status = "Healthy"
      hs.message = string.format("%d/%d agent replicas ready", ready_replicas, desired_replicas)
      return hs
    end

    -- Some replicas ready
    if ready_replicas > 0 then
      hs.status = "Progressing"
      hs.message = string.format("%d/%d agent replicas ready", ready_replicas, desired_replicas)
      return hs
    end

    -- No replicas ready - check conditions
    if obj.status.conditions ~= nil then
      for i, condition in ipairs(obj.status.conditions) do
        if condition.type == "Available" and condition.status == "False" then
          hs.status = "Degraded"
          hs.message = condition.message or "Agent not available"
          return hs
        end
      end
    end
  end

  hs.status = "Progressing"
  hs.message = "Agent deployment starting"
  return hs
```

### 5. Cert-Manager Certificate

```yaml
resource.customizations.health.cert-manager.io_Certificate: |
  hs = {}

  if obj.status ~= nil and obj.status.conditions ~= nil then
    for i, condition in ipairs(obj.status.conditions) do
      if condition.type == "Ready" then
        if condition.status == "True" then
          hs.status = "Healthy"
          hs.message = "Certificate issued and ready"
          return hs
        elseif condition.status == "False" then
          hs.status = "Degraded"
          hs.message = condition.message or "Certificate not ready"
          return hs
        end
      end
    end
  end

  hs.status = "Progressing"
  hs.message = "Certificate issuance in progress"
  return hs
```

### 6. Istio Gateway

```yaml
resource.customizations.health.gateway.networking.k8s.io_Gateway: |
  hs = {}

  if obj.status ~= nil and obj.status.conditions ~= nil then
    local programmed = false
    local accepted = false

    for i, condition in ipairs(obj.status.conditions) do
      if condition.type == "Programmed" and condition.status == "True" then
        programmed = true
      end
      if condition.type == "Accepted" and condition.status == "True" then
        accepted = true
      end
      if condition.type == "Programmed" and condition.status == "False" then
        hs.status = "Degraded"
        hs.message = "Gateway not programmed: " .. (condition.message or "unknown")
        return hs
      end
    end

    if programmed and accepted then
      hs.status = "Healthy"
      hs.message = "Gateway accepted and programmed"
      return hs
    end
  end

  hs.status = "Progressing"
  hs.message = "Gateway configuration in progress"
  return hs
```

### 7. Tekton PipelineRun

```yaml
resource.customizations.health.tekton.dev_PipelineRun: |
  hs = {}

  if obj.status ~= nil and obj.status.conditions ~= nil then
    for i, condition in ipairs(obj.status.conditions) do
      if condition.type == "Succeeded" then
        if condition.status == "True" then
          hs.status = "Healthy"
          hs.message = "Pipeline run completed successfully"
          return hs
        elseif condition.status == "False" then
          hs.status = "Degraded"
          hs.message = condition.message or "Pipeline run failed"
          return hs
        elseif condition.reason == "Running" or condition.reason == "Started" then
          hs.status = "Progressing"
          hs.message = "Pipeline run in progress"
          return hs
        end
      end
    end
  end

  hs.status = "Progressing"
  hs.message = "Pipeline run starting"
  return hs
```

---

## Testing and Validation

### Local Testing with argocd CLI

ArgoCD provides a command to test health checks locally without deploying to cluster:

```bash
# Save your health check Lua script to a file
cat > health-check.lua <<'EOF'
hs = {}
if obj.status ~= nil and obj.status.ready == true then
  hs.status = "Healthy"
  return hs
end
hs.status = "Progressing"
return hs
EOF

# Get a sample resource from your cluster
kubectl get clusterspiffeid -n spire-system <name> -o yaml > resource.yaml

# Test the health check
argocd admin settings resource-overrides health \
  --health-script health-check.lua \
  resource.yaml
```

**Output**:
```
Health Status: Healthy
Message: (if provided)
```

### Integration Testing

Create test resources with known states:

```yaml
# test-resources/clusterspiffeid-healthy.yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: test-healthy
status:
  stats:
    namespaceSelected: 2
    podsSelected: 5
    podEntryRenderFailures: 0
    entryFailures: 0
---
# test-resources/clusterspiffeid-degraded.yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: test-degraded
status:
  stats:
    namespaceSelected: 2
    podsSelected: 5
    podEntryRenderFailures: 3
    entryFailures: 1
```

Test each:
```bash
argocd admin settings resource-overrides health \
  --health-script health-check.lua \
  test-resources/clusterspiffeid-healthy.yaml
# Expected: Healthy

argocd admin settings resource-overrides health \
  --health-script health-check.lua \
  test-resources/clusterspiffeid-degraded.yaml
# Expected: Degraded
```

### Unit Testing Framework (Optional)

For complex health checks, create a test suite:

```yaml
# health_test.yaml (ArgoCD convention)
tests:
  - healthStatus:
      status: Healthy
      message: "Applied to 2 namespaces, 5 pods"
    inputPath: testdata/clusterspiffeid-healthy.yaml

  - healthStatus:
      status: Degraded
      message: "Failures detected - Render: 3, Entry: 1"
    inputPath: testdata/clusterspiffeid-degraded.yaml

  - healthStatus:
      status: Progressing
      message: "Waiting for ClusterSPIFFEID to be processed"
    inputPath: testdata/clusterspiffeid-no-status.yaml
```

Run tests:
```bash
# ArgoCD will validate all test cases
argocd admin settings resource-overrides health-test \
  --health-script health.lua \
  --test-file health_test.yaml
```

---

## Deployment Strategy

### Centralized ConfigMap Approach (Recommended)

Create a single ConfigMap for all custom health checks:

**File**: `argocd/config/argocd-cm-health-checks.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  # SPIRE Health Checks
  resource.customizations.health.spire.spiffe.io_ClusterSPIFFEID: |
    # ... health check script ...

  resource.customizations.health.spire.spiffe.io_ClusterStaticEntry: |
    # ... health check script ...

  # Kagenti Operator Health Checks
  resource.customizations.health.kagenti.operator.dev_Component: |
    # ... health check script ...

  resource.customizations.health.kagenti.operator.dev_Agent: |
    # ... health check script ...

  resource.customizations.health.kagenti.operator.dev_AgentBuild: |
    # ... health check script ...

  # Infrastructure Health Checks
  resource.customizations.health.cert-manager.io_Certificate: |
    # ... health check script ...

  resource.customizations.health.gateway.networking.k8s.io_Gateway: |
    # ... health check script ...

  resource.customizations.health.tekton.dev_PipelineRun: |
    # ... health check script ...
```

### Deployment Steps

1. **Create/Update ConfigMap**:
```bash
kubectl apply -f argocd/config/argocd-cm-health-checks.yaml
```

2. **Restart ArgoCD Components** (to pick up changes):
```bash
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout restart deployment argocd-application-controller -n argocd
```

3. **Verify Health Checks Loaded**:
```bash
kubectl logs -n argocd deployment/argocd-application-controller | grep "resource customization"
```

4. **Test with Sample Resource**:
```bash
# Create test ClusterSPIFFEID
kubectl apply -f test-clusterspiffeid.yaml

# Check health in ArgoCD
argocd app get spire --show-params
```

### GitOps Integration

Add to your ArgoCD bootstrap:

**File**: `argocd/bootstrap/kind/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - install.yaml
  - argocd-cm-health-checks.yaml  # Add this

# Patch to merge with existing argocd-cm if needed
patches:
  - target:
      kind: ConfigMap
      name: argocd-cm
    patch: |-
      - op: add
        path: /data
        value:
          # Health checks will be merged here
```

---

## Troubleshooting

### Health Check Not Applying

**Symptom**: Health check Lua script added to ConfigMap, but resource still shows "Progressing"

**Diagnosis**:
```bash
# 1. Verify ConfigMap has the health check
kubectl get cm argocd-cm -n argocd -o yaml | grep -A 20 "ClusterSPIFFEID"

# 2. Check ArgoCD logs for errors
kubectl logs -n argocd deployment/argocd-application-controller | grep -i "health\|lua\|error"

# 3. Verify resource group/kind matches exactly
kubectl api-resources | grep -i spiffeid
```

**Common Fixes**:
- Restart ArgoCD pods after ConfigMap changes
- Check for syntax errors in Lua (missing `return hs`)
- Verify resource group name uses underscores: `spire.spiffe.io_ClusterSPIFFEID` not `spire.spiffe.io/ClusterSPIFFEID`

### Lua Script Errors

**Symptom**: ArgoCD logs show Lua errors

**Diagnosis**:
```bash
kubectl logs -n argocd deployment/argocd-application-controller | grep "lua.*error"
```

**Common Errors**:
```
Error: attempt to index a nil value
Fix: Add nil checks before accessing fields

Error: ')' expected
Fix: Check for unclosed string literals or table definitions

Error: 'end' expected
Fix: Ensure all if/for/function blocks are closed
```

### Health Check Always Returns Progressing

**Symptom**: Resource always shows "Progressing" even when healthy

**Diagnosis**:
- Check if script is reaching the `return hs` statements
- Verify status fields exist on the resource: `kubectl get <resource> -o yaml`

**Fix**:
Add debug logging (then remove after testing):
```lua
hs = {}
if obj.status == nil then
  hs.status = "Progressing"
  hs.message = "DEBUG: No status field"
  return hs
end
if obj.status.stats == nil then
  hs.status = "Progressing"
  hs.message = "DEBUG: No stats field"
  return hs
end
-- ... rest of logic
```

### Application Health Not Updating

**Symptom**: Individual resource health updated, but Application still shows old status

**Diagnosis**:
```bash
# Force refresh Application
argocd app get <app-name> --refresh

# Check if auto-sync is enabled
argocd app get <app-name> | grep "Sync Policy"
```

**Fix**:
- ArgoCD caches health status - wait ~3 minutes or force refresh
- Check if resource is ignored: `argocd.argoproj.io/sync-options: SkipHealthCheck=true`

---

## References

### Official Documentation

- **ArgoCD Health Checks**: https://argo-cd.readthedocs.io/en/stable/operator-manual/health/
- **Resource Customizations**: https://github.com/argoproj/argo-cd/tree/master/resource_customizations
- **Lua 5.3 Reference**: https://www.lua.org/manual/5.3/
- **ArgoCD CLI Health Testing**: https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_admin_settings_resource-overrides_health/

### Community Resources

- **Custom Health Checks Guide**: https://medium.com/matsiremark/custom-health-checks-with-argocd-b49a45ab4d0c
- **CRD Health Checks**: https://www.gepardec.com/blog/crdhealthecks-for-argocd/
- **Health Check Patterns**: https://www.patrickdap.com/post/argocd-health-checks/

### Kagenti Project References

- **TODO_FIX_SPIRE.md**: SPIRE integration and health check requirements
- **TODO_KAGENTI_OPERATORS.md**: Operator deployment and health

---

## Conclusion

Proper health checks are **essential** for production ArgoCD deployments. They enable:
- ✅ Accurate application status reporting
- ✅ Safe automated deployments with rollback
- ✅ Meaningful SLO tracking
- ✅ Proper sync-wave orchestration

**Next Steps**:
1. Review Kagenti component health checks in this document
2. Create `argocd/config/argocd-cm-health-checks.yaml` with all checks
3. Deploy and test each health check
4. Add health check validation to CI/CD

**Maintenance**:
- Review health checks when adding new CRDs
- Test health checks with failure scenarios
- Update as resource schemas evolve

---

**Document Version**: 1.0
**Last Updated**: 2025-11-10
**Maintained By**: Kagenti Platform Team
