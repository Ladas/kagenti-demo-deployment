#!/usr/bin/env bash
# Load operator images into Kind cluster
#
# This script loads operator image tar files into the Kind cluster.
# Used in CI environments where operator images are pre-built and exported.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGES_DIR="$REPO_ROOT/.images"
CLUSTER_NAME="${KIND_CLUSTER_NAME:-kagenti-demo}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Load Operator Images into Kind${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Check if images directory exists
if [ ! -d "$IMAGES_DIR" ]; then
    echo -e "${RED}✗ Images directory not found: $IMAGES_DIR${NC}"
    echo "  Please run ./scripts/export-operator-images.sh first to export images."
    exit 1
fi

# List of operator image tar files
TAR_FILES=(
    "$IMAGES_DIR/kagenti-operator-dev.tar"
    "$IMAGES_DIR/kagenti-platform-operator-dev.tar"
)

echo -e "${BLUE}Loading operator images into Kind cluster: $CLUSTER_NAME${NC}"
echo ""

loaded_count=0
missing_count=0

for tar_file in "${TAR_FILES[@]}"; do
    image_name=$(basename "$tar_file" .tar)

    if [ ! -f "$tar_file" ]; then
        echo -e "${YELLOW}⊘ Skipping missing file: $tar_file${NC}"
        missing_count=$((missing_count + 1))
        continue
    fi

    echo -e "${YELLOW}→ Loading: $image_name${NC}"

    if kind load image-archive "$tar_file" --name "$CLUSTER_NAME" 2>&1 | grep -v "Image.*already present"; then
        size=$(du -h "$tar_file" | cut -f1)
        echo -e "${GREEN}✓ Loaded: $image_name ($size)${NC}"
        loaded_count=$((loaded_count + 1))
    else
        echo -e "${RED}✗ Failed to load: $tar_file${NC}"
    fi
    echo ""
done

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}Load complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Loaded $loaded_count operator image(s) into Kind cluster: $CLUSTER_NAME"
if [ $missing_count -gt 0 ]; then
    echo -e "${YELLOW}Skipped $missing_count missing image(s)${NC}"
    echo ""
    echo "To export operator images from Docker:"
    echo "  ./scripts/export-operator-images.sh"
fi
echo ""

# Verify images are loaded
echo -e "${BLUE}Verifying images in Kind cluster...${NC}"
docker exec "$CLUSTER_NAME-control-plane" crictl images | grep -E "(kagenti.*operator|REPOSITORY)" || echo -e "${YELLOW}No operator images found in cluster${NC}"
