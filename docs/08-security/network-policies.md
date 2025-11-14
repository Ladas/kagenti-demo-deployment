# Network Policies: Network Security and Segmentation

**Version**: 1.0
**Last Updated**: 2025-11-12
**Status**: Production Ready
**Audience**: Platform Engineers, Security Engineers, Network Engineers

Complete guide to Kubernetes NetworkPolicies for the Kagenti platform, covering default-deny strategies, namespace isolation, pod-to-pod restrictions, and defense-in-depth network security.

---

## Table of Contents

- [Overview](#overview)
- [Current State: No Network Policies](#current-state-no-network-policies)
- [NetworkPolicy Fundamentals](#networkpolicy-fundamentals)
- [Default-Deny Strategy](#default-deny-strategy)
- [Namespace Isolation](#namespace-isolation)
- [Application-Level Policies](#application-level-policies)
- [Infrastructure Policies](#infrastructure-policies)
- [Istio Integration](#istio-integration)
- [Policy Testing and Validation](#policy-testing-and-validation)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Alternatives](#alternatives)
- [Next Steps](#next-steps)
- [References](#references)

---

## Overview

**Purpose**: Implement defense-in-depth network security by controlling pod-to-pod and external traffic using Kubernetes NetworkPolicies.

**What You Get**:
- ✅ Default-deny ingress/egress policies
- ✅ Namespace isolation (team1, team2, observability)
- ✅ Application-specific traffic rules
- ✅ Integration with Istio service mesh
- ✅ Policy validation and testing tools
- ✅ Compliance-ready network segmentation
- ✅ Protection against lateral movement after compromise

**Key Principle**: **Default-deny with explicit allow**. All traffic is blocked by default, and only explicitly permitted traffic flows are allowed. This limits the blast radius of a security breach.

**Source**: Based on [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/), [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

---

## Current State: No Network Policies

### Security Gap

**Current Behavior**: Without NetworkPolicies, all pods can communicate freely:

```
❌ Current State (No NetworkPolicies):

┌─────────────────────────────────────────────────┐
│ Namespace: team1                                │
│                                                 │
│  research-agent ←──────→ code-agent            │
│       ↕                       ↕                 │
│  orchestrator-agent ←──→ any-other-pod         │
│       ↕                       ↕                 │
│  PostgreSQL ←────────────→ Redis               │
│                                                 │
└─────────────────────────────────────────────────┘
         ↕ (unrestricted)
┌─────────────────────────────────────────────────┐
│ Namespace: observability                        │
│                                                 │
│  Grafana ←────────────────→ Prometheus         │
│       ↕                       ↕                 │
│  Tempo ←──────────────────→ Phoenix            │
│                                                 │
└─────────────────────────────────────────────────┘

ALL pods can talk to ALL other pods in the cluster!
```

**Risk**: If an attacker compromises `research-agent`, they can:
- 🔴 Connect to PostgreSQL (steal data)
- 🔴 Connect to Redis (poison cache)
- 🔴 Connect to other agents (lateral movement)
- 🔴 Connect to observability stack (disable monitoring)

**Source**: [CIS Benchmark 5.3.2](https://www.cisecurity.org/benchmark/kubernetes)

---

### Target State: Default-Deny with Explicit Allow

```
✅ Target State (NetworkPolicies enabled):

┌─────────────────────────────────────────────────┐
│ Namespace: team1                                │
│                                                 │
│  research-agent ──✅──→ orchestrator-agent     │
│       ↕ (OTEL)              ↕ (DB)              │
│  OTEL Collector       PostgreSQL (allowed)     │
│       ↕                       ❌                 │
│  ❌ Redis (denied)     code-agent (denied)     │
│                                                 │
└─────────────────────────────────────────────────┘
         ↕ (OTEL only)
┌─────────────────────────────────────────────────┐
│ Namespace: observability                        │
│                                                 │
│  Grafana ──✅──→ Prometheus (allowed)          │
│       ❌                       ❌                 │
│  Tempo (denied) ←──❌──→ Phoenix (denied)      │
│                                                 │
└─────────────────────────────────────────────────┘

Only explicitly allowed traffic flows!
```

**Benefit**: Attacker can only access explicitly permitted services, limiting lateral movement.

---

## NetworkPolicy Fundamentals

### How NetworkPolicies Work

NetworkPolicies are firewall rules for pods:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-frontend
  namespace: team1
spec:
  # Which pods this policy applies to (target)
  podSelector:
    matchLabels:
      app: backend

  # Policy types
  policyTypes:
  - Ingress  # Control incoming traffic
  - Egress   # Control outgoing traffic

  # Allow ingress from frontend pods
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080

  # Allow egress to database
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

**How It Works**:
1. `podSelector` targets which pods the policy applies to
2. `ingress` rules define allowed incoming traffic
3. `egress` rules define allowed outgoing traffic
4. Traffic not explicitly allowed is **denied by default** (once a policy exists for that pod)

**Source**: [Kubernetes NetworkPolicy API](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#networkpolicy-v1-networking-k8s-io)

---

### Selectors: Targeting Pods

NetworkPolicies use three types of selectors:

#### 1. podSelector (Pods in Same Namespace)

```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: frontend  # Pods with label app=frontend
```

#### 2. namespaceSelector (All Pods in Namespace)

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: team1  # All pods in namespace with label name=team1
```

#### 3. Combined (Specific Pods in Specific Namespace)

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: team1
    podSelector:
      matchLabels:
        app: frontend  # Pods with app=frontend in namespace with name=team1
```

#### 4. CIDR Blocks (External IPs)

```yaml
egress:
- to:
  - ipBlock:
      cidr: 203.0.113.0/24  # Allow egress to this IP range
      except:
      - 203.0.113.5/32      # Except this specific IP
```

**Source**: [NetworkPolicy Selectors](https://kubernetes.io/docs/concepts/services-networking/network-policies/#behavior-of-to-and-from-selectors)

---

### Policy Types: Ingress vs Egress

**Ingress**: Controls incoming traffic to pods

```yaml
policyTypes:
- Ingress

ingress:
- from:
  - podSelector:
      matchLabels:
        role: frontend
  ports:
  - protocol: TCP
    port: 8080
```

**Egress**: Controls outgoing traffic from pods

```yaml
policyTypes:
- Egress

egress:
- to:
  - podSelector:
      matchLabels:
        role: database
  ports:
  - protocol: TCP
    port: 5432
```

**Both**: Control ingress AND egress

```yaml
policyTypes:
- Ingress
- Egress

ingress:
- from: [...]

egress:
- to: [...]
```

---

## Default-Deny Strategy

### Step 1: Default-Deny All Traffic

**Best Practice**: Start with default-deny, then add explicit allows.

```yaml
# Deny all ingress and egress in namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: team1
spec:
  podSelector: {}  # Empty selector = all pods
  policyTypes:
  - Ingress
  - Egress
```

**Effect**:
- ❌ No pods can receive traffic (ingress)
- ❌ No pods can send traffic (egress)
- ✅ DNS still works (kube-dns is in different namespace)

**Apply to all namespaces**:

```bash
for NAMESPACE in team1 team2 observability keycloak; do
  kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
done
```

**Source**: [Default Deny NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-ingress-and-all-egress-traffic)

---

### Step 2: Allow DNS

**Problem**: Default-deny blocks DNS lookups.

**Solution**: Allow egress to kube-dns on port 53.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: team1
spec:
  podSelector: {}  # All pods
  policyTypes:
  - Egress
  egress:
  # Allow DNS (UDP 53)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**Effect**: All pods can resolve DNS names.

---

### Step 3: Allow Kubernetes API Access

**Problem**: Pods need to access Kubernetes API (ServiceAccount tokens).

**Solution**: Allow egress to Kubernetes API server.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kube-api
  namespace: team1
spec:
  podSelector: {}  # All pods
  policyTypes:
  - Egress
  egress:
  # Allow Kubernetes API (TCP 443)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: default
    ports:
    - protocol: TCP
      port: 443
```

**Alternative**: Use CIDR for API server IP

```yaml
egress:
- to:
  - ipBlock:
      cidr: 10.96.0.1/32  # Kubernetes service IP
  ports:
  - protocol: TCP
    port: 443
```

---

## Namespace Isolation

### Isolate Team Namespaces

**Goal**: Prevent team1 pods from accessing team2 pods.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace-only
  namespace: team1
spec:
  podSelector: {}  # All pods in team1
  policyTypes:
  - Ingress
  ingress:
  # Only allow traffic from same namespace
  - from:
    - podSelector: {}  # Any pod in this namespace
```

**Effect**:
- ✅ team1 pods can talk to each other
- ❌ team2 pods CANNOT talk to team1 pods
- ❌ observability pods CANNOT talk to team1 pods (blocked)

---

### Allow Observability Access

**Problem**: Observability tools (Prometheus, OTEL) need to scrape metrics.

**Solution**: Allow ingress from observability namespace.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-observability
  namespace: team1
spec:
  podSelector: {}  # All pods
  policyTypes:
  - Ingress
  ingress:
  # Allow Prometheus scraping
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: observability
    ports:
    - protocol: TCP
      port: 8080  # Metrics port
```

---

### Allow Istio Sidecar Communication

**Problem**: Istio sidecars need to communicate with istiod (control plane).

**Solution**: Allow egress to istio-system namespace.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-istio
  namespace: team1
spec:
  podSelector: {}  # All pods
  policyTypes:
  - Egress
  egress:
  # Allow Istio control plane
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: istio-system
    ports:
    - protocol: TCP
      port: 15012  # istiod xDS

  # Allow Istio telemetry
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: istio-system
    ports:
    - protocol: TCP
      port: 15014  # Telemetry
```

**Source**: [Istio NetworkPolicy Requirements](https://istio.io/latest/docs/ops/deployment/requirements/)

---

## Application-Level Policies

### Example: Research Agent

**Architecture**:
```
research-agent needs:
- Ingress from: orchestrator-agent (port 8080)
- Egress to: OTEL Collector (port 4317)
- Egress to: OpenAI API (port 443, external)
- Egress to: Keycloak (port 8080, authentication)
```

**NetworkPolicy**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: research-agent-policy
  namespace: team1
spec:
  podSelector:
    matchLabels:
      app: research-agent

  policyTypes:
  - Ingress
  - Egress

  # Ingress rules
  ingress:
  # Allow from orchestrator-agent
  - from:
    - podSelector:
        matchLabels:
          app: orchestrator-agent
    ports:
    - protocol: TCP
      port: 8080

  # Egress rules
  egress:
  # 1. DNS (required for all pods)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53

  # 2. OTEL Collector (telemetry)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: observability
      podSelector:
        matchLabels:
          app: otel-collector
    ports:
    - protocol: TCP
      port: 4317  # OTLP gRPC

  # 3. Keycloak (authentication)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: keycloak
      podSelector:
        matchLabels:
          app: keycloak
    ports:
    - protocol: TCP
      port: 8080

  # 4. OpenAI API (external)
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0  # Allow all external IPs
    ports:
    - protocol: TCP
      port: 443
```

**Effect**:
- ✅ Orchestrator can call research-agent
- ✅ Research-agent can send telemetry to OTEL
- ✅ Research-agent can authenticate with Keycloak
- ✅ Research-agent can call OpenAI API
- ❌ Research-agent CANNOT access PostgreSQL (not in egress rules)
- ❌ Code-agent CANNOT call research-agent (not in ingress rules)

---

### Example: PostgreSQL Database

**Architecture**:
```
PostgreSQL needs:
- Ingress from: orchestrator-agent ONLY (port 5432)
- Egress to: None (stateful database, no external calls)
```

**NetworkPolicy**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-policy
  namespace: team1
spec:
  podSelector:
    matchLabels:
      app: postgresql

  policyTypes:
  - Ingress
  - Egress

  # Ingress rules
  ingress:
  # Only allow orchestrator-agent
  - from:
    - podSelector:
        matchLabels:
          app: orchestrator-agent
    ports:
    - protocol: TCP
      port: 5432

  # Egress rules
  egress:
  # Only DNS (no external access)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**Effect**:
- ✅ Orchestrator-agent can connect to PostgreSQL
- ❌ Research-agent CANNOT connect to PostgreSQL (not in ingress rules)
- ❌ PostgreSQL CANNOT make external calls (no egress except DNS)

**Security Benefit**: If PostgreSQL is compromised, attacker cannot exfiltrate data via network.

---

## Infrastructure Policies

### Observability Namespace

**Grafana Policy** (needs to query Prometheus, Tempo, Loki):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: grafana-policy
  namespace: observability
spec:
  podSelector:
    matchLabels:
      app: grafana

  policyTypes:
  - Ingress
  - Egress

  # Ingress rules
  ingress:
  # Allow from OAuth2-Proxy (authenticated users)
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: oauth2-proxy
    ports:
    - protocol: TCP
      port: 3000

  # Egress rules
  egress:
  # DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53

  # Prometheus datasource
  - to:
    - podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 9090

  # Tempo datasource
  - to:
    - podSelector:
        matchLabels:
          app: tempo
    ports:
    - protocol: TCP
      port: 3100

  # Loki datasource
  - to:
    - podSelector:
        matchLabels:
          app: loki
    ports:
    - protocol: TCP
      port: 3100

  # Keycloak (authentication)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: keycloak
    ports:
    - protocol: TCP
      port: 8080
```

---

### Keycloak Namespace

**Keycloak Policy** (needs to access PostgreSQL database):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: keycloak-policy
  namespace: keycloak
spec:
  podSelector:
    matchLabels:
      app: keycloak

  policyTypes:
  - Ingress
  - Egress

  # Ingress rules
  ingress:
  # Allow from all namespaces (authentication provider)
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 8080

  # Egress rules
  egress:
  # DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53

  # PostgreSQL database (same namespace)
  - to:
    - podSelector:
        matchLabels:
          app: postgresql
    ports:
    - protocol: TCP
      port: 5432
```

---

## Istio Integration

### NetworkPolicy vs Istio AuthorizationPolicy

Kubernetes NetworkPolicies and Istio AuthorizationPolicies provide **defense-in-depth**:

| Layer | Technology | Enforcement Point | Scope |
|-------|------------|-------------------|-------|
| **Layer 3/4** (Network) | Kubernetes NetworkPolicy | Linux kernel (iptables/eBPF) | IP addresses, ports |
| **Layer 7** (Application) | Istio AuthorizationPolicy | Envoy proxy (sidecar) | HTTP methods, paths, headers, JWT claims |

**Why Use Both?**
- ✅ **NetworkPolicy** blocks traffic at network layer (even if Istio bypassed)
- ✅ **AuthorizationPolicy** adds fine-grained application-level controls
- ✅ **Defense-in-depth** - two independent security layers

**Source**: [Istio Security Architecture](https://istio.io/latest/docs/concepts/security/)

---

### Example: Combined Policies

**NetworkPolicy** (Layer 3/4):

```yaml
# Allow research-agent → orchestrator-agent (port 8080 only)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: research-agent-network
  namespace: team1
spec:
  podSelector:
    matchLabels:
      app: orchestrator-agent
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: research-agent
    ports:
    - protocol: TCP
      port: 8080
```

**Istio AuthorizationPolicy** (Layer 7):

```yaml
# Only allow GET/POST, deny DELETE
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: orchestrator-authz
  namespace: team1
spec:
  selector:
    matchLabels:
      app: orchestrator-agent
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/team1/sa/research-agent"]
    to:
    - operation:
        methods: ["GET", "POST"]  # Only allow GET/POST
        paths: ["/api/*"]          # Only /api/* paths
```

**Combined Effect**:
- 🔒 NetworkPolicy blocks at network layer (port 8080 only, research-agent only)
- 🔒 AuthorizationPolicy blocks at application layer (GET/POST only, /api/* paths only)
- 🔒 If Istio bypassed, NetworkPolicy still enforces network-level restrictions

---

### Allow Istio Sidecar Traffic

**Problem**: Istio sidecars need to intercept traffic between pods.

**Solution**: Allow pod-to-pod traffic within namespace (Istio handles authorization).

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-istio-sidecar
  namespace: team1
spec:
  podSelector: {}  # All pods
  policyTypes:
  - Ingress
  - Egress

  ingress:
  # Allow from any pod in namespace (Istio will enforce AuthorizationPolicy)
  - from:
    - podSelector: {}

  egress:
  # Allow to any pod in namespace
  - to:
    - podSelector: {}
```

**Note**: This delegates authorization to Istio. Use **AuthorizationPolicy** for fine-grained control.

---

## Policy Testing and Validation

### Test Connectivity

**Before applying policies**, test connectivity:

```bash
# Test from research-agent to PostgreSQL
kubectl exec -n team1 deploy/research-agent -- \
  nc -zv postgresql.team1.svc.cluster.local 5432

# Expected (before NetworkPolicy): Connection succeeded
# Expected (after NetworkPolicy): Connection refused (if not allowed)
```

**Test specific policies**:

```bash
# Test DNS resolution (should always work)
kubectl exec -n team1 deploy/research-agent -- \
  nslookup kubernetes.default.svc.cluster.local

# Test OTEL Collector access
kubectl exec -n team1 deploy/research-agent -- \
  nc -zv otel-collector.observability.svc.cluster.local 4317

# Test unauthorized access (should fail)
kubectl exec -n team1 deploy/research-agent -- \
  nc -zv postgresql.team1.svc.cluster.local 5432
# Expected: Connection refused (if not in policy)
```

---

### Validate Policies

**Check applied policies**:

```bash
# List all NetworkPolicies in namespace
kubectl get networkpolicies -n team1

# Describe specific policy
kubectl describe networkpolicy research-agent-policy -n team1
```

**Check which policies apply to a pod**:

```bash
# Get pod labels
kubectl get pod research-agent-xxx -n team1 --show-labels

# Find matching NetworkPolicies
kubectl get networkpolicies -n team1 -o yaml | \
  grep -A 5 "podSelector"
```

---

### CNI Plugin Support

**NetworkPolicies require CNI plugin support**:

| CNI Plugin | NetworkPolicy Support | Notes |
|------------|----------------------|-------|
| **Calico** | ✅ Full support | Recommended for production |
| **Cilium** | ✅ Full support + extended features | eBPF-based, high performance |
| **Weave Net** | ✅ Full support | Simple setup |
| **Flannel** | ❌ No support | Overlay network only |
| **Canal** | ✅ Full support | Flannel + Calico NetworkPolicy |
| **Kind (kindnet)** | ⚠️ Limited support | Development only |

**For Kind clusters**:

```bash
# Check if NetworkPolicies are enforced
kubectl get pods -n kube-system | grep kindnet

# If using Kind, NetworkPolicies may not be enforced by default
# Consider using Calico for Kind:
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

**Source**: [Kubernetes Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)

---

### Policy Visualization

**Visualize NetworkPolicies**:

```bash
# Install kubectl-np plugin
kubectl krew install np-viewer

# Visualize policies in namespace
kubectl np-viewer -n team1

# Generate graph
kubectl np-viewer -n team1 -o graph
```

**Example output**:

```
research-agent (team1)
  ← orchestrator-agent (team1) [port 8080]
  → otel-collector (observability) [port 4317]
  → keycloak (keycloak) [port 8080]
  → external [port 443]

postgresql (team1)
  ← orchestrator-agent (team1) [port 5432]
  ✗ NO egress (except DNS)
```

**Source**: [np-viewer GitHub](https://github.com/runoncloud/kubectl-np-viewer)

---

## Best Practices

### 1. Start with Default-Deny

**Always** start with default-deny policy, then add explicit allows:

```yaml
# Step 1: Deny all
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

```yaml
# Step 2: Allow DNS
# Step 3: Allow specific application traffic
```

---

### 2. Label Namespaces

**Label namespaces** to simplify selectors:

```bash
# Label namespaces
kubectl label namespace team1 name=team1
kubectl label namespace observability name=observability
kubectl label namespace keycloak name=keycloak
```

**Use in policies**:

```yaml
namespaceSelector:
  matchLabels:
    name: observability  # Much clearer than kubernetes.io/metadata.name
```

---

### 3. Use Meaningful Names

**Good names** make policies self-documenting:

```yaml
# ✅ Good names
name: allow-orchestrator-to-database
name: deny-external-egress
name: allow-observability-scraping

# ❌ Bad names
name: policy-1
name: network-policy
name: temp-fix
```

---

### 4. Document Policy Intent

**Add annotations** to explain why policy exists:

```yaml
metadata:
  name: research-agent-policy
  annotations:
    description: "Allows research-agent to call orchestrator and external APIs"
    owner: "platform-team"
    security-ticket: "SEC-1234"
```

---

### 5. Test Before Production

**Always test policies** in non-production first:

```bash
# Apply to dev namespace first
kubectl apply -f network-policies.yaml -n team1-dev

# Test connectivity
./test-connectivity.sh

# If tests pass, apply to production
kubectl apply -f network-policies.yaml -n team1-prod
```

---

### 6. Monitor Policy Violations

**Enable audit logging** for denied connections:

```yaml
# Calico: Enable policy logging
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: default-deny-log
spec:
  order: 1000
  selector: all()
  types:
  - Ingress
  - Egress
  ingress:
  - action: Log
  - action: Deny
  egress:
  - action: Log
  - action: Deny
```

**Check logs**:

```bash
# View denied connections
kubectl logs -n kube-system -l k8s-app=calico-node | grep -i deny

# Example output:
# 2025-11-12 10:15:23 calico-node DROP: IN=cali123 SRC=10.244.1.5 DST=10.244.2.10 PROTO=TCP DPT=5432
```

---

### 7. Allow Istio Control Plane

**Always allow** Istio sidecar communication:

```yaml
# Allow Istio control plane access
egress:
- to:
  - namespaceSelector:
      matchLabels:
        name: istio-system
  ports:
  - protocol: TCP
    port: 15012  # xDS API
```

---

### 8. Gradual Rollout

**Rollout strategy**:

1. **Week 1**: Apply default-deny + DNS + Kubernetes API
2. **Week 2**: Add application-specific policies (test thoroughly)
3. **Week 3**: Monitor for denied connections, add missing rules
4. **Week 4**: Harden policies (remove overly permissive rules)

---

### 9. Use GitOps

**Store NetworkPolicies in Git**:

```
components/08-security/network-policies/
├── base/
│   ├── default-deny.yaml
│   ├── allow-dns.yaml
│   └── allow-kube-api.yaml
├── team1/
│   ├── research-agent.yaml
│   ├── orchestrator-agent.yaml
│   └── postgresql.yaml
└── observability/
    ├── grafana.yaml
    └── prometheus.yaml
```

**Deploy via ArgoCD**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: network-policies
spec:
  source:
    path: components/08-security/network-policies
  destination:
    server: https://kubernetes.default.svc
```

---

### 10. Regular Audits

**Audit policies quarterly**:

```bash
# Find policies without egress restrictions
kubectl get networkpolicies -A -o json | \
  jq '.items[] | select(.spec.egress == null) | .metadata.name'

# Find pods without NetworkPolicy
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.metadata.labels | length == 0) | "\(.metadata.namespace)/\(.metadata.name)"'
```

---

## Troubleshooting

### Issue: DNS Not Working After Applying Policy

**Symptoms**: Pods cannot resolve DNS names.

**Diagnosis**:

```bash
# Test DNS
kubectl exec -n team1 deploy/research-agent -- \
  nslookup kubernetes.default.svc.cluster.local

# Error: "server can't find kubernetes.default.svc.cluster.local: NXDOMAIN"
```

**Fix**: Add allow-dns policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: team1
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53  # Some DNS uses TCP
```

---

### Issue: Istio Sidecar Not Connecting to Control Plane

**Symptoms**: Pods with Istio sidecars stuck in "NotReady" state.

**Diagnosis**:

```bash
# Check sidecar logs
kubectl logs -n team1 research-agent-xxx -c istio-proxy

# Error: "connection to istiod refused"
```

**Fix**: Allow Istio control plane access:

```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: istio-system
  ports:
  - protocol: TCP
    port: 15012  # istiod xDS
  - protocol: TCP
    port: 15014  # Telemetry
```

---

### Issue: NetworkPolicy Not Enforced

**Symptoms**: Traffic flows even with deny policy.

**Diagnosis**:

```bash
# Check if CNI supports NetworkPolicies
kubectl get pods -n kube-system | grep -E "calico|cilium|weave|canal"

# If using Flannel (no NetworkPolicy support):
# kubectl get pods -n kube-system | grep flannel
```

**Fix**: Install CNI with NetworkPolicy support:

```bash
# Install Calico
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Restart pods to use new CNI
kubectl rollout restart deployment -n team1
```

---

### Issue: Prometheus Cannot Scrape Metrics

**Symptoms**: Prometheus shows targets as "down".

**Diagnosis**:

```bash
# Check Prometheus logs
kubectl logs -n observability deployment/prometheus | grep -i "scrape"

# Error: "connection refused" or "timeout"
```

**Fix**: Allow Prometheus scraping:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scraping
  namespace: team1
spec:
  podSelector: {}  # All pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: observability
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 8080  # Metrics port
```

---

### Issue: Pods Cannot Access External APIs

**Symptoms**: Pods fail to call external services (OpenAI, AWS, etc.).

**Diagnosis**:

```bash
# Test external connectivity
kubectl exec -n team1 deploy/research-agent -- \
  curl -I https://api.openai.com

# Error: "connection timed out" or "connection refused"
```

**Fix**: Allow external egress:

```yaml
egress:
- to:
  - ipBlock:
      cidr: 0.0.0.0/0  # Allow all external IPs
  ports:
  - protocol: TCP
    port: 443  # HTTPS
```

**More restrictive** (allow specific IPs):

```yaml
egress:
- to:
  - ipBlock:
      cidr: 13.107.42.0/24  # OpenAI IP range (example)
  ports:
  - protocol: TCP
    port: 443
```

---

## Alternatives

### Alternative 1: Istio AuthorizationPolicy Only

**Process**:
- Use only Istio AuthorizationPolicy for access control
- No Kubernetes NetworkPolicies

**Pros**:
- ✅ Layer 7 controls (HTTP methods, paths, JWT claims)
- ✅ Simpler to manage (single policy type)
- ✅ Better observability (Istio telemetry)

**Cons**:
- ❌ No network-layer protection if Istio bypassed
- ❌ Requires Istio on all pods (service mesh overhead)
- ❌ Doesn't protect non-HTTP traffic (databases, caches)

**When to Use**: Service mesh everywhere, HTTP-only workloads, prefer simplicity over defense-in-depth

**Source**: [Istio Authorization](https://istio.io/latest/docs/tasks/security/authorization/)

---

### Alternative 2: Calico GlobalNetworkPolicy

**Process**:
- Use Calico GlobalNetworkPolicy (cluster-wide policies)
- More powerful than Kubernetes NetworkPolicy

**Pros**:
- ✅ Cluster-wide policies (apply to all namespaces)
- ✅ More selectors (ServiceAccount, ports, protocols)
- ✅ Policy ordering (priority)
- ✅ Logging and audit

**Cons**:
- ❌ Vendor-specific (Calico only)
- ❌ Not portable to other CNIs
- ❌ More complex than Kubernetes NetworkPolicy

**When to Use**: Advanced policy requirements, centralized policy management, Calico already deployed

**Source**: [Calico GlobalNetworkPolicy](https://docs.projectcalico.org/reference/resources/globalnetworkpolicy)

---

### Alternative 3: Cilium NetworkPolicy (L7)

**Process**:
- Use Cilium NetworkPolicy with Layer 7 rules
- eBPF-based enforcement

**Pros**:
- ✅ Layer 7 filtering (HTTP, gRPC, Kafka, DNS)
- ✅ High performance (eBPF)
- ✅ Advanced observability (Hubble)
- ✅ Extended Kubernetes NetworkPolicy

**Cons**:
- ❌ Requires Cilium CNI
- ❌ More complex setup
- ❌ Steeper learning curve

**When to Use**: High-performance requirements, Layer 7 controls needed, eBPF expertise available

**Example** (Cilium L7 policy):

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: http-policy
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api/.*"
```

**Source**: [Cilium NetworkPolicy](https://docs.cilium.io/en/stable/policy/)

---

### Alternative 4: OPA Gatekeeper

**Process**:
- Use Open Policy Agent (OPA) to enforce policy at admission time
- Prevent non-compliant resources from being created

**Pros**:
- ✅ Prevent violations before deployment
- ✅ Policy-as-code (Rego language)
- ✅ Audit and dry-run modes
- ✅ Broad policy scope (not just network)

**Cons**:
- ❌ Doesn't enforce runtime traffic (admission-time only)
- ❌ Learning curve (Rego language)
- ❌ Requires OPA infrastructure

**When to Use**: Compliance requirements, policy-as-code workflows, shift-left security

**Example** (OPA policy requiring NetworkPolicy):

```rego
package kubernetes.admission

deny[msg] {
  input.request.kind.kind == "Deployment"
  not has_network_policy(input.request.object.metadata.namespace)
  msg := "Namespace must have NetworkPolicy before deploying"
}
```

**Source**: [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)

---

## Next Steps

### For Development

1. **Apply default-deny policies**:
   ```bash
   # Deny all traffic in team namespaces
   for NS in team1 team2; do
     kubectl apply -n $NS -f default-deny-all.yaml
   done
   ```

2. **Add DNS and Kubernetes API access**:
   ```bash
   kubectl apply -f allow-dns.yaml
   kubectl apply -f allow-kube-api.yaml
   ```

3. **Test connectivity**:
   ```bash
   # Test DNS
   kubectl exec -n team1 deploy/research-agent -- \
     nslookup kubernetes.default.svc.cluster.local

   # Test application connectivity
   ./test-connectivity.sh
   ```

### For Production

1. **Deploy Calico** (if not already installed):
   ```bash
   kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
   ```

2. **Label namespaces**:
   ```bash
   kubectl label namespace team1 name=team1 env=production
   kubectl label namespace observability name=observability
   ```

3. **Apply application-specific policies**:
   ```bash
   kubectl apply -f network-policies/team1/
   kubectl apply -f network-policies/observability/
   ```

4. **Enable policy logging** (Calico):
   ```bash
   kubectl apply -f calico-policy-logging.yaml
   ```

5. **Monitor for violations**:
   ```bash
   # Check Calico logs for denied connections
   kubectl logs -n kube-system -l k8s-app=calico-node | grep DROP
   ```

### Learn More

- [Encryption Guide](./encryption.md) - TLS and mTLS encryption
- [Security Roadmap](./security-roadmap.md) - Strategic security enhancements
- [Secrets Management](./secrets-management.md) - Secure secret handling
- [Istio Service Mesh](../02-service-mesh/istio.md) - AuthorizationPolicy integration

---

## References

### Official Documentation

- **Kubernetes NetworkPolicy**: [kubernetes.io/docs/concepts/services-networking/network-policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- **NetworkPolicy Recipes**: [github.com/ahmetb/kubernetes-network-policy-recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- **Calico NetworkPolicy**: [docs.projectcalico.org/security/calico-network-policy](https://docs.projectcalico.org/security/calico-network-policy)
- **Cilium NetworkPolicy**: [docs.cilium.io/en/stable/policy](https://docs.cilium.io/en/stable/policy/)
- **Istio Authorization**: [istio.io/latest/docs/tasks/security/authorization](https://istio.io/latest/docs/tasks/security/authorization/)

### Tools and Projects

- **Calico**: [projectcalico.org](https://www.projectcalico.org/)
- **Cilium**: [cilium.io](https://cilium.io/)
- **np-viewer**: [github.com/runoncloud/kubectl-np-viewer](https://github.com/runoncloud/kubectl-np-viewer)
- **OPA Gatekeeper**: [open-policy-agent.github.io/gatekeeper](https://open-policy-agent.github.io/gatekeeper/)

### Security Standards

- **CIS Kubernetes Benchmark 5.3.2**: [cisecurity.org/benchmark/kubernetes](https://www.cisecurity.org/benchmark/kubernetes)
- **NIST SP 800-190** (Container Security): [csrc.nist.gov/publications/detail/sp/800-190/final](https://csrc.nist.gov/publications/detail/sp/800-190/final)

### Internal Documentation

- **Main README**: [../../README.md](../../README.md)
- **Architecture Overview**: [../00-getting-started/architecture-overview.md](../00-getting-started/architecture-overview.md)
- **Encryption Guide**: [./encryption.md](./encryption.md)
- **Security Roadmap**: [./security-roadmap.md](./security-roadmap.md)
- **Secrets Management**: [./secrets-management.md](./secrets-management.md)
- **Istio Service Mesh**: [../02-service-mesh/istio.md](../02-service-mesh/istio.md)

### Repository

- **GitHub**: [Ladas/kagenti-demo-deployment](https://github.com/Ladas/kagenti-demo-deployment)
- **Network Policies**: `components/08-security/network-policies/`

---

**Last Updated**: 2025-11-12
**Document Version**: 1.0
**Maintained By**: Platform Engineering Team
**License**: Apache 2.0
