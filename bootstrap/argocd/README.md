# ArgoCD Bootstrap

This directory contains resources for bootstrapping ArgoCD on any Kubernetes cluster.

## Quick Install

Use the provided script:

```bash
./scripts/deploy/bootstrap-argocd.sh
```

## Manual Install

```bash
# Create namespace
kubectl apply -f bootstrap/argocd/namespace.yaml

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## Access ArgoCD

**Port Forward:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
open https://localhost:8080
```

**OpenShift Route:**
ArgoCD Route is automatically created by the bootstrap script on OpenShift.

## Deploy Applications

After ArgoCD is installed, deploy applications:

```bash
# Deploy to Kind
kubectl apply -f argocd-apps/kind-local.yaml

# Deploy to OpenShift Stage
kubectl apply -f argocd-apps/openshift-stage.yaml
```
