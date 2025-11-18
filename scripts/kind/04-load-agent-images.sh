#!/usr/bin/env bash
# Build and Load Agent Images for Kind Cluster (LEGACY - For Local Development Only)
#
# ⚠️  DEPRECATION NOTICE ⚠️
# This script is LEGACY and should only be used for quick local development/testing.
# For production-like builds, use the operator-based workflow:
#   - Setup: scripts/dev/setup-agent-source-repo.sh
#   - Trigger: scripts/dev/trigger-agent-builds.sh
#   - Docs: components/03-applications/agents/agent-builds/README.md
#
# This script handles agent images for local Kind development:
# 1. BUILD mode (default): Build images from source using Docker + load into Kind
# 2. LOAD mode: Load pre-built images from Docker into Kind (skip build)
#
# Use this ONLY for:
# - Quick local testing without GitHub setup
# - Rapid iteration on agent code changes
# - Development when Tekton/operator not needed
#
# For production builds using kagenti-operator + Tekton, see:
# - components/03-applications/agents/agent-builds/README.md
# - CLAUDE.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-kagenti-demo}"
MODE="${1:-build}" # build or load
VERSION="${VERSION:-v0.0.15}"
AGENT_SOURCE_DIR="${AGENT_SOURCE_DIR:-/Users/ladas/Projects/OCTO/research/agent-examples-local}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      Build & Load Agent Images for Kind Cluster             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Mode:    $MODE"
echo "Version: $VERSION"
echo "Cluster: $CLUSTER_NAME"
echo ""

# Check if Kind cluster exists
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "❌ ERROR: Kind cluster '${CLUSTER_NAME}' not found"
    echo "Run ./scripts/kind/01-create-cluster.sh first"
    exit 1
fi

echo "✓ Kind cluster '${CLUSTER_NAME}' found"
echo ""

# Agent images to build/load
IMAGES=(
    "localhost:5000/research-agent:${VERSION}"
    "localhost:5000/code-agent:${VERSION}"
    "localhost:5000/orchestrator-agent:${VERSION}"
    "localhost:5000/weather-service:v0.0.1"
    "localhost:5000/weather-mcp-tool:v0.0.1"
)

AGENTS=(
    "research-agent"
    "code-agent"
    "orchestrator-agent"
)

# Additional services (different source paths)
ADDITIONAL_SERVICES=(
    "weather-service:a2a/weather_service"
    "weather-mcp-tool:mcp/weather_tool"
)

if [ "$MODE" = "build" ]; then
    echo "Mode: BUILD images from source + load into Kind"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check if agent source directory exists
    if [ ! -d "$AGENT_SOURCE_DIR" ]; then
        echo "❌ ERROR: Agent source directory not found: $AGENT_SOURCE_DIR"
        echo ""
        echo "Set AGENT_SOURCE_DIR environment variable to the agent source location:"
        echo "  export AGENT_SOURCE_DIR=/path/to/agent-examples-local"
        echo "  $0 build"
        echo ""
        echo "Or use LOAD mode if you have pre-built images:"
        echo "  $0 load"
        exit 1
    fi

    echo "✓ Agent source directory found: $AGENT_SOURCE_DIR"
    echo ""

    # Build Docker images
    echo "Building agent images with Docker..."
    for agent in "${AGENTS[@]}"; do
        agent_dir="$AGENT_SOURCE_DIR/a2a/$agent"

        if [ ! -d "$agent_dir" ]; then
            echo "⚠️  WARNING: Directory $agent_dir not found, skipping $agent"
            continue
        fi

        echo "  Building $agent..."
        docker build -t "localhost:5000/$agent:$VERSION" "$agent_dir"
        if [ $? -eq 0 ]; then
            echo "  ✓ Built $agent successfully"
        else
            echo "  ✗ Failed to build $agent"
            exit 1
        fi
    done

    echo ""
    echo "✅ All agent images built successfully!"
    echo ""

    # Build additional services (weather-service, weather-mcp-tool)
    echo "Building additional services..."
    AGENT_EXAMPLES_DIR="${AGENT_EXAMPLES_DIR:-/Users/ladas/Projects/OCTO/research/agent-examples}"

    if [ -d "$AGENT_EXAMPLES_DIR" ]; then
        for service_path in "${ADDITIONAL_SERVICES[@]}"; do
            IFS=':' read -r service_name service_dir <<< "$service_path"
            full_path="$AGENT_EXAMPLES_DIR/$service_dir"

            if [ ! -d "$full_path" ]; then
                echo "⚠️  WARNING: Directory $full_path not found, skipping $service_name"
                continue
            fi

            echo "  Building $service_name from $service_dir..."
            # Determine version based on service name
            if [[ "$service_name" == weather-* ]]; then
                service_version="v0.0.1"
            else
                service_version="${VERSION}"
            fi

            docker build -t "localhost:5000/$service_name:$service_version" "$full_path"
            if [ $? -eq 0 ]; then
                echo "  ✓ Built $service_name successfully"
            else
                echo "  ⚠️  Failed to build $service_name (non-fatal, continuing...)"
            fi
        done
    else
        echo "⚠️  WARNING: Agent examples directory not found: $AGENT_EXAMPLES_DIR"
        echo "  Skipping weather service builds. Set AGENT_EXAMPLES_DIR to build them."
    fi

    echo ""

    # Load images into Kind
    echo "Loading agent images into Kind cluster..."
    for img in "${IMAGES[@]}"; do
        echo "  Loading: $img"
        kind load docker-image "$img" --name "$CLUSTER_NAME"
    done

    echo ""
    echo "✅ All agent images loaded successfully!"

elif [ "$MODE" = "load" ]; then
    echo "Mode: LOAD pre-built images into Kind"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check if images exist locally
    echo "Checking for agent images in Docker..."
    MISSING_IMAGES=()
    for img in "${IMAGES[@]}"; do
        if ! docker image inspect "$img" &>/dev/null; then
            MISSING_IMAGES+=("$img")
        fi
    done

    if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
        echo "❌ ERROR: Missing agent images in Docker:"
        for img in "${MISSING_IMAGES[@]}"; do
            echo "  - $img"
        done
        echo ""
        echo "Options:"
        echo "  1. Build images from source:"
        echo "     $0 build"
        echo ""
        echo "  2. Build manually from agent-examples-local:"
        echo "     cd $AGENT_SOURCE_DIR"
        echo "     VERSION=$VERSION ./build-and-deploy.sh"
        exit 1
    fi

    echo "✓ All agent images found in Docker"
    echo ""

    # Load images into Kind
    echo "Loading agent images into Kind cluster..."
    for img in "${IMAGES[@]}"; do
        echo "  Loading: $img"
        kind load docker-image "$img" --name "$CLUSTER_NAME"
    done

    echo ""
    echo "✅ All agent images loaded successfully!"

else
    echo "❌ ERROR: Invalid mode '$MODE'"
    echo ""
    echo "Usage: $0 [build|load]"
    echo ""
    echo "Modes:"
    echo "  build  - Build images from source using Docker + load into Kind (default)"
    echo "  load   - Load pre-built images from Docker into Kind (skip build)"
    echo ""
    echo "Environment Variables:"
    echo "  VERSION           - Image tag (default: v0.0.15)"
    echo "  AGENT_SOURCE_DIR  - Path to agent source code (default: /Users/ladas/Projects/OCTO/research/agent-examples-local)"
    echo "  CLUSTER_NAME      - Kind cluster name (default: kagenti-demo)"
    echo ""
    echo "Examples:"
    echo "  $0 build                    # Build from source + load"
    echo "  $0 load                     # Load existing images"
    echo "  VERSION=v0.0.16 $0 build    # Build with custom version"
    exit 1
fi

echo ""
echo "Next steps:"
echo "  1. Sync agents via ArgoCD:"
echo "     argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web"
echo ""
echo "  2. Verify pods are running:"
echo "     kubectl get pods -n team1"
echo ""
echo "  3. Test agent connectivity:"
echo "     curl http://research-agent.team1.svc.cluster.local:8080/.well-known/agent-card.json"
echo ""
