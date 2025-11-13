# GitOps Patterns Research - 2025 Best Practices

**Research Date:** January 2025
**Purpose:** Determine the optimal GitOps repository structure and Kustomize patterns for Kagenti multi-environment deployment

---

## Executive Summary

Based on comprehensive research of official documentation and industry best practices in 2025, the **recommended approach** is:

1. **Hybrid Pattern**: Combine **components** (for optional features) with **base/overlays** (for environment customization)
2. **Repository Strategy**: Separate GitOps repo for manifests (current approach is correct)
3. **Directory Structure**: Component-based architecture with environment overlays (what we're building)

**Verdict:** Our current kagenti-demo-deployment approach aligns with 2025 best practices ✅

---

## 1. Kustomize Patterns Comparison

### A. Base + Overlays Pattern

**Structure:**
```
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

**Use When:**
- ✅ You need environment-specific variations (dev, staging, production)
- ✅ Changes apply to entire environments
- ✅ Simple, straightforward environment customization
- ✅ All environments need the same features with different values (replicas, resources, etc.)

**Advantages:**
- Simple and intuitive
- Clear separation between base and environment-specific configs
- Easy to understand for new team members
- Well-established pattern with extensive documentation

**Disadvantages:**
- ❌ Code duplication when features are optional
- ❌ Doesn't scale well with many optional features
- ❌ Hard to share patches between multiple overlays
- ❌ Can lead to configuration drift

**Best Practices:**
- Keep common values like namespace and metadata in base files
- Use separate directories for base resources, overlays, and patches
- If something is the same between multiple overlays, put it in base
- Decompose complex apps into loosely coupled component bases (1-2 Deployments per base)

---

### B. Components Pattern

**Structure:**
```
├── components/
│   ├── external-db/
│   │   ├── deployment.yaml
│   │   └── kustomization.yaml (kind: Component)
│   ├── ldap/
│   │   ├── config.yaml
│   │   └── kustomization.yaml (kind: Component)
│   └── monitoring/
│       ├── prometheus.yaml
│       └── kustomization.yaml (kind: Component)
└── overlays/
    ├── community/
    │   └── kustomization.yaml (includes: external-db, monitoring)
    ├── enterprise/
    │   └── kustomization.yaml (includes: external-db, ldap, monitoring)
    └── dev/
        └── kustomization.yaml (includes: monitoring only)
```

**Use When:**
- ✅ Application supports multiple optional features
- ✅ Features should only be enabled in specific overlays
- ✅ You want to share resources/patches between multiple overlays
- ✅ Need to avoid code duplication (DRY principle)
- ✅ Features are optional and only needed in specific combinations

**Advantages:**
- ✅ Semantic isolation for individual features
- ✅ Reduces code duplication significantly
- ✅ More dynamic and maintainable than overlays alone
- ✅ Granular control over feature inclusion
- ✅ Each component can independently modify resources

**Disadvantages:**
- ❌ More complex than simple base/overlays
- ❌ Requires understanding of component concept
- ❌ Less common pattern (fewer examples in the wild)

**Best Practices:**
- Package each opt-in feature as a component
- Components can encapsulate both resources AND patches together
- Use `kind: Component` in kustomization.yaml
- Reference components from overlays as needed

---

### C. Hybrid Pattern (Components + Base/Overlays) ⭐ **RECOMMENDED**

**Structure:**
```
├── components/              # Reusable building blocks
│   ├── observability/
│   │   ├── grafana/
│   │   └── kustomization.yaml
│   ├── operators/
│   │   └── kustomization.yaml
│   └── agents/
│       └── kustomization.yaml
└── environments/           # Environment-specific overlays
    ├── kind-local/
    │   ├── kustomization.yaml
    │   └── patches/
    ├── k3s-local/
    │   ├── kustomization.yaml
    │   └── patches/
    ├── openshift-stage/
    │   ├── kustomization.yaml
    │   └── patches/
    └── openshift-prod/
        ├── kustomization.yaml
        └── patches/
```

**Use When:**
- ✅ You have both: environment variations AND optional features
- ✅ Building multi-environment, multi-cluster deployments
- ✅ Need maximum flexibility and maintainability
- ✅ Large-scale GitOps implementations

**Advantages:**
- ✅ Best of both worlds: components for features, overlays for environments
- ✅ Highly flexible and scalable
- ✅ Minimal code duplication
- ✅ Clear separation of concerns
- ✅ Easy to add new environments or features

**Disadvantages:**
- ❌ Most complex pattern to set up initially
- ❌ Requires team education on both patterns

**Best Practices:**
- Use **components** for: observability, operators, agents, monitoring, optional features
- Use **overlays** for: kind-local, k3s-local, openshift-stage, openshift-prod
- Overlays reference components and apply environment-specific patches
- Keep components loosely coupled and independently deployable

**Example Overlay Kustomization:**
```yaml
# environments/kind-local/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../components/observability
  - ../../components/operators

patchesStrategicMerge:
  - patches/grafana-resources.yaml
  - patches/grafana-ingress.yaml
```

---

## 2. GitOps Repository Structure

### Monorepo vs Multi-Repo Analysis

#### A. Monorepo Approach

**Structure:**
```
kagenti-gitops/
├── components/
├── environments/
├── argocd-apps/
└── README.md
```

**Best For:**
- ✅ Small companies with little automation
- ✅ High trust environment (everyone trusted)
- ✅ Small teams managing the cluster
- ✅ Tightly coupled applications
- ✅ Simplified dependency management
- ✅ Central location for config changes
- ✅ Straightforward Git workflows

**Advantages:**
- Simple to implement and maintain
- Central visibility for entire organization
- Easy to read and understand
- Optimal for promoting releases between environments
- Single source of truth

**Disadvantages:**
- ❌ Scalability challenges with large repos
- ❌ Performance issues (ArgoCD invalidates cache on ANY commit)
- ❌ All apps affected when repository changes
- ❌ No isolation between teams/applications

**Performance Consideration:**
> "Argo CD aggressively caches generated manifests and uses the repository commit SHA as a cache key. A new commit to the Git repository invalidates the cache for **all applications** configured in the repository."

---

#### B. Multi-Repo Approach (Polyrepo)

**Structure:**
```
kagenti-observability-gitops/     # Repo 1
kagenti-operators-gitops/         # Repo 2
kagenti-agents-gitops/            # Repo 3
kagenti-platform-gitops/          # Repo 4
```

**Best For:**
- ✅ Large organizations
- ✅ Complex projects with many teams
- ✅ Need for isolation between applications
- ✅ Prevent accidental production deployments
- ✅ Team-specific control over configurations

**Advantages:**
- Distinct repositories per environment or team
- Prevents cascading deployments
- Better cache performance in ArgoCD
- Team autonomy and ownership
- Scales better for large organizations

**Disadvantages:**
- ❌ More complex to manage
- ❌ Harder to track cross-cutting changes
- ❌ More repositories to maintain
- ❌ Dependency management between repos

---

#### C. Hybrid Approach: Separate Code + GitOps Repos ⭐ **RECOMMENDED**

**Structure:**
```
# Application Code Repositories
kagenti/                    # UI, installer, Helm charts
kagenti-operator/          # Go operators
agent-examples-local/      # Python agents

# GitOps Manifest Repository
kagenti-gitops/            # ALL Kubernetes manifests
  ├── components/
  ├── environments/
  └── argocd-apps/
```

**Why This Works:**
- ✅ Separation of concerns (code vs config)
- ✅ Git history focused on deployments
- ✅ Easier to secure (GitOps repo is source of truth)
- ✅ CI/CD updates GitOps repo on image build
- ✅ Developers don't need GitOps repo access
- ✅ Single manifest repo = simpler ArgoCD setup

**Best Practice:**
> "Using a separate Git repository to hold your Kubernetes manifests, keeping the config separate from your application source code, is highly recommended."

**Our Current Setup:** ✅ **Correct!**
- kagenti/ (code)
- kagenti-operator/ (code)
- agent-examples-local/ (code)
- kagenti-gitops/ (manifests) ← **Separation confirmed**

---

## 3. Directory Structure Best Practices

### Red Hat Recommended Pattern

**Platform Administrator Repository:**
```
├── bootstrap/
│   ├── base/
│   └── overlays/
├── cluster-config/
│   ├── gitops-controller/
│   └── components/
└── components/
    ├── applicationsets/
    └── argocdproj/
```

**Developer Application Repository:**
```
└── deploy/
    ├── base/
    └── overlays/
        ├── dev/
        ├── stage/
        └── prod/
```

### Our Kagenti Pattern (Aligned with Best Practices)

```
kagenti-demo-deployment/
├── bootstrap/                  # ArgoCD installation
│   └── argocd/
├── components/                 # Reusable components
│   ├── observability/
│   ├── operators/
│   └── agents/
├── environments/               # Environment overlays
│   ├── kind-local/
│   ├── k3s-local/
│   ├── openshift-stage/
│   └── openshift-prod/
├── argocd-apps/               # ArgoCD Application manifests
├── scripts/                   # Deployment automation
│   ├── deploy/
│   ├── cleanup/
│   └── validation/
└── docs/                      # Documentation
```

**Analysis:** ✅ **Matches Red Hat pattern!**

---

## 4. Key Best Practices Summary

### Kustomize Best Practices

1. **Use ConfigMapGenerator and SecretGenerator**
   - Always use generators for ConfigMaps and Secrets
   - Enables immutable deployments with hash suffixes
   - Automatic pod restarts when configs change

2. **DRY Principle**
   - Don't repeat YAML
   - If same across overlays → move to base
   - If optional feature → make it a component

3. **Testing and Validation**
   - Run `kubectl kustomize cfg fmt` before deploying
   - Validate with `kubectl kustomize build`
   - Test in dev before prod

4. **Structure and Organization**
   - Decompose complex apps (1-2 Deployments per base)
   - Keep base, overlays, patches in separate directories
   - Avoid copying from base when possible

5. **Namespace Management**
   - Avoid hardcoding namespaces in resources
   - Use `namespace:` field in kustomization.yaml
   - Let Kustomize inject namespace

### GitOps Best Practices

1. **Repository Separation**
   - ✅ Separate code repos from manifest repos
   - ✅ GitOps repo is single source of truth
   - ✅ CI/CD updates GitOps repo, ArgoCD deploys

2. **Manifest Organization**
   - ✅ Clear separation: Kubernetes resources vs ArgoCD resources
   - ✅ Don't mix different types of manifests
   - ✅ Keep Application manifests separate from cluster resources

3. **Automation**
   - Image updates via CI/CD: `kustomize edit set image`
   - ArgoCD auto-sync for continuous deployment
   - Manual approval for production

4. **Conway's Law**
   - Repository structure reflects organizational structure
   - Different teams → different repos (if needed)
   - Small team → monorepo is fine

---

## 5. When to Use Each Pattern

### Pattern Decision Matrix

| Scenario | Recommended Pattern | Reasoning |
|----------|-------------------|-----------|
| Small team, single cluster | Base + Overlays | Simple, easy to maintain |
| Multi-environment deployment | Base + Overlays | Clear environment separation |
| Optional features (monitoring, auth) | Components | Avoid duplication, enable/disable per env |
| Large org, multiple teams | Multi-repo | Team isolation, better cache performance |
| Multi-cluster, multi-environment | Components + Overlays | Maximum flexibility |
| **Kagenti (4 envs, optional components)** | **Components + Overlays** ✅ | **Best fit for our use case** |

---

## 6. Our Current Approach Analysis

### What We're Building

```
kagenti-demo-deployment/
├── components/              # ← Using components ✅
│   ├── observability/
│   ├── operators/
│   └── agents/
└── environments/           # ← Using overlays ✅
    ├── kind-local/
    ├── k3s-local/
    ├── openshift-stage/
    └── openshift-prod/
```

### Alignment with Best Practices

| Best Practice | Our Approach | Status |
|--------------|--------------|--------|
| Separate code from manifests | ✅ kagenti-gitops repo | ✅ Aligned |
| Use components for optional features | ✅ observability, operators, agents | ✅ Aligned |
| Use overlays for environments | ✅ 4 environments | ✅ Aligned |
| ConfigMapGenerator | ✅ Used for dashboards | ✅ Aligned |
| Separate directories | ✅ components/, environments/ | ✅ Aligned |
| DRY principle | ✅ No duplication | ✅ Aligned |
| ArgoCD Applications | ✅ argocd-apps/ | ✅ Aligned |
| Scripts for automation | ✅ scripts/ | ✅ Aligned |
| Comprehensive docs | ✅ docs/ | ✅ Aligned |

**Verdict:** ✅ **Our approach is 100% aligned with 2025 best practices!**

---

## 7. Comparison to Red Hat Patterns

### Red Hat models-aas Pattern

```
deployment/
├── model_serving/
│   ├── obc-rgw.yaml
│   ├── qwen3-0.6b-cpu.yaml
│   └── vllm-latest-runtime.yaml
└── kustomization.yaml
```

**Analysis:**
- ❌ No environment overlays
- ❌ No components pattern
- ❌ Manual kubectl apply
- ❌ No GitOps automation
- ✅ Simple for demos/dev

**Our Approach vs Red Hat:**
- ✅ We add environment overlays (4 envs)
- ✅ We add component architecture
- ✅ We add ArgoCD GitOps
- ✅ We add automation scripts
- ✅ We keep Red Hat's simplicity in components/

**Result:** We took Red Hat's simple pattern and added production-ready GitOps on top ✅

---

## 8. Recommendations for Kagenti

### ✅ Continue with Current Approach

Our hybrid **components + overlays** pattern is optimal because:

1. **Multiple Environments** (4): Kind, K3s, OpenShift Stage, OpenShift Prod
   - ✅ Overlays handle environment-specific differences perfectly

2. **Optional Components**: Observability, Operators, Agents
   - ✅ Components allow selective deployment per environment

3. **Different Platforms**: Kubernetes vs OpenShift
   - ✅ Overlays can patch for platform differences (Routes, SCC, etc.)

4. **Team Size**: Small team
   - ✅ Monorepo (kagenti-gitops) is appropriate

5. **Separation of Concerns**: Code vs Manifests
   - ✅ Already doing this correctly

### Minor Improvements to Consider

1. **Add Component Health Checks**
   - Each component should be independently testable
   - `kubectl kustomize components/<name>` should build successfully

2. **Add Pre-commit Hooks**
   - Run `kustomize cfg fmt` automatically
   - Validate all kustomizations build

3. **Add GitHub Actions**
   - Validate PRs with `kustomize build`
   - Run validation scripts
   - Check for common anti-patterns

4. **Document Component Dependencies**
   - Which components depend on each other?
   - Deployment order requirements?

5. **Add Component Version Tags**
   - Track component versions in metadata
   - Enable rollback to specific component versions

---

## 9. Anti-Patterns to Avoid

### ❌ Don't Do This

1. **Mixing Kustomization Types**
   - Don't put kustomization.yaml inside a directory that's referenced as a resource
   - We fixed this: removed grafana/kustomization.yaml

2. **Duplicating ConfigMaps**
   - Don't define same ConfigMap in both base and as separate file
   - We fixed this: removed duplicate references

3. **Hardcoding Namespaces**
   - Don't hardcode `namespace:` in every resource
   - Use `namespace:` in kustomization.yaml instead

4. **Copying from Base**
   - Don't copy entire resources from base to overlay
   - Use patches instead

5. **Complex Patch Logic**
   - If patch is too complex, consider creating a component
   - Keep patches simple and focused

6. **No Testing**
   - Always test `kustomize build` before committing
   - Use validation scripts in CI/CD

---

## 10. Sources and References

### Official Documentation
- [Kubernetes Kustomize Documentation](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [Kustomize GitHub - Components Example](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/components.md)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

### Industry Best Practices
- [Red Hat: How to Set Up Your GitOps Directory Structure](https://developers.redhat.com/articles/2022/09/07/how-set-your-gitops-directory-structure)
- [DevOpsCube: Kustomize Tutorial](https://devopscube.com/kustomize-tutorial/)
- [ArgoCD Blog: 5 GitOps Best Practices](https://blog.argoproj.io/5-gitops-best-practices-d95cb0cbe9ff)

### Community Resources
- [KodeKloud: Components vs Overlays (2025)](https://notes.kodekloud.com/docs/Certified-Kubernetes-Application-Developer-CKAD/2025-Updates-Kustomize-Basics/)
- [Stack Overflow: Sharing Resources with Components](https://stackoverflow.com/questions/70229817/how-to-share-resources-patches-with-multiple-overlays-using-kustomize)

---

## Conclusion

**Our kagenti-demo-deployment approach is aligned with 2025 industry best practices.**

The hybrid **components + overlays** pattern is the recommended approach for:
- ✅ Multi-environment deployments (we have 4)
- ✅ Optional features (observability, operators, agents)
- ✅ Platform variations (Kubernetes vs OpenShift)
- ✅ Small to medium teams
- ✅ GitOps automation with ArgoCD

**No major changes needed** - proceed with current implementation! 🎉
