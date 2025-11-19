# ArgoCD GitOps Workflow for Local Development

**Last Updated**: 2025-11-17

This document provides quick reference for developing Kagenti platform components using ArgoCD and GitOps.

**See also**: [argocd_architecture.md](./argocd_architecture.md) for detailed architecture documentation.

---

## 🎯 Philosophy

**ALL changes to the Kind cluster happen via ArgoCD syncing from Git**. This ensures:
- ✅ Every change is tracked in Git
- ✅ No configuration drift
- ✅ Reproducible deployments
- ✅ Easy rollback
- ✅ Branch-based development

**🚫 No `kubectl apply` allowed** (except for ArgoCD installation and debugging only).

**✅ Always Git + `argocd app sync`**

---

## 🚀 Quick Start

This guide will help you deploy the Kagenti platform on a local Kind cluster in ~15-20 minutes.

### Prerequisites

**Required tools:**
- **Docker** - Container runtime (must be running)
- **kubectl** >= 1.27 - Kubernetes CLI
- **kind** >= 0.20 - Kubernetes in Docker
- **argocd** CLI >= 2.9 - ArgoCD CLI
- **Python** 3.11+ - For integration tests
- **Git** - Version control

**Install missing tools:**
```bash
# macOS (Homebrew)
brew install kubectl kind argocd python@3.11

# Linux (apt)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

# Verify Docker is running
docker ps
```

**Install Python dependencies:**
```bash
pip install -r tests/requirements.txt
```

### Step 1: Clone Repository

```bash
git clone https://github.com/redhat-et/kagenti-demo-deployment.git
cd kagenti-demo-deployment
```

### Step 2: Deploy Cluster (One Command)

```bash
./scripts/quick-redeploy.sh
```

**What happens during deployment:**
1. **Cleanup** (30s) - Destroys existing cluster if present
2. **Cluster creation** (2min) - Creates new Kind cluster with ingress
3. **ArgoCD install** (1min) - Installs ArgoCD in the cluster
4. **Bootstrap** (1min) - Creates root Application (App-of-Apps pattern)
5. **Agent images prompt** (interactive) - Build, load, or skip agent images
6. **Sync applications** (10-15min) - Deploys all platform components via ArgoCD
7. **Health check** (1min) - Verifies deployment success

**Agent images prompt (local only):**
- `y` - Build from source (2-5 min) - Choose if you have agent source code
- `n` - Load pre-built images (30s) - Choose if images are pre-built
- `skip` - Skip agents - Choose for platform-only deployment
- *CI mode: Automatically skips*

**Expected successful output:**
```
=== 🎉 Deployment Complete ===
✓ Cluster: kagenti-demo running
✓ ArgoCD: Healthy
✓ Applications synced: 24/24
✓ Platform pods: 48/48 Running

🌐 Access ArgoCD UI:
  URL: https://argocd.localtest.me:9443
  User: admin
  Pass: <saved to /tmp/argocd-pass.txt>

Next: ./scripts/platform-status.sh
```

### Step 3: Verify Deployment

```bash
# Comprehensive platform health check
./scripts/platform-status.sh
```

**What it checks:**
- ✅ All ArgoCD applications (health & sync status)
- ✅ Platform pods (Running/Ready)
- ✅ Gateway & TLS certificates
- ✅ Istio service mesh & mTLS
- ✅ Service accessibility (Keycloak, Grafana, etc.)
- ✅ OAuth authentication
- ✅ Integration tests (106 tests)

**Expected healthy output:**
```
=== Kagenti Platform Status ===

ArgoCD Applications: 24/24 Healthy, 24/24 Synced
Platform Pods: 48/48 Running (100%)
Gateway: external-gateway Ready
Certificates: 3/3 Ready
Istio mTLS: STRICT mode enabled

✓ All services accessible
✓ OAuth authentication working
✓ Integration tests: 106 passed

Status: 🟢 HEALTHY
```

### Step 4: Access Services

**Get ArgoCD credentials:**
```bash
# Admin password saved during deployment
cat /tmp/argocd-pass.txt
```

**Access platform services:**
```bash
# Web UIs (open in browser)
open https://argocd.localtest.me:9443       # ArgoCD
open https://grafana.localtest.me:9443      # Grafana (Dashboards, Logs, Metrics)
open https://keycloak.localtest.me:9443     # Keycloak (Identity Provider)
open https://kagenti.localtest.me:9443      # Kagenti UI
open https://kiali.localtest.me:9443        # Kiali (Service Mesh)
```

**Default credentials:**
- **ArgoCD**: `admin` / `<from /tmp/argocd-pass.txt>`
- **Grafana**: `admin` / `admin123` (dev only)
- **Keycloak**: `admin` / `admin123` (dev only)

### Troubleshooting Common Issues

**Issue: "Docker not running"**
```bash
# Start Docker Desktop or Docker daemon
# macOS: Open Docker Desktop app
# Linux: sudo systemctl start docker
```

**Issue: "Port already in use"**
```bash
# Check what's using ports 80, 443, 9443
lsof -i :80 -i :443 -i :9443

# Kill conflicting processes or stop other Kind clusters
kind delete cluster --name kagenti-demo
```

**Issue: "Pods stuck in ImagePullBackOff"**
```bash
# Verify images are loaded
docker exec kagenti-demo-control-plane crictl images | grep kagenti

# Reload agent images
./scripts/kind/04-load-agent-images.sh load
```

**Issue: "ArgoCD apps stuck OutOfSync"**
```bash
# Force sync specific app
argocd app sync <app-name> --force \
  --port-forward --port-forward-namespace argocd --grpc-web

# Sync all apps
argocd app sync -l argocd.argoproj.io/instance=kagenti-platform-kind \
  --port-forward --port-forward-namespace argocd --grpc-web
```

**Issue: "Deployment timeout after 20 minutes"**
```bash
# Monitor deployment progress
./scripts/monitor-argocd-apps.sh 1800  # 30-minute timeout

# Check specific app status
argocd app get <app-name> \
  --port-forward --port-forward-namespace argocd --grpc-web
```

**Issue: "OAuth2-Proxy pods not starting"**
```bash
# This is a known race condition with Keycloak
# Wait 2-5 minutes for Keycloak to fully start, then:
kubectl delete pod -n oauth2-proxy --all

# Pods will restart and should succeed
```

### Next Steps

**After successful deployment:**

1. **Explore the platform:**
   - Browse ArgoCD apps: https://argocd.localtest.me:9443
   - View logs in Grafana: https://grafana.localtest.me:9443
   - Check service mesh in Kiali: https://kiali.localtest.me:9443

2. **Import an agent** (see `.claude/skills/import-agent/SKILL.md`):
   ```bash
   # Example: Import a weather agent
   ./scripts/import-agents-via-kagenti.sh
   ```

3. **Make changes via GitOps** (see `.claude/skills/gitops-workflow/SKILL.md`):
   ```bash
   # Create branch, edit manifests, commit, sync
   git checkout -b feature/my-change
   # ... make changes ...
   argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web
   ```

4. **Run integration tests:**
   ```bash
   # All tests
   pytest tests/integration/ -v

   # Specific test suite
   pytest tests/integration/test_authentication.py -v
   ```

5. **Learn more:**
   - **ArgoCD Architecture**: [argocd_architecture.md](./argocd_architecture.md)
   - **Security & mTLS**: [docs/08-security/encryption.md](./docs/08-security/encryption.md)
   - **Testing Strategy**: [docs/CI_CD_TESTING.md](./docs/CI_CD_TESTING.md)
   - **All Claude Code Skills**: `.claude/skills/*/SKILL.md`

### Advanced Options

**For detailed deployment options, see**: `.claude/skills/deploy-cluster/SKILL.md`

**Manual step-by-step deployment:**
```bash
./scripts/kind/00-cleanup.sh
./scripts/kind/01-create-cluster.sh
./scripts/kind/02-install-argocd.sh
./scripts/kind/03-bootstrap-apps.sh
./scripts/kind/04-load-agent-images.sh build  # or 'load'
argocd app sync kagenti-platform-kind --port-forward --port-forward-namespace argocd --grpc-web
```

**For detailed health checks, see**: `.claude/skills/platform-health/SKILL.md`

---

## 🤖 Claude Code Skills

**Claude Code has specialized skills that are loaded on-demand when needed.**

### Workflow Skills

- **gitops-workflow**: Making changes via Git, ArgoCD sync, validation
- **tdd-workflow**: Test-driven development, running tests, validation
- **deploy-cluster**: Full cluster deployment and redeployment
- **import-agent**: Import agents into the platform

### Troubleshooting Skills

- **troubleshoot-pods**: Pod issues (CrashLoopBackOff, ImagePullBackOff, connectivity)
- **troubleshoot-argocd**: ArgoCD app issues (OutOfSync, Degraded, sync failures)
- **debug-ci**: CI/CD failures in GitHub Actions

### Observability Skills

- **check-alerts**: Check firing Grafana alerts, analyze alert status
- **check-logs**: Query Loki logs, search for errors
- **check-metrics**: Query Prometheus metrics, check resource usage
- **investigate-incident**: Perform RCA, create incident documentation
- **platform-health**: Comprehensive platform health checks

**Skills are located at**: `.claude/skills/*/SKILL.md`

**When to invoke**: Claude Code will automatically invoke skills when relevant, or you can explicitly request them.

---

## 📋 Quick Reference

### Essential Commands

```bash
# Deploy/redeploy cluster
./scripts/quick-redeploy.sh

# Platform health check
./scripts/platform-status.sh

# Sync ArgoCD application
argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# List all applications
argocd app list --port-forward --port-forward-namespace argocd --grpc-web

# Force sync (when needed)
argocd app sync <app-name> --force --prune --port-forward --port-forward-namespace argocd --grpc-web
```

### Making Changes (GitOps)

```bash
# 1. Create feature branch
git checkout -b feature/update-component

# 2. Make changes
vim components/path/to/file.yaml

# 3. Validate BEFORE committing
kustomize build components/path/ > /dev/null

# 4. Commit and push
git add components/path/
git commit -m "Update component"
git push

# 5. Sync from Git
argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# 6. Verify
./scripts/platform-status.sh
```

**For detailed GitOps workflow, see**: `.claude/skills/gitops-workflow/SKILL.md`

### Running Tests

```bash
# Fast validation (critical apps only)
pytest tests/validation/test_app_state.py -v --only-critical

# Full platform tests
pytest tests/ -v --html=report.html
```

**For detailed TDD workflow, see**: `.claude/skills/tdd-workflow/SKILL.md`

---

## 🔍 Access Services

```bash
# Get ArgoCD admin password
cat /tmp/argocd-pass.txt

# Access services via browser
open https://argocd.localtest.me:9443      # ArgoCD UI
open https://grafana.localtest.me:9443     # Grafana (Alerts, Logs, Metrics)
open https://keycloak.localtest.me:9443    # Keycloak Admin
open https://kagenti.localtest.me:9443     # Kagenti UI
open https://kiali.localtest.me:9443       # Kiali Service Mesh
```

**Default credentials:**
- ArgoCD: `admin` / `<from /tmp/argocd-pass.txt>`
- Grafana: `admin` / `admin123` (dev only)
- Keycloak: `admin` / `admin123` (dev only)

### Finding Alerts, Logs, and Metrics in Grafana

**Access Grafana**: https://grafana.localtest.me:9443

**Alerts**:
- **Alerting** → **Alert list**: Currently firing alerts
- **Alerting** → **Alert rules**: All 24 configured alert rules
- Every alert has a runbook in `docs/runbooks/alerts/<alert-uid>.md`
- **Skill**: `.claude/skills/check-alerts/SKILL.md`

**Logs** (Loki):
- **Explore** → Select **Loki** datasource → Enter LogQL query
- **Dashboards** → **Loki Logs**: Pre-built log dashboard
- **Skill**: `.claude/skills/check-logs/SKILL.md`

**Metrics** (Prometheus):
- **Explore** → Select **Prometheus** datasource → Enter PromQL query
- **Dashboards** → **Kubernetes / Compute Resources**: Resource metrics
- **Skill**: `.claude/skills/check-metrics/SKILL.md`

---

## 🎛️ Essential ArgoCD Commands

```bash
# List all applications with status
argocd app list --port-forward --port-forward-namespace argocd --grpc-web

# Get application details
argocd app get <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Sync application
argocd app sync <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Compare Git vs cluster
argocd app diff <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# View sync history
argocd app history <app-name> --port-forward --port-forward-namespace argocd --grpc-web

# Rollback to previous version
argocd app rollback <app-name> <revision-id> --port-forward --port-forward-namespace argocd --grpc-web

# Force sync (bypass cache)
argocd app sync <app-name> --force --port-forward --port-forward-namespace argocd --grpc-web

# Hard sync (force + prune orphaned resources)
argocd app sync <app-name> --force --prune --port-forward --port-forward-namespace argocd --grpc-web
```

**For ArgoCD troubleshooting, see**: `.claude/skills/troubleshoot-argocd/SKILL.md`

---

## 🔒 Security & Encryption

**ALL service-to-service communication uses Istio mTLS (STRICT mode)**.

### Sidecar Proxy Pattern

```
Application (HTTP) → Istio Sidecar (mTLS) → Network (encrypted) → Istio Sidecar → Application (HTTP)
```

**Key points:**
- ✅ Applications speak HTTP to local Istio sidecar (same pod)
- ✅ Istio sidecars automatically encrypt ALL network traffic
- ✅ NO plaintext HTTP travels over the network
- ✅ Automatic certificate rotation

### Verification

```bash
# Check sidecar injection (should show 2/2 for app + sidecar)
kubectl get pods -n <namespace>

# Check mTLS policies
kubectl get peerauthentication -A

# Debug specific pod
istioctl x describe pod <pod-name> -n <namespace>
```

**See also**:
- [docs/08-security/encryption.md](./docs/08-security/encryption.md) - Full encryption architecture
- [TODO_SECURITY.md](./TODO_SECURITY.md) - Production security roadmap

---

## 📁 Repository Structure

```
kagenti-demo-deployment/
├── .claude/skills/              # Claude Code skills (on-demand)
│   ├── check-alerts/            # Alert checking and analysis
│   ├── check-logs/              # Loki log querying
│   ├── check-metrics/           # Prometheus metrics querying
│   ├── investigate-incident/    # RCA and incident documentation
│   ├── platform-health/         # Health checks
│   ├── gitops-workflow/         # GitOps development workflow
│   ├── tdd-workflow/            # Test-driven development
│   ├── deploy-cluster/          # Cluster deployment
│   ├── troubleshoot-pods/       # Pod troubleshooting
│   ├── troubleshoot-argocd/     # ArgoCD troubleshooting
│   ├── debug-ci/                # CI/CD debugging
│   └── import-agent/            # Agent import workflow
│
├── argocd/
│   ├── bootstrap/kind/
│   │   └── root-app.yaml        # Root Application (App-of-Apps)
│   └── applications/
│       ├── base/                # Reusable templates
│       ├── kind-local/          # Kind-specific patches
│       └── helm/                # Helm-based apps
│
├── components/                  # LAYERED manifests
│   ├── 00-infrastructure/       # Wave 0: Gateway, cert-manager, Tekton, Istio
│   ├── 01-platform/             # Wave 10: Keycloak, operators, UI
│   ├── 02-observability/        # Wave 20: Grafana, Tempo, Phoenix
│   └── 03-applications/         # Wave 30: Agents
│
├── docs/
│   ├── runbooks/alerts/         # Alert-specific runbooks (24 alerts)
│   ├── 04-observability/        # Observability documentation
│   └── 08-security/             # Security documentation
│
├── scripts/
│   ├── quick-redeploy.sh        # Complete cluster redeploy
│   ├── platform-status.sh       # Health check + pytest
│   ├── monitor-argocd-apps.sh   # Monitor sync progress
│   ├── capture-platform-snapshot.sh  # Capture diagnostics
│   └── kind/                    # Kind cluster scripts
│
└── tests/
    ├── integration/             # Integration tests
    ├── validation/              # Platform validation tests
    └── e2e/                     # End-to-end tests
```

---

## 📚 Further Reading

### Core Documentation
- [argocd_architecture.md](./argocd_architecture.md) - ArgoCD architecture and sync waves
- [docs/08-security/encryption.md](./docs/08-security/encryption.md) - Encryption and mTLS
- [docs/CI_CD_TESTING.md](./docs/CI_CD_TESTING.md) - Integration testing strategy

### Observability
- [docs/runbooks/alerts/](./docs/runbooks/alerts/) - Alert-specific runbooks (24 alerts)
- [docs/04-observability/ALERT_TESTING_GUIDE.md](./docs/04-observability/ALERT_TESTING_GUIDE.md) - Alert testing
- [docs/04-observability/ADDING_NEW_ALERTS.md](./docs/04-observability/ADDING_NEW_ALERTS.md) - Adding alerts
- [TODO_INCIDENTS.md](./TODO_INCIDENTS.md) - Active incident tracking

### Roadmaps
- [TODO_TESTS.md](./TODO_TESTS.md) - Testing roadmap
- [TODO_SECURITY.md](./TODO_SECURITY.md) - Security roadmap (SPIRE integration + OpenShift)
- [TODO_ALERTS.md](./TODO_ALERTS.md) - Alert development roadmap

### External Resources
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Istio mTLS](https://istio.io/latest/docs/concepts/security/#mutual-tls-authentication)
- [Prometheus PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Loki LogQL](https://grafana.com/docs/loki/latest/logql/)

---

## 💡 Pro Tips

1. **Always validate before committing**: `kustomize build` catches errors early
2. **Use skills for complex tasks**: Claude Code skills provide guided workflows
3. **Check alerts first**: Before diving into logs, see if an alert fired
4. **Follow runbooks**: Every alert has proven investigation steps
5. **Capture snapshots**: Use `./scripts/capture-platform-snapshot.sh` before changes
6. **Test after changes**: Run `./scripts/platform-status.sh` to verify
7. **Document incidents**: Update `TODO_INCIDENTS.md` with findings

---

**Remember**: 🚫 No `kubectl apply` → ✅ Always Git + `argocd app sync`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
