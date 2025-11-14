#!/usr/bin/env bash
# Create Kind Cluster with ArgoCD-ready Configuration
# Part of ArgoCD GitOps migration
# Usage: ./scripts/kind/01-create-cluster.sh

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kagenti-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Creating Kind cluster: ${CLUSTER_NAME}"
echo ""

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️  Cluster '${CLUSTER_NAME}' already exists!"
    echo "   Run ./scripts/kind/00-cleanup.sh first to delete it"
    exit 1
fi

# Create cluster with port mappings for Istio Gateway
echo "📦 Creating Kind cluster with Istio port mappings..."
cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  # HTTP - Maps host:8080 to NodePort 30080 (gateway HTTP)
  - containerPort: 30080
    hostPort: 8080
    protocol: TCP
  # HTTPS - Maps host:9443 to NodePort 30443 (gateway HTTPS)
  - containerPort: 30443
    hostPort: 9443
    protocol: TCP
EOF

echo "✅ Kind cluster created"
echo ""

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s
echo "✅ Cluster is ready"
echo ""

# Install MetalLB for LoadBalancer support
echo "🔧 Installing MetalLB for LoadBalancer support..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s 2>/dev/null || echo "⚠️  MetalLB pods not ready yet (will continue)"

# Configure MetalLB IP pool
echo "⚙️  Configuring MetalLB IP address pool..."
docker network inspect kind | grep -o '"Subnet": "[^"]*' | cut -d'"' -f4 | grep -v ':' | head -1 | while read SUBNET; do
  # Extract first 3 octets and create pool range (IPv4 only)
  POOL_PREFIX=$(echo ${SUBNET} | cut -d'.' -f1-3)
  cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
  - ${POOL_PREFIX}.200-${POOL_PREFIX}.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - kind-pool
EOF
done

echo "✅ MetalLB installed and configured"
echo ""

echo "✨ Cluster creation complete!"
echo ""
echo "📊 Cluster info:"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo ""
echo "Next steps:"
echo "  1. Install ArgoCD: ./scripts/kind/02-install-argocd.sh"
echo "  2. Bootstrap apps:  ./scripts/kind/03-bootstrap-apps.sh"
