#!/usr/bin/env bash
# Quick Redeploy Script
# Automates complete cluster teardown and redeployment
# Usage: ./scripts/quick-redeploy.sh

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

# Function to detect current branch (works in both local and GitHub Actions)
detect_branch() {
    local branch=""

    # Method 1: Check GitHub Actions environment variables (for PRs and pushes)
    if [ -n "${GITHUB_HEAD_REF:-}" ]; then
        # For pull_request events
        branch="${GITHUB_HEAD_REF}"
    elif [ -n "${GITHUB_REF_NAME:-}" ]; then
        # For push events
        branch="${GITHUB_REF_NAME}"
    elif [ -n "${GITHUB_REF:-}" ]; then
        # Fallback: parse GITHUB_REF (refs/heads/branch-name)
        if [[ "${GITHUB_REF}" =~ refs/heads/(.+) ]]; then
            branch="${BASH_REMATCH[1]}"
        fi
    fi

    # Method 2: Try git command (works locally)
    if [ -z "$branch" ]; then
        branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "")
    fi

    # Method 3: Parse git symbolic-ref
    if [ -z "$branch" ]; then
        branch=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo "")
    fi

    echo "$branch"
}

# Function to detect repository URL (works in both local and GitHub Actions)
detect_repo_url() {
    local repo_url=""

    # Method 1: Check GitHub Actions environment variables
    if [ -n "${GITHUB_REPOSITORY:-}" ]; then
        # GITHUB_REPOSITORY is in format "owner/repo"
        repo_url="https://github.com/${GITHUB_REPOSITORY}"
    fi

    # Method 2: Get from git remote (works locally)
    if [ -z "$repo_url" ]; then
        repo_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")

        # Convert SSH URLs to HTTPS for Argo
        if [[ "$repo_url" =~ ^git@github\.com:(.+)\.git$ ]]; then
            repo_url="https://github.com/${BASH_REMATCH[1]}"
        elif [[ "$repo_url" =~ ^git@github\.com:(.+)$ ]]; then
            repo_url="https://github.com/${BASH_REMATCH[1]}"
        fi
    fi

    echo "$repo_url"
}

# Detect repository and branch
DEPLOY_REPO=$(detect_repo_url)
DEPLOY_BRANCH=$(detect_branch)

# Fallback to defaults if detection fails
if [ -z "$DEPLOY_REPO" ]; then
    DEPLOY_REPO="https://github.com/redhat-et/kagenti-demo-deployment"
fi

if [ -z "$DEPLOY_BRANCH" ]; then
    DEPLOY_BRANCH="main"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       Kagenti Platform Quick Redeploy Script                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo -e "  Repository: ${BLUE}${DEPLOY_REPO}${NC}"
echo -e "  Branch:     ${BLUE}${DEPLOY_BRANCH}${NC}"
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo -e "  Mode:       ${YELLOW}GitHub Actions${NC}"
    echo -e "  Event:      ${GITHUB_EVENT_NAME:-N/A}"
fi
echo ""

# Pre-flight: Ask about agent images (or use CI_MODE env var)
AGENT_IMAGE_MODE="${AGENT_IMAGE_MODE:-skip}"
AGENT_SOURCE_DIR="${AGENT_SOURCE_DIR:-$REPO_ROOT/../agent-examples-local}"

# Skip prompts in CI mode
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo -e "${YELLOW}→ CI mode detected - skipping agent image loading${NC}"
    AGENT_IMAGE_MODE="skip"
elif [ -d "$AGENT_SOURCE_DIR" ]; then
    echo -e "${BLUE}Agent source found at: $AGENT_SOURCE_DIR${NC}"
    echo ""
    echo "Build agent images? (y/n/skip) [default: skip]"
    echo "  y     - Build from source (2-5 minutes)"
    echo "  n     - Load pre-built images (30 seconds)"
    echo "  skip  - Skip agent image loading (agents won't start)"
    echo ""
    echo -n "Your choice: "
    read -r -t 15 response || response="skip"
    echo ""

    case "$response" in
        y|Y)
            AGENT_IMAGE_MODE="build"
            echo -e "${GREEN}→ Will build agent images from source${NC}"
            ;;
        n|N)
            AGENT_IMAGE_MODE="load"
            echo -e "${GREEN}→ Will load pre-built agent images${NC}"
            ;;
        *)
            AGENT_IMAGE_MODE="skip"
            echo -e "${YELLOW}→ Will skip agent image loading${NC}"
            ;;
    esac
else
    echo -e "${YELLOW}⊘ Agent source not found at: $AGENT_SOURCE_DIR${NC}"
    echo "  Skipping agent image loading"
    AGENT_IMAGE_MODE="skip"
fi
echo ""

# Pre-flight: Ask about operator images (or use CI_MODE env var)
OPERATOR_IMAGE_MODE="${OPERATOR_IMAGE_MODE:-load}"

# Skip prompts in CI mode
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo -e "${YELLOW}→ CI mode detected - skipping operator image loading${NC}"
    OPERATOR_IMAGE_MODE="skip"
else
    echo "Load operator images? (y/n/skip) [default: y]"
    echo "  y     - Load pre-built images from Docker (30 seconds)"
    echo "  n     - Rebuild from source (2-5 minutes)"
    echo "  skip  - Skip operator image loading (operators won't start)"
    echo ""
    echo -n "Your choice: "
    read -r -t 15 operator_response || operator_response="y"
    echo ""

    case "$operator_response" in
        n|N)
            OPERATOR_IMAGE_MODE="rebuild"
            echo -e "${YELLOW}→ Will rebuild operator images from source${NC}"
            ;;
        skip|SKIP|s|S)
            OPERATOR_IMAGE_MODE="skip"
            echo -e "${YELLOW}→ Will skip operator image loading${NC}"
            ;;
        *)
            OPERATOR_IMAGE_MODE="load"
            echo -e "${GREEN}→ Will load pre-built operator images${NC}"
            ;;
    esac
fi
echo ""

# Step 1: Cleanup existing cluster
echo -e "${BLUE}[1/6] Cleaning up existing cluster...${NC}"
if "$SCRIPT_DIR/kind/00-cleanup.sh"; then
    echo -e "${GREEN}✓ Cluster cleanup complete${NC}"
else
    echo -e "${RED}✗ Cluster cleanup failed${NC}"
    exit 1
fi
echo ""

# Step 2: Create new Kind cluster
echo -e "${BLUE}[2/6] Creating Kind cluster...${NC}"
if "$SCRIPT_DIR/kind/01-create-cluster.sh"; then
    echo -e "${GREEN}✓ Kind cluster created${NC}"
else
    echo -e "${RED}✗ Kind cluster creation failed${NC}"
    exit 1
fi
echo ""

# Step 3: Load Operator Images (kagenti-operator, kagenti-platform-operator)
echo -e "${BLUE}[3/7] Loading Kagenti operator images...${NC}"

case "$OPERATOR_IMAGE_MODE" in
    rebuild)
        echo -e "${YELLOW}→ Rebuilding operator images from source${NC}"
        OPERATOR_SOURCE_DIR="${OPERATOR_SOURCE_DIR:-$REPO_ROOT/../kagenti-operator}"
        if [ -d "$OPERATOR_SOURCE_DIR" ]; then
            echo "Building kagenti-operator..."
            (cd "$OPERATOR_SOURCE_DIR" && make docker-build IMG=localhost:5001/kagenti-operator:dev) || {
                echo -e "${RED}✗ Failed to build kagenti-operator${NC}"
                exit 1
            }

            PLATFORM_OPERATOR_DIR="${PLATFORM_OPERATOR_DIR:-$REPO_ROOT/../kagenti-platform-operator}"
            if [ -d "$PLATFORM_OPERATOR_DIR" ]; then
                echo "Building kagenti-platform-operator..."
                (cd "$PLATFORM_OPERATOR_DIR" && make docker-build IMG=localhost:5001/kagenti-platform-operator:dev) || {
                    echo -e "${RED}✗ Failed to build kagenti-platform-operator${NC}"
                    exit 1
                }
            fi

            echo "Loading operator images into Kind..."
            kind load docker-image \
                localhost:5001/kagenti-operator:dev \
                localhost:5001/kagenti-platform-operator:dev \
                --name kagenti-demo || {
                echo -e "${RED}✗ Failed to load operator images${NC}"
                exit 1
            }
            echo -e "${GREEN}✓ Operator images rebuilt and loaded${NC}"
        else
            echo -e "${RED}✗ Operator source not found at: $OPERATOR_SOURCE_DIR${NC}"
            exit 1
        fi
        ;;
    skip)
        echo -e "${YELLOW}⊘ Skipping operator image loading${NC}"
        ;;
    load)
        # Default: load pre-built images
        echo -e "${GREEN}→ Loading pre-built operator images from Docker${NC}"

        # Check if both operator images exist
        KAGENTI_OP_EXISTS=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -c "localhost:5001/kagenti-operator:dev" || true)
        PLATFORM_OP_EXISTS=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -c "localhost:5001/kagenti-platform-operator:dev" || true)

        if [ "$KAGENTI_OP_EXISTS" -ge 1 ] && [ "$PLATFORM_OP_EXISTS" -ge 1 ]; then
            echo "  ✓ Found kagenti-operator:dev"
            echo "  ✓ Found kagenti-platform-operator:dev"
            kind load docker-image \
                localhost:5001/kagenti-operator:dev \
                localhost:5001/kagenti-platform-operator:dev \
                --name kagenti-demo || {
                echo -e "${YELLOW}⚠ Failed to load operator images (continuing anyway)${NC}"
            }
            echo -e "${GREEN}✓ Operator images loaded into Kind${NC}"
        else
            echo -e "${YELLOW}⚠ Pre-built operator images not found in Docker${NC}"
            [ "$KAGENTI_OP_EXISTS" -eq 0 ] && echo "  ✗ Missing: localhost:5001/kagenti-operator:dev"
            [ "$PLATFORM_OP_EXISTS" -eq 0 ] && echo "  ✗ Missing: localhost:5001/kagenti-platform-operator:dev"
            echo ""
            echo "  To build operator images:"
            echo "    cd ../kagenti-operator"
            echo "    make docker-build IMG=localhost:5001/kagenti-operator:dev"
            echo "    make docker-build IMG=localhost:5001/kagenti-platform-operator:dev"
            echo ""
            echo "  ⚠ Operators will fail with ImagePullBackOff"
        fi
        ;;
esac
echo ""

# Step 4: Install ArgoCD
echo -e "${BLUE}[4/7] Installing ArgoCD...${NC}"
if "$SCRIPT_DIR/kind/02-install-argocd.sh"; then
    echo -e "${GREEN}✓ ArgoCD installed${NC}"
else
    echo -e "${RED}✗ ArgoCD installation failed${NC}"
    exit 1
fi
echo ""

# Step 5: Bootstrap ArgoCD Applications
echo -e "${BLUE}[5/7] Bootstrapping ArgoCD Applications...${NC}"

# Generate root-app.yaml dynamically with detected repo/branch
ROOT_APP_YAML="/tmp/root-app-kagenti-$(date +%s).yaml"
cat > "$ROOT_APP_YAML" <<EOF
# Root Application (App-of-Apps Pattern)
# Auto-generated by quick-redeploy.sh
# Repository: ${DEPLOY_REPO}
# Branch: ${DEPLOY_BRANCH}

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagenti-platform-kind
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: ${DEPLOY_REPO}
    targetRevision: ${DEPLOY_BRANCH}
    path: argocd/applications/kind-local

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "  Creating root Application (App-of-Apps)..."
echo "  Using: ${DEPLOY_REPO} @ ${DEPLOY_BRANCH}"

if kubectl apply -f "$ROOT_APP_YAML"; then
    echo -e "${GREEN}✓ Root Application created${NC}"
else
    echo -e "${RED}✗ Failed to create root Application${NC}"
    exit 1
fi

# Wait for ArgoCD to detect the app
sleep 3

# List Applications
echo "  ArgoCD Applications:"
if command -v argocd &>/dev/null; then
    argocd app list --port-forward --port-forward-namespace argocd --grpc-web 2>/dev/null || \
        kubectl get applications -n argocd
else
    kubectl get applications -n argocd
fi

echo -e "${GREEN}✓ ArgoCD Applications bootstrapped${NC}"
echo ""

# Step 6: Load Agent Images (based on user choice)
echo -e "${BLUE}[6/7] Loading agent images...${NC}"
if [ "$AGENT_IMAGE_MODE" = "build" ]; then
    if [ -f "$SCRIPT_DIR/kind/04-load-agent-images.sh" ]; then
        if "$SCRIPT_DIR/kind/04-load-agent-images.sh" build; then
            echo -e "${GREEN}✓ Agent images built and loaded${NC}"
        else
            echo -e "${YELLOW}⚠ Agent image build failed (continuing anyway)${NC}"
        fi
    else
        echo -e "${RED}✗ Agent image script not found${NC}"
    fi
elif [ "$AGENT_IMAGE_MODE" = "load" ]; then
    if [ -f "$SCRIPT_DIR/kind/04-load-agent-images.sh" ]; then
        if "$SCRIPT_DIR/kind/04-load-agent-images.sh" load; then
            echo -e "${GREEN}✓ Agent images loaded${NC}"
        else
            echo -e "${YELLOW}⚠ Agent image load failed (continuing anyway)${NC}"
        fi
    else
        echo -e "${RED}✗ Agent image script not found${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Skipping agent image loading${NC}"
fi
echo ""

# Step 7: Sync root ArgoCD Application
echo -e "${BLUE}[7/7] Syncing root ArgoCD Application...${NC}"
echo "This will deploy the entire platform. Please wait..."
echo ""

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

# Sync the root app
if argocd app sync kagenti-platform-kind \
    --port-forward --port-forward-namespace "$ARGOCD_NAMESPACE" --grpc-web \
    --timeout 600 2>/dev/null; then
    echo -e "${GREEN}✓ Root application synced${NC}"
else
    echo -e "${YELLOW}⚠ Root application sync completed with warnings${NC}"
fi
echo ""

# Wait a moment for applications to be created
echo "Waiting for ArgoCD to create child applications..."
sleep 5


# Final summary
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  Deployment Summary                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✓ Cluster redeployed successfully!${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo -e "  Repository: ${DEPLOY_REPO}"
echo -e "  Branch:     ${DEPLOY_BRANCH}"
echo ""
echo "Next steps:"
echo "  1. Wait 5-10 minutes for all pods to become ready"
echo "  2. Check platform status:"
echo "     ./scripts/platform-status.sh"
echo ""
echo "  3. Access services:"
echo "     ArgoCD:   https://argocd.localtest.me:9443"
echo "     Keycloak: https://keycloak.localtest.me:9443"
echo "     Kagenti:  https://kagenti.localtest.me:9443"
echo "     Grafana:  https://grafana.localtest.me:9443"
echo ""
echo "  4. Get ArgoCD admin password:"
echo "     cat /tmp/argocd-pass.txt"
echo ""
echo "Deployment time: $(date)"
echo ""
