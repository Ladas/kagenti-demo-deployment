#!/usr/bin/env bash
# Build and push Kagenti operators to local Kind registry
# Usage: ./scripts/dev/build-operators.sh [platform|kagenti|both]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
OPERATOR_REPO_PATH="${OPERATOR_REPO_PATH:-/Users/ladas/Projects/OCTO/research/ladas-kagenti-operator}"
LOCAL_REGISTRY="${LOCAL_REGISTRY:-localhost:5001}"
IMAGE_TAG="${IMAGE_TAG:-dev}"

# Which operators to build
BUILD_PLATFORM=false
BUILD_KAGENTI=false

if [ "$1" == "platform" ]; then
  BUILD_PLATFORM=true
elif [ "$1" == "kagenti" ]; then
  BUILD_KAGENTI=true
elif [ "$1" == "both" ] || [ -z "$1" ]; then
  BUILD_PLATFORM=true
  BUILD_KAGENTI=true
else
  echo -e "${RED}Error: Invalid argument. Use 'platform', 'kagenti', or 'both'${NC}"
  exit 1
fi

echo -e "${GREEN}=== Kagenti Operators Local Build ===${NC}"
echo ""
echo "Operator repo: $OPERATOR_REPO_PATH"
echo "Local registry: $LOCAL_REGISTRY"
echo "Image tag: $IMAGE_TAG"
echo ""

# Verify operator repo exists
if [ ! -d "$OPERATOR_REPO_PATH" ]; then
  echo -e "${RED}Error: Operator repository not found at $OPERATOR_REPO_PATH${NC}"
  echo "Clone it with: git clone https://github.com/Ladas/kagenti-operator $OPERATOR_REPO_PATH"
  exit 1
fi

# Verify Kind cluster is running
echo -e "${YELLOW}Checking Kind cluster...${NC}"
if ! kind get clusters | grep -q "kagenti-demo"; then
  echo -e "${RED}Error: Kind cluster 'kagenti-demo' is not running${NC}"
  echo "Create the cluster with: ./scripts/kind/01-create-cluster.sh"
  exit 1
fi
echo -e "${GREEN}✓ Kind cluster is running${NC}"
echo ""

cd "$OPERATOR_REPO_PATH"

# Function to build and push operator image
build_operator() {
  local operator_name=$1
  local operator_dir=$2
  local image_name="${LOCAL_REGISTRY}/kagenti-${operator_name}:${IMAGE_TAG}"

  echo -e "${YELLOW}Building ${operator_name} operator...${NC}"

  cd "$OPERATOR_REPO_PATH/$operator_dir"

  # Build image using make
  if [ -f "Makefile" ]; then
    echo "Using Makefile to build image..."
    make docker-build IMG="$image_name" || {
      echo -e "${RED}Error: Failed to build ${operator_name} operator${NC}"
      return 1
    }
  else
    echo -e "${RED}Error: No Makefile found in $operator_dir${NC}"
    return 1
  fi

  echo -e "${YELLOW}Loading ${operator_name} operator into Kind cluster...${NC}"
  kind load docker-image "$image_name" --name kagenti-demo || {
    echo -e "${RED}Error: Failed to load ${operator_name} operator image into Kind${NC}"
    return 1
  }

  echo -e "${GREEN}✓ ${operator_name} operator built and loaded into Kind cluster${NC}"
  echo "  Image: $image_name"
  echo ""
}

# Build platform-operator
if [ "$BUILD_PLATFORM" == true ]; then
  build_operator "platform-operator" "platform-operator"
fi

# Build kagenti-operator
if [ "$BUILD_KAGENTI" == true ]; then
  build_operator "operator" "kagenti-operator"
fi

echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Verify images loaded into Kind cluster:"
echo "  docker exec kagenti-demo-control-plane crictl images | grep kagenti"
echo ""
echo "Next steps:"
echo "  1. Sync operators: argocd app sync kagenti-operator platform-operator --port-forward --port-forward-namespace argocd --grpc-web"
echo "  2. Verify pods: kubectl get pods -n kagenti-system"
echo "  3. Check operator logs: kubectl logs -n kagenti-system deployment/kagenti-operator-controller-manager -f"
