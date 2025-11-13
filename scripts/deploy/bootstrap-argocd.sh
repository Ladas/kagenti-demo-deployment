#!/bin/bash
# Bootstrap ArgoCD on any Kubernetes cluster
# Supports: Kind, K3s, OpenShift

set -e

ARGOCD_VERSION="stable"
ARGOCD_NAMESPACE="argocd"

echo "=== ArgoCD Bootstrap ==="
echo ""

# Detect cluster type
if kubectl get nodes -o json | grep -q "kind"; then
  CLUSTER_TYPE="kind"
elif kubectl get nodes -o json | grep -q "k3s"; then
  CLUSTER_TYPE="k3s"
elif kubectl version | grep -q "openshift"; then
  CLUSTER_TYPE="openshift"
else
  CLUSTER_TYPE="generic"
fi

echo "Detected cluster type: $CLUSTER_TYPE"
echo ""

# Create namespace
echo "Creating namespace $ARGOCD_NAMESPACE..."
kubectl create namespace $ARGOCD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "Installing ArgoCD $ARGOCD_VERSION..."
kubectl apply -n $ARGOCD_NAMESPACE \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml

# Wait for ArgoCD to be ready
echo ""
echo "Waiting for ArgoCD components to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server \
  deployment/argocd-repo-server \
  deployment/argocd-dex-server \
  -n $ARGOCD_NAMESPACE

# OpenShift-specific configuration
if [ "$CLUSTER_TYPE" = "openshift" ]; then
  echo ""
  echo "Applying OpenShift-specific configuration..."

  # Create Route for ArgoCD server
  cat <<EOF | kubectl apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: argocd-server
  namespace: $ARGOCD_NAMESPACE
spec:
  to:
    kind: Service
    name: argocd-server
  port:
    targetPort: https
  tls:
    termination: passthrough
    insecureEdgeTerminationPolicy: Redirect
EOF

  ARGOCD_URL="https://$(kubectl get route argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.host}')"
else
  ARGOCD_URL="https://localhost:8080"
fi

# Get initial admin password
echo ""
echo "=== ArgoCD Installation Complete ==="
echo ""
echo "ArgoCD Server: $ARGOCD_URL"
echo ""

if kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NAMESPACE &>/dev/null; then
  ADMIN_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
  echo "Admin Username: admin"
  echo "Admin Password: $ADMIN_PASSWORD"
else
  echo "⚠️  Initial admin secret not found. Password may have been reset."
  echo "Reset password: argocd account update-password"
fi

echo ""

# Instructions for accessing
if [ "$CLUSTER_TYPE" = "openshift" ]; then
  echo "Access ArgoCD UI:"
  echo "  $ARGOCD_URL"
else
  echo "Access ArgoCD UI (via port-forward):"
  echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
  echo "  Then open: https://localhost:8080"
fi

echo ""
echo "Install ArgoCD CLI:"
echo "  brew install argocd"
echo ""
echo "Login via CLI:"
if [ "$CLUSTER_TYPE" = "openshift" ]; then
  echo "  argocd login $(kubectl get route argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.host}')"
else
  echo "  argocd login localhost:8080"
fi
echo ""
