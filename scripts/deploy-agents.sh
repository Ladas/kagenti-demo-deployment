#!/usr/bin/env bash
# Deploy/Redeploy Kagenti Agents
# This script handles agent deployment and redeployment via ArgoCD
#
# Usage:
#   ./scripts/deploy-agents.sh              # Deploy all agents
#   ./scripts/deploy-agents.sh --sync-only  # Skip image loading, just sync
#   ./scripts/deploy-agents.sh --build      # Rebuild images before deploying

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
SYNC_ONLY=false
BUILD_IMAGES=false
AGENT_SOURCE_DIR="${AGENT_SOURCE_DIR:-$REPO_ROOT/../agent-examples-local}"
AGENT_EXAMPLES_DIR="${AGENT_EXAMPLES_DIR:-$REPO_ROOT/../agent-examples}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --sync-only)
            SYNC_ONLY=true
            shift
            ;;
        --build)
            BUILD_IMAGES=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--sync-only] [--build]"
            exit 1
            ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Kagenti Agent Deployment Script                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Load/Build Agent Images (unless --sync-only)
if [ "$SYNC_ONLY" = false ]; then
    if [ "$BUILD_IMAGES" = true ]; then
        echo -e "${BLUE}[1/3] Building agent images from source...${NC}"
        "$SCRIPT_DIR/kind/04-load-agent-images.sh" build
    else
        echo -e "${BLUE}[1/3] Loading pre-built agent images...${NC}"
        "$SCRIPT_DIR/kind/04-load-agent-images.sh" load || {
            echo -e "${YELLOW}⚠️  Pre-built images not found, attempting to build from source...${NC}"
            "$SCRIPT_DIR/kind/04-load-agent-images.sh" build
        }
    fi
    echo ""
else
    echo -e "${YELLOW}[1/3] Skipping agent image loading (--sync-only mode)${NC}"
    echo ""
fi

# Step 2: Sync agents application via ArgoCD
echo -e "${BLUE}[2/3] Syncing agents via ArgoCD...${NC}"
echo ""

# Check if ArgoCD is accessible
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo -e "${RED}✗ ArgoCD not found. Is the cluster running?${NC}"
    exit 1
fi

# Sync agents application
argocd app sync agents \
    --port-forward \
    --port-forward-namespace argocd \
    --grpc-web \
    --timeout 300 || {
    echo -e "${YELLOW}⚠️  ArgoCD sync had issues (may be normal if app doesn't exist yet)${NC}"
}

echo ""
echo -e "${GREEN}✓ Agent sync initiated${NC}"
echo ""

# Step 3: Wait for agent pods to be ready
echo -e "${BLUE}[3/3] Waiting for agent pods to be ready...${NC}"
echo ""

# List of expected agents
EXPECTED_AGENTS=(
    "research-agent"
    "code-agent"
    "orchestrator-agent"
    "weather-service"
    "weather-mcp-tool"
)

# Wait for each agent pod
MAX_WAIT=180  # 3 minutes
ELAPSED=0
ALL_READY=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    ALL_READY=true

    for agent in "${EXPECTED_AGENTS[@]}"; do
        # Check if deployment exists
        if ! kubectl get deployment "$agent" -n team1 &>/dev/null; then
            echo -e "${YELLOW}  ⏳ Waiting for $agent deployment to be created...${NC}"
            ALL_READY=false
            continue
        fi

        # Check if deployment is ready
        READY=$(kubectl get deployment "$agent" -n team1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment "$agent" -n team1 -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

        if [ "$READY" != "$DESIRED" ]; then
            echo -e "${YELLOW}  ⏳ $agent: $READY/$DESIRED ready${NC}"
            ALL_READY=false
        else
            echo -e "${GREEN}  ✓ $agent: $READY/$DESIRED ready${NC}"
        fi
    done

    if [ "$ALL_READY" = true ]; then
        break
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""

if [ "$ALL_READY" = true ]; then
    echo -e "${GREEN}✅ All agent pods are ready!${NC}"
else
    echo -e "${YELLOW}⚠️  Some agents are not ready yet (waited ${ELAPSED}s)${NC}"
    echo ""
    echo "Check pod status with:"
    echo "  kubectl get pods -n team1"
    echo ""
    echo "Check logs for any agent:"
    echo "  kubectl logs -n team1 deployment/research-agent --tail=50"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Agent Deployment Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show deployment status
kubectl get deployments -n team1 -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyReplicas,\
DESIRED:.spec.replicas,\
IMAGE:.spec.template.spec.containers[0].image

echo ""
echo "Agent Access URLs:"
echo "  Research Agent:    http://research-agent.team1.svc.cluster.local:8080"
echo "  Code Agent:        http://code-agent.team1.svc.cluster.local:8080"
echo "  Orchestrator:      http://orchestrator-agent.team1.svc.cluster.local:8080"
echo "  Weather Service:   http://weather-service.team1.svc.cluster.local:8000"
echo "  Weather MCP Tool:  http://weather-mcp-tool.team1.svc.cluster.local:8001"
echo ""

# Test agent connectivity
echo "Test agent connectivity:"
echo "  kubectl run test-curl -n team1 --image=curlimages/curl:latest --restart=Never --rm -it \\"
echo "    -- curl http://research-agent:8080/.well-known/agent-card.json"
echo ""

# Phoenix traces
echo "View agent traces in Phoenix:"
echo "  https://phoenix.localtest.me:9443/projects/team1-agents"
echo ""
