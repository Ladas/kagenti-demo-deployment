# Documentation Cleanup and Reorganization Plan

**Version**: 1.0
**Date**: 2025-11-10
**Status**: Planning Phase - Ready for Implementation
**Goal**: Clean, well-structured, and human-friendly documentation organized by stack components

---

## Executive Summary

The `docs/` directory currently contains 24 markdown files (13,000+ lines) with:
- **Inconsistent structure** - mix of guides, reports, checklists, and architecture docs
- **Unclear organization** - no clear categorization by stack component
- **Missing TOCs** - most docs lack internal navigation
- **Unverified sources** - many external links not validated
- **Duplicate content** - overlapping information across multiple files
- **No clear audience** - some docs are internal notes, others are user-facing

**Goal**: Reorganize into logical stack components with:
- Clear directory structure by technology area
- Consistent document format with TOCs
- Verified sources with direct links
- Alternatives and next steps sections
- Human-friendly, concise explanations

---

## Current Documentation Inventory

### Existing Files (24 total, 13,000+ lines)

```
docs/
├── README.md                                # 447 lines - Index/navigation
├──  CLEANUP.md                               # 713 lines - Cleanup plan (deprecated)
├── DEPLOYMENT.md                             # 443 lines - General deployment guide
├── DOCUMENTATION_VERIFICATION_SUMMARY.md     # 398 lines - Verification report
├── ENCRYPTION_ARCHITECTURE.md                # 417 lines - Encryption setup
├── GATEWAY-ACCESS-KIND.md                    # 367 lines - Gateway config
├── INTEGRATION_TESTS.md                      # 764 lines - Testing guide
├── KAGENTI_DEPS_DECOMPOSITION.md             # 374 lines - Dependencies analysis
├── kagenti_operators.md                      # 1444 lines - Operators guide
├── KEYCLOAK_GITOPS_ARCHITECTURE.md           # 307 lines - Keycloak GitOps
├── LINK_VERIFICATION_CHECKLIST.md            # 348 lines - Link checking
├── NEXT-STEPS.md                             # 780 lines - Future plans
├── OLM_ARGOCD_COMPARISON.md                  # 1229 lines - OLM guide
├── OLM_CONFIGURATION_REALITY.md              # 635 lines - OLM reality check
├── OPENSHIFT-LOCAL-SETUP.md                  # 654 lines - Local OpenShift setup
├── OPENSHIFT.md                              # 815 lines - OpenShift deployment
├── PLATFORM-STATUS.md                        # 366 lines - Platform status report
├── PLATFORM-VALIDATION-REPORT.md             # 603 lines - Validation report
├── PRODUCTION_SECURITY_ROADMAP.md            # 313 lines - Security roadmap
├── QUICK-START.md                            # 506 lines - Quick start guide
├── SECURITY-MONITORING-ACCESS.md             # 412 lines - Security/monitoring access
├── SOP-PLATFORM-OPERATIONS.md                # 649 lines - Operations procedures
├── TRACING_ARCHITECTURE.md                   # 481 lines - Distributed tracing
└── UI-ACCESS-VIA-GATEWAY.md                  # 398 lines - UI access guide
```

---

## Proposed New Structure

Organize docs by **technology stack component** with clear categorization:

```
docs/
├── README.md                                 # 🎯 Index with TOC (UPDATED)
│
├── 00-getting-started/                       # 🆕 New users start here
│   ├── README.md                            # Quick navigation
│   ├── quick-start.md                       # 15-min local deployment
│   ├── architecture-overview.md             # High-level system overview
│   └── prerequisites.md                     # Tools, accounts, knowledge needed
│
├── 01-infrastructure/                        # 🆕 Base infrastructure components
│   ├── README.md                            # Infrastructure index
│   ├── kubernetes.md                        # Kind + kubectl setup
│   ├── argocd.md                            # GitOps with ArgoCD + ApplicationSets
│   ├── cert-manager.md                      # TLS certificate management
│   ├── container-registry.md                # Local container registry
│   └── gateway-api.md                       # Gateway API + Istio integration
│
├── 02-service-mesh/                          # 🆕 Istio service mesh
│   ├── README.md                            # Service mesh index
│   ├── istio.md                             # Istio installation + config
│   ├── mtls.md                              # Mutual TLS configuration
│   ├── traffic-management.md                # Routing, retries, timeouts
│   └── observability.md                     # Istio metrics + traces
│
├── 03-authentication/                        # 🆕 Auth and identity
│   ├── README.md                            # Authentication index
│   ├── keycloak.md                          # Keycloak SSO (Operator vs OLM)
│   ├── oauth2-proxy.md                      # OAuth2 proxy for services
│   └── rbac.md                              # RBAC policies
│
├── 04-observability/                         # 🆕 Monitoring + tracing
│   ├── README.md                            # Observability index
│   ├── distributed-tracing.md               # OpenTelemetry + Tempo + Phoenix
│   ├── grafana.md                           # Grafana dashboards + datasources
│   ├── prometheus.md                        # Prometheus metrics
│   ├── kiali.md                             # Service mesh visualization
│   └── jaeger.md                            # Jaeger (deprecated, use Tempo)
│
├── 05-ci-cd/                                 # 🆕 CI/CD pipelines
│   ├── README.md                            # CI/CD index
│   ├── tekton.md                            # Tekton Pipelines (Operator vs OLM)
│   └── gitops-workflows.md                  # GitOps best practices
│
├── 06-operators/                             # 🆕 Kagenti operators
│   ├── README.md                            # Operators index
│   ├── platform-operator.md                 # Platform Operator guide
│   ├── agent-operator.md                    # Agent Operator guide
│   ├── crds.md                              # CRD specifications
│   └── troubleshooting.md                   # Operator troubleshooting
│
├── 07-platform/                              # 🆕 Kagenti platform
│   ├── README.md                            # Platform index
│   ├── kagenti-ui.md                        # UI deployment + access
│   ├── agents.md                            # AI agent deployment
│   └── mcp-servers.md                       # MCP server integration
│
├── 08-security/                              # 🆕 Security hardening
│   ├── README.md                            # Security index
│   ├── encryption.md                        # Encryption at rest + transit
│   ├── secrets-management.md                # Secrets handling
│   ├── network-policies.md                  # Network security
│   └── security-roadmap.md                  # Future security improvements
│
├── 09-deployment/                            # 🆕 Environment-specific deployment
│   ├── README.md                            # Deployment index
│   ├── kind-local.md                        # Kind local development
│   ├── openshift-local.md                   # OpenShift Local (CRC)
│   ├── openshift-stage.md                   # OpenShift staging
│   ├── openshift-prod.md                    # OpenShift production
│   └── migration-guide.md                   # Kubernetes → OpenShift OLM
│
├── 10-operations/                            # 🆕 Day-2 operations
│   ├── README.md                            # Operations index
│   ├── monitoring.md                        # Monitoring setup + alerts
│   ├── troubleshooting.md                   # Common issues + solutions
│   ├── backup-restore.md                    # Backup procedures
│   ├── disaster-recovery.md                 # DR procedures
│   └── runbooks/                            # Incident runbooks
│       ├── pod-crashloop.md
│       ├── certificate-expiry.md
│       └── keycloak-unavailable.md
│
└── 99-appendix/                              # 🆕 Reference material
    ├── glossary.md                          # Terms + acronyms
    ├── external-links.md                    # Curated external resources
    ├── changelog.md                         # Documentation changes
    └── deprecated/                          # Old docs (for reference)
        ├── CLEANUP.md
        ├── PLATFORM-STATUS.md
        ├── PLATFORM-VALIDATION-REPORT.md
        └── DOCUMENTATION_VERIFICATION_SUMMARY.md
```

---

## Standard Document Template

Every document MUST follow this structure:

```markdown
# [Component Name]: [Brief Purpose]

**Version**: X.Y
**Last Updated**: YYYY-MM-DD
**Status**: Draft | In Review | Production Ready
**Audience**: Developers | Platform Engineers | SRE | All

---

## Table of Contents

- [Overview](#overview)
- [What is [Component]?](#what-is-component)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Alternatives](#alternatives)
- [Next Steps](#next-steps)
- [References](#references)

---

## Overview

**Purpose**: [1-2 sentences explaining why this component exists]

**Key Benefits**:
- Benefit 1
- Benefit 2
- Benefit 3

**Prerequisites**:
- Prerequisite 1
- Prerequisite 2

**Quick Links**:
- [Official Documentation](https://example.com)
- [GitHub Repository](https://github.com/example/repo)
- [Related Guide](./related-guide.md)

---

## What is [Component]?

### Concept

[2-3 paragraphs explaining the technology/concept]

**Source**: [Official Docs](https://example.com/docs/concept)

### Why We Use It

[Explain specific use case in Kagenti platform]

**Source**: [Architecture Decision](./architecture-overview.md#decision-x)

### Deployment Methods

| Method | Environment | Why |
|--------|-------------|-----|
| Upstream Helm | Kind (dev) | Simplicity, fast iteration |
| OLM Operator | OpenShift (prod) | Automated upgrades, Red Hat support |

**Source**: [OLM Comparison](./deployment/migration-guide.md)

---

## Architecture

### Component Diagram

```mermaid
graph TD
    [Mermaid diagram showing component relationships]
```

### Integration Points

1. **[Related Component 1]**: How they interact
   - **Source**: [Integration Guide](./path.md)

2. **[Related Component 2]**: How they interact
   - **Source**: [Integration Guide](./path.md)

---

## Installation

### Method 1: [Upstream/Helm/Kustomize]

**Prerequisites**:
- Tool 1 version X.Y
- Tool 2 configured

**Installation**:
```bash
# Step 1: Brief description
command-here

# Step 2: Brief description
command-here
```

**Verification**:
```bash
# Check deployment
kubectl get pods -n namespace

# Expected output:
# NAME                     READY   STATUS
# component-xxx-xxx        1/1     Running
```

**Source**: [Upstream Installation Guide](https://example.com/install)

### Method 2: [OLM Operator]

**Prerequisites**:
- OpenShift cluster with OLM
- ArgoCD installed

**Installation**:
```bash
# Deploy via ArgoCD ApplicationSet
kubectl apply -f argocd/appsets/component.yaml
```

**Verification**:
```bash
# Check operator installed
kubectl get csv -n namespace

# Check custom resources
kubectl get ComponentCR -n namespace
```

**Source**: [OLM Documentation](https://olm.operatorframework.io/)

---

## Configuration

### Basic Configuration

**File**: `components/00-infrastructure/component/base/config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: component-config
data:
  # Setting 1: What it does
  setting1: value1

  # Setting 2: What it does
  setting2: value2
```

**Source**: [Upstream Configuration Reference](https://example.com/config)

### Environment-Specific Configuration

#### Kind (Local Development)

**File**: `components/00-infrastructure/component/overlays/kind-local/kustomization.yaml`

```yaml
patches:
  # Lower resources for dev
  - patch: |-
      - op: replace
        path: /spec/resources/requests/cpu
        value: 100m
```

**Why**: Conserve local resources

#### OpenShift (Production)

**File**: `components/00-infrastructure/component/overlays/openshift-prod/kustomization.yaml`

```yaml
patches:
  # High availability
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```

**Why**: Production resilience requirements

**Source**: [Kustomize Best Practices](https://kubectl.docs.kubernetes.io/references/kustomize/)

---

## Usage

### Common Tasks

#### Task 1: [Description]

**Command**:
```bash
kubectl exec -n namespace pod-name -- command
```

**Expected Output**:
```
output here
```

**Source**: [Upstream CLI Reference](https://example.com/cli)

#### Task 2: [Description]

**Steps**:
1. Step 1
2. Step 2
3. Step 3

**Verification**:
```bash
# Check result
kubectl get resource -n namespace
```

---

## Troubleshooting

### Issue 1: [Common Problem]

**Symptoms**:
- Symptom 1
- Symptom 2

**Diagnosis**:
```bash
# Check logs
kubectl logs -n namespace deployment/component
```

**Root Cause**: [Explanation]

**Solution**:
```bash
# Fix command
kubectl apply -f fix.yaml
```

**Source**: [Troubleshooting Guide](https://example.com/troubleshooting)

### Issue 2: [Another Problem]

[Same format as Issue 1]

---

## Alternatives

### Alternative 1: [Tool/Approach Name]

**Description**: What it is and how it compares

**Pros**:
- Pro 1
- Pro 2

**Cons**:
- Con 1
- Con 2

**When to Use**: Specific scenarios where this alternative makes sense

**Source**: [Comparison Article](https://example.com/comparison)

### Alternative 2: [Another Tool]

[Same format as Alternative 1]

---

## Next Steps

### Recommended Reading

1. **[Related Component Guide](./related.md)** - How this integrates
2. **[Advanced Configuration](./advanced.md)** - Deep dive into features
3. **[Operations Guide](../10-operations/monitoring.md)** - Day-2 operations

### Suggested Improvements

1. **[Feature Name]**: Description of potential enhancement
   - **Benefit**: Why it would help
   - **Effort**: Time/complexity estimate
   - **Priority**: Low | Medium | High

2. **[Another Feature]**: Description
   - [Same format]

### Related Projects

- **[Project Name](https://github.com/example/project)**: How it relates
- **[Another Project](https://github.com/example/another)**: How it relates

---

## References

### Official Documentation

- **Main Documentation**: [https://example.com/docs](https://example.com/docs)
- **API Reference**: [https://example.com/api](https://example.com/api)
- **GitHub Repository**: [https://github.com/example/repo](https://github.com/example/repo)

### Community Resources

- **Blog Post**: [Title](https://blog.example.com/post) - Summary
- **Video Tutorial**: [Title](https://youtube.com/watch?v=xxx) - Summary
- **Conference Talk**: [Title](https://example.com/talk) - Summary

### Internal Documentation

- **[Related Internal Doc](./related.md)** - Brief description
- **[Architecture Decision](../architecture.md)** - Brief description

### Version Information

- **Current Version**: vX.Y.Z
- **Tested Version**: vX.Y.Z
- **Compatibility**: Kubernetes X.Y+, OpenShift X.Y+

---

**Last Updated**: YYYY-MM-DD
**Document Version**: X.Y
**Maintained By**: Platform Engineering Team
**License**: Apache 2.0
```

---

## Migration Checklist

### Phase 1: Reorganization Planning ✅ COMPLETE

- [x] Analyze current documentation (24 files)
- [x] Design new directory structure
- [x] Create standard template
- [x] Create TODO_DOCS_CLEANUP.md (this file)

### Phase 2: Create New Directory Structure

- [ ] Create new directories:
  ```bash
  mkdir -p docs/{00-getting-started,01-infrastructure,02-service-mesh,03-authentication,04-observability,05-ci-cd,06-operators,07-platform,08-security,09-deployment,10-operations,99-appendix}
  mkdir -p docs/99-appendix/deprecated
  ```

- [ ] Create index README.md files for each directory

### Phase 3: Document Migration and Cleanup

For each document:

#### Step 1: Identify Target Location

Determine which new directory the content belongs in.

#### Step 2: Extract Content

Read current file and extract:
- Core technical content
- Configuration examples
- Troubleshooting sections

#### Step 3: Rewrite with Standard Template

Apply standard template:
- Add TOC
- Add Overview section
- Organize into clear sections
- Add verified source links for EVERY subsection
- Add Alternatives section
- Add Next Steps section
- Add References section with all sources

#### Step 4: Verify Sources

For each external link:
- [ ] Verify URL exists (returns 200)
- [ ] Verify content matches our description
- [ ] Add version information if applicable
- [ ] Replace generic links with specific deep links

#### Step 5: Move to New Location

- [ ] Save new file in appropriate directory
- [ ] Update cross-references
- [ ] Move old file to `99-appendix/deprecated/`

---

## Document-by-Document Migration Plan

### Priority 1: Core Infrastructure Guides

#### 1.1: ArgoCD Documentation

**Current Files**:
- `DEPLOYMENT.md` (443 lines) - General deployment
- TODO_ARGO_CLEANUP.md (1500+ lines) - ArgoCD cleanup plan
- TODO_ARGO_NEXT.md (500+ lines) - ApplicationSets migration

**New File**: `docs/01-infrastructure/argocd.md`

**Content Sections**:
1. **What is ArgoCD?** - GitOps concept, why we use it
   - **Source**: https://argo-cd.readthedocs.io/en/stable/
2. **Architecture** - App-of-Apps vs ApplicationSets
   - **Source**: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
3. **Installation** - Deploy ArgoCD on Kind
   - **Source**: https://argo-cd.readthedocs.io/en/stable/getting_started/
4. **Configuration** - ApplicationSets for multi-environment
   - **Source**: TODO_ARGO_NEXT.md
5. **Usage** - Common ArgoCD operations
6. **Troubleshooting** - Sync issues, health checks
7. **Alternatives** - Flux, Jenkins X
   - **Source**: https://fluxcd.io/, https://jenkins-x.io/
8. **Next Steps** - Migrate to ApplicationSets, add notifications

**Sources to Verify**:
- [ ] https://argo-cd.readthedocs.io/ (main docs)
- [ ] https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/ (ApplicationSets)
- [ ] https://github.com/argoproj/argo-cd (GitHub repo)

**Status**: 🔲 NOT STARTED

---

#### 1.2: Keycloak Documentation

**Current Files**:
- `KEYCLOAK_GITOPS_ARCHITECTURE.md` (307 lines)
- Sections in `DEPLOYMENT.md` about Keycloak

**New File**: `docs/03-authentication/keycloak.md`

**Content Sections**:
1. **What is Keycloak?** - SSO/Identity provider concept
   - **Source**: https://www.keycloak.org/documentation
2. **Architecture** - How Keycloak integrates with OAuth2-Proxy, Grafana, Kiali
   - **Source**: KEYCLOAK_GITOPS_ARCHITECTURE.md
3. **Installation**:
   - **Method 1**: Upstream Keycloak Operator (Kind)
     - **Source**: https://www.keycloak.org/operator/installation
   - **Method 2**: Red Hat Keycloak Operator via OLM (OpenShift)
     - **Source**: https://access.redhat.com/documentation/en-us/red_hat_build_of_keycloak/22.0
4. **Configuration**:
   - Keycloak CR specification
   - Realm imports (kubernetes realm, kagenti realm)
   - Client configurations (grafana, kiali, phoenix)
   - **Source**: `components/00-infrastructure/keycloak/`
5. **Usage** - Create users, manage realms
6. **Troubleshooting** - Pod not ready, realm import failures
7. **Alternatives** - Auth0, Okta, Dex
   - **Source**: https://auth0.com/, https://www.okta.com/, https://dexidp.io/
8. **Next Steps** - External LDAP integration, MFA

**Sources to Verify**:
- [ ] https://www.keycloak.org/documentation (official docs)
- [ ] https://www.keycloak.org/operator/installation (operator docs)
- [ ] https://access.redhat.com/documentation/en-us/red_hat_build_of_keycloak (Red Hat docs)
- [ ] https://github.com/keycloak/keycloak-operator (GitHub)

**Status**: 🔲 NOT STARTED

---

#### 1.3: Distributed Tracing Documentation

**Current Files**:
- `TRACING_ARCHITECTURE.md` (481 lines)
- TODO_TRACING.md (if exists in root)

**New File**: `docs/04-observability/distributed-tracing.md`

**Content Sections**:
1. **What is Distributed Tracing?** - Concept, W3C Trace Context
   - **Source**: https://www.w3.org/TR/trace-context/
2. **Architecture** - OpenTelemetry → Tempo → Grafana + Phoenix
   - **Source**: TRACING_ARCHITECTURE.md
3. **Installation**:
   - OpenTelemetry Operator
     - **Source**: https://opentelemetry.io/docs/kubernetes/operator/
   - Grafana Tempo
     - **Source**: https://grafana.com/docs/tempo/
   - Arize Phoenix
     - **Source**: https://docs.arize.com/phoenix/
4. **Configuration**:
   - OTEL Collector pipeline
   - Tempo storage backend
   - Grafana datasource
   - **Source**: `components/02-observability/tempo/`, `components/02-observability/otel-collector/`
5. **Usage** - View traces, correlate spans
6. **Troubleshooting** - No traces appearing, trace sampling
7. **Alternatives** - Jaeger (deprecated), Zipkin
   - **Source**: https://www.jaegertracing.io/, https://zipkin.io/
8. **Next Steps** - Trace sampling, trace-based alerting

**Sources to Verify**:
- [ ] https://www.w3.org/TR/trace-context/ (W3C standard)
- [ ] https://opentelemetry.io/docs/ (OTEL docs)
- [ ] https://grafana.com/docs/tempo/ (Tempo docs)
- [ ] https://docs.arize.com/phoenix/ (Phoenix docs)

**Status**: 🔲 NOT STARTED

---

#### 1.4: Istio Service Mesh Documentation

**Current Files**:
- Sections in various deployment docs
- `GATEWAY-ACCESS-KIND.md` (367 lines) - Gateway config

**New File**: `docs/02-service-mesh/istio.md`

**Content Sections**:
1. **What is Istio?** - Service mesh concept
   - **Source**: https://istio.io/latest/docs/concepts/what-is-istio/
2. **Architecture** - Control plane, data plane, Gateway API integration
   - **Source**: https://istio.io/latest/docs/ops/deployment/architecture/
3. **Installation**:
   - **Method 1**: Upstream Helm (Kind)
     - **Source**: https://istio.io/latest/docs/setup/install/helm/
   - **Method 2**: Sail Operator (OpenShift)
     - **Source**: https://docs.openshift.com/container-platform/latest/service_mesh/v3x/ossm-about.html
4. **Configuration**:
   - mTLS STRICT mode
   - Gateway API resources
   - VirtualService, DestinationRule
   - **Source**: `components/00-infrastructure/istio-config/`
5. **Usage** - Traffic management, observability
6. **Troubleshooting** - Pod injection issues, mTLS failures
7. **Alternatives** - Linkerd, Consul
   - **Source**: https://linkerd.io/, https://www.consul.io/
8. **Next Steps** - Ambient mesh, multi-cluster

**Sources to Verify**:
- [ ] https://istio.io/latest/docs/ (main docs)
- [ ] https://docs.openshift.com/container-platform/latest/service_mesh/ (OpenShift SM)
- [ ] https://gateway-api.sigs.k8s.io/ (Gateway API)

**Status**: 🔲 NOT STARTED

---

### Priority 2: Operators and Platform

#### 2.1: Kagenti Operators Documentation

**Current Files**:
- `kagenti_operators.md` (1444 lines) - Comprehensive operators guide

**Action**: **KEEP** but restructure and split

**New Files**:
1. `docs/06-operators/platform-operator.md`
2. `docs/06-operators/agent-operator.md`
3. `docs/06-operators/crds.md`
4. `docs/06-operators/troubleshooting.md`

**Extract from kagenti_operators.md**:
- Platform Operator content → `platform-operator.md`
- Agent Operator content → `agent-operator.md`
- CRD specifications → `crds.md`
- Troubleshooting section → `troubleshooting.md`

**Apply Standard Template** to each new file

**Sources to Verify**:
- [ ] https://github.com/kagenti/kagenti-operator (GitHub)
- [ ] Operator CRD schemas
- [ ] Helm chart values

**Status**: 🔲 NOT STARTED

---

#### 2.2: OpenShift OLM Documentation

**Current Files**:
- `OLM_ARGOCD_COMPARISON.md` (1229 lines)
- `OLM_CONFIGURATION_REALITY.md` (635 lines)

**New File**: `docs/09-deployment/migration-guide.md`

**Content Sections**:
1. **What is OLM?** - Operator Lifecycle Manager concept
   - **Source**: https://olm.operatorframework.io/
2. **Architecture** - CatalogSource, Subscription, CSV, InstallPlan
   - **Source**: OLM_ARGOCD_COMPARISON.md
3. **Kubernetes vs OpenShift** - Key differences
   - **Source**: OLM_ARGOCD_COMPARISON.md
4. **Migration Strategy** - How to migrate components to OLM
   - **Source**: OLM_CONFIGURATION_REALITY.md
5. **What OLM Actually Reduces** - Reality check on line count savings
   - **Source**: OLM_CONFIGURATION_REALITY.md
6. **Troubleshooting** - Subscription not installing, InstallPlan pending
7. **Alternatives** - Helm, Kustomize (when NOT to use OLM)
8. **Next Steps** - Migrate remaining operators

**Sources to Verify**:
- [ ] https://olm.operatorframework.io/ (main docs)
- [ ] https://docs.openshift.com/container-platform/latest/operators/ (OpenShift OLM)

**Status**: 🔲 NOT STARTED

---

### Priority 3: Deployment and Operations

#### 3.1: Quick Start Guide

**Current File**:
- `QUICK-START.md` (506 lines)

**New File**: `docs/00-getting-started/quick-start.md`

**Content Sections**:
1. **Prerequisites** - Tools needed (kubectl, kind, helm, argocd CLI)
2. **15-Minute Deployment** - Step-by-step local deployment
3. **Verification** - How to check everything is running
4. **Access Services** - URLs for Grafana, Kiali, Phoenix, Kagenti UI
5. **Next Steps** - Where to go from here

**Apply Standard Template**

**Sources to Verify**:
- [ ] https://kind.sigs.k8s.io/ (Kind docs)
- [ ] https://kubernetes.io/docs/tasks/tools/ (kubectl)
- [ ] https://helm.sh/docs/ (Helm)

**Status**: 🔲 NOT STARTED

---

#### 3.2: OpenShift Deployment Guides

**Current Files**:
- `OPENSHIFT.md` (815 lines)
- `OPENSHIFT-LOCAL-SETUP.md` (654 lines)

**New Files**:
1. `docs/09-deployment/openshift-local.md` (CRC setup)
2. `docs/09-deployment/openshift-stage.md` (Staging deployment)
3. `docs/09-deployment/openshift-prod.md` (Production deployment)

**Extract content from current files and apply standard template**

**Sources to Verify**:
- [ ] https://docs.openshift.com/ (OpenShift docs)
- [ ] https://developers.redhat.com/products/openshift-local (CRC)

**Status**: 🔲 NOT STARTED

---

### Priority 4: Security and Operations

#### 4.1: Security Documentation

**Current Files**:
- `ENCRYPTION_ARCHITECTURE.md` (417 lines)
- `PRODUCTION_SECURITY_ROADMAP.md` (313 lines)
- `SECURITY-MONITORING-ACCESS.md` (412 lines)

**New Files**:
1. `docs/08-security/encryption.md`
2. `docs/08-security/security-roadmap.md`
3. `docs/08-security/secrets-management.md`

**Apply Standard Template**

**Sources to Verify**:
- [ ] https://cert-manager.io/docs/ (TLS certificates)
- [ ] https://kubernetes.io/docs/concepts/configuration/secret/ (Secrets)

**Status**: 🔲 NOT STARTED

---

#### 4.2: Operations Documentation

**Current Files**:
- `SOP-PLATFORM-OPERATIONS.md` (649 lines)
- `INTEGRATION_TESTS.md` (764 lines)

**New Files**:
1. `docs/10-operations/monitoring.md`
2. `docs/10-operations/troubleshooting.md`
3. `docs/10-operations/testing.md`

**Apply Standard Template**

**Sources to Verify**:
- [ ] https://prometheus.io/docs/ (Prometheus)
- [ ] https://grafana.com/docs/grafana/ (Grafana)

**Status**: 🔲 NOT STARTED

---

### Priority 5: Deprecated/Archive

**Files to Move to `99-appendix/deprecated/`**:

- [ ] `CLEANUP.md` (713 lines) - Old cleanup plan
- [ ] `PLATFORM-STATUS.md` (366 lines) - Point-in-time status report
- [ ] `PLATFORM-VALIDATION-REPORT.md` (603 lines) - Old validation report
- [ ] `DOCUMENTATION_VERIFICATION_SUMMARY.md` (398 lines) - Old verification
- [ ] `LINK_VERIFICATION_CHECKLIST.md` (348 lines) - Old checklist
- [ ] `NEXT-STEPS.md` (780 lines) - Superseded by new docs
- [ ] `KAGENTI_DEPS_DECOMPOSITION.md` (374 lines) - Old dependency analysis

**Action**: Move these files to deprecated/ with a README explaining why they're deprecated

---

## Source Link Verification Procedure

For **every subsection** in every document:

### Step 1: Identify Source

Find the authoritative source for the information:
- Official project documentation
- GitHub repository
- Blog posts from maintainers
- Conference talks
- Academic papers

### Step 2: Verify URL

```bash
# Check URL returns 200
curl -I https://example.com/docs | grep "HTTP/"

# Expected: HTTP/2 200
```

### Step 3: Verify Content

- [ ] Does the source actually contain the information we're citing?
- [ ] Is the source current (not deprecated)?
- [ ] Is there a more specific/better source?

### Step 4: Add to Document

```markdown
**Source**: [Descriptive Title](https://example.com/specific/page#anchor)
```

### Step 5: Track Verification

Create `docs/99-appendix/verified-sources.md` with:
- [ ] List of all sources used
- [ ] Verification date
- [ ] Notes about version compatibility

---

## Execution Plan

### Week 1: Structure and Priority 1

**Day 1-2**:
- [ ] Create new directory structure
- [ ] Create index README.md files
- [ ] Update main docs/README.md with new structure

**Day 3-4**:
- [ ] Migrate ArgoCD documentation
- [ ] Migrate Keycloak documentation
- [ ] Verify all sources

**Day 5**:
- [ ] Migrate Distributed Tracing documentation
- [ ] Migrate Istio documentation
- [ ] Verify all sources

### Week 2: Priority 2 and 3

**Day 1-2**:
- [ ] Split and migrate Kagenti Operators documentation
- [ ] Migrate OLM documentation
- [ ] Verify all sources

**Day 3-4**:
- [ ] Migrate Quick Start guide
- [ ] Migrate OpenShift deployment guides
- [ ] Verify all sources

**Day 5**:
- [ ] Review and test all Week 1-2 documentation
- [ ] Fix broken links and cross-references

### Week 3: Priority 4 and 5, Finalization

**Day 1-2**:
- [ ] Migrate Security documentation
- [ ] Migrate Operations documentation
- [ ] Verify all sources

**Day 3**:
- [ ] Move deprecated files to 99-appendix/deprecated/
- [ ] Create deprecation README

**Day 4**:
- [ ] Final review of all documentation
- [ ] Test all commands and code examples
- [ ] Verify all cross-references

**Day 5**:
- [ ] Update main docs/README.md with complete TOC
- [ ] Create docs/99-appendix/changelog.md
- [ ] Publish updated documentation

---

## Success Criteria

### Documentation Quality

- [ ] Every document has TOC
- [ ] Every document follows standard template
- [ ] Every subsection has verified source link
- [ ] Every code example has been tested
- [ ] Every command has expected output
- [ ] All cross-references are bidirectional

### Organization

- [ ] Clear directory structure by stack component
- [ ] Logical progression for new users (00 → 10)
- [ ] Easy to find information by topic, environment, or role
- [ ] No duplicate content across files

### Accessibility

- [ ] Can onboard a new user in 15 minutes (quick start)
- [ ] Can find deployment guide for specific environment
- [ ] Can find troubleshooting for specific component
- [ ] Can find source material for every claim

### Maintenance

- [ ] Documentation roadmap defined
- [ ] Change log maintained
- [ ] Source verification procedure documented
- [ ] Review process defined

---

## Tracking Progress

Use this checklist to track completion:

### Phase 1: Structure ✅ COMPLETE

- [x] Create TODO_DOCS_CLEANUP.md
- [ ] Create new directory structure
- [ ] Create index README.md files
- [ ] Update main docs/README.md

### Phase 2: Priority 1 (Core Infrastructure)

- [ ] ArgoCD documentation
- [ ] Keycloak documentation
- [ ] Distributed Tracing documentation
- [ ] Istio documentation

### Phase 3: Priority 2 (Operators and Platform)

- [ ] Kagenti Operators documentation (split into 4 files)
- [ ] OpenShift OLM documentation

### Phase 4: Priority 3 (Deployment and Operations)

- [ ] Quick Start guide
- [ ] OpenShift deployment guides (3 files)

### Phase 5: Priority 4 (Security and Operations)

- [ ] Security documentation (3 files)
- [ ] Operations documentation (3 files)

### Phase 6: Priority 5 (Cleanup)

- [ ] Move deprecated files
- [ ] Create deprecation README
- [ ] Final review

---

## Next Steps

1. **Review this plan** - Get team feedback
2. **Start with Quick Win** - Migrate Quick Start guide first (easiest, highest value)
3. **Iterate through Priority 1** - Core infrastructure components
4. **Regular check-ins** - Daily progress updates
5. **Continuous verification** - Verify sources as you go, don't batch

---

**IMPORTANT**: Do NOT start migration until this plan is reviewed and approved.

**Estimated Total Time**: 3 weeks (15 working days)

---

**Last Updated**: 2025-11-10
**Author**: Platform Engineering Team
**Status**: Ready for Review
