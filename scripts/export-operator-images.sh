#!/usr/bin/env bash
# Export operator images for CI/CD usage
#
# This script exports operator images from Docker and saves them as tar files
# that can be loaded into Kind clusters in CI environments.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGES_DIR="$REPO_ROOT/.images"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Export Kagenti Operator Images${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Create images directory if it doesn't exist
mkdir -p "$IMAGES_DIR"

# List of operator images to export
IMAGES=(
    "localhost:5001/kagenti-operator:dev"
    "localhost:5001/kagenti-platform-operator:dev"
)

echo -e "${BLUE}Exporting operator images...${NC}"
echo ""

for image in "${IMAGES[@]}"; do
    # Extract image name for filename
    image_name=$(echo "$image" | sed 's|localhost:5001/||' | sed 's|:|-|' | sed 's|/|-|g')
    tar_file="$IMAGES_DIR/${image_name}.tar"

    echo -e "${YELLOW}→ Exporting: $image${NC}"

    # Check if image exists
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo -e "${RED}✗ Image not found: $image${NC}"
        echo "  Please build the image first or pull it from a registry."
        echo ""
        continue
    fi

    # Export image
    if docker save "$image" -o "$tar_file"; then
        size=$(du -h "$tar_file" | cut -f1)
        echo -e "${GREEN}✓ Exported to: $tar_file ($size)${NC}"
    else
        echo -e "${RED}✗ Failed to export: $image${NC}"
    fi
    echo ""
done

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}Export complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Exported images are saved in: $IMAGES_DIR"
echo ""
echo "To load these images into a Kind cluster:"
echo "  kind load image-archive $IMAGES_DIR/kagenti-operator-dev.tar --name kagenti-demo"
echo "  kind load image-archive $IMAGES_DIR/kagenti-platform-operator-dev.tar --name kagenti-demo"
echo ""
echo "Or use the load-operator-images.sh script:"
echo "  ./scripts/load-operator-images.sh"
