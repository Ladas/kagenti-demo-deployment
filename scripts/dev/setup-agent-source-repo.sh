#!/usr/bin/env bash
# Setup GitHub Repository for Agent Source Code
#
# This script helps set up a GitHub repository for agent source code and
# prepares it for use with kagenti-operator + Tekton CI/CD builds.
#
# Prerequisites:
# - GitHub CLI (gh) installed and authenticated
# - Agent source code in AGENT_SOURCE_DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SOURCE_DIR="${AGENT_SOURCE_DIR:-/Users/ladas/Projects/OCTO/research/agent-examples-local}"
GITHUB_USER="${GITHUB_USER:-Ladas}"
REPO_NAME="${REPO_NAME:-agent-examples}"
BRANCH="${BRANCH:-main}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      Setup GitHub Repository for Agent Source Code          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "GitHub User:   $GITHUB_USER"
echo "Repository:    $REPO_NAME"
echo "Branch:        $BRANCH"
echo "Source Dir:    $AGENT_SOURCE_DIR"
echo ""

# Check if agent source directory exists
if [ ! -d "$AGENT_SOURCE_DIR" ]; then
    echo "❌ ERROR: Agent source directory not found: $AGENT_SOURCE_DIR"
    exit 1
fi

echo "✓ Agent source directory found"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ ERROR: GitHub CLI (gh) not found"
    echo ""
    echo "Install GitHub CLI:"
    echo "  brew install gh"
    echo ""
    echo "Or create repository manually:"
    echo "  1. Go to https://github.com/new"
    echo "  2. Create repository: $GITHUB_USER/$REPO_NAME"
    echo "  3. Run this script again"
    exit 1
fi

echo "✓ GitHub CLI found"
echo ""

# Check if already logged in to GitHub
if ! gh auth status &> /dev/null; then
    echo "⚠️  Not authenticated with GitHub"
    echo ""
    echo "Please authenticate:"
    gh auth login
fi

echo "✓ GitHub authenticated"
echo ""

# Check if repository already exists
if gh repo view "$GITHUB_USER/$REPO_NAME" &> /dev/null; then
    echo "✓ Repository already exists: $GITHUB_USER/$REPO_NAME"
    REPO_EXISTS=true
else
    echo "📝 Repository does not exist"
    REPO_EXISTS=false
fi

# Offer to create repository
if [ "$REPO_EXISTS" = false ]; then
    echo ""
    read -p "Create GitHub repository $GITHUB_USER/$REPO_NAME? (y/n) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Creating repository..."
        gh repo create "$GITHUB_USER/$REPO_NAME" \
            --public \
            --description "Agent source code for Kagenti platform" \
            --clone=false

        echo "✓ Repository created"
    else
        echo "⚠️  Skipping repository creation"
        echo ""
        echo "Create repository manually:"
        echo "  gh repo create $GITHUB_USER/$REPO_NAME --public"
        exit 0
    fi
fi

echo ""
echo "Configuring Git repository..."

# Navigate to agent source directory
cd "$AGENT_SOURCE_DIR"

# Initialize git if not already initialized
if [ ! -d ".git" ]; then
    git init
    echo "✓ Git repository initialized"
else
    echo "✓ Git repository exists"
fi

# Add remote if not already added
if ! git remote get-url origin &> /dev/null; then
    git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
    echo "✓ Remote origin added"
else
    CURRENT_ORIGIN=$(git remote get-url origin)
    EXPECTED_ORIGIN="https://github.com/$GITHUB_USER/$REPO_NAME.git"

    if [ "$CURRENT_ORIGIN" != "$EXPECTED_ORIGIN" ]; then
        echo "⚠️  Remote origin mismatch:"
        echo "   Current:  $CURRENT_ORIGIN"
        echo "   Expected: $EXPECTED_ORIGIN"
        echo ""
        read -p "Update remote origin? (y/n) " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git remote set-url origin "$EXPECTED_ORIGIN"
            echo "✓ Remote origin updated"
        fi
    else
        echo "✓ Remote origin configured"
    fi
fi

# Check git status
echo ""
echo "Current git status:"
git status --short

# Commit and push
echo ""
read -p "Commit and push to GitHub? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Add all files
    git add .

    # Commit
    if git diff --cached --quiet; then
        echo "⚠️  No changes to commit"
    else
        git commit -m "Initial commit: A2A agent source code

- research-agent: Specialized in web research and information gathering
- code-agent: Specialized in code generation and analysis
- orchestrator-agent: Orchestrates multi-agent workflows

🤖 Prepared for kagenti-operator + Tekton CI/CD builds"

        echo "✓ Changes committed"
    fi

    # Push to GitHub
    echo "Pushing to GitHub..."
    git push -u origin "$BRANCH"

    echo ""
    echo "✅ Agent source code pushed to GitHub!"
    echo ""
    echo "Repository: https://github.com/$GITHUB_USER/$REPO_NAME"
else
    echo "⚠️  Skipping push"
fi

echo ""
echo "Next steps:"
echo "  1. Create GitHub token secret for Tekton:"
echo "     kubectl create secret generic github-token-secret \\"
echo "       --from-literal=username=$GITHUB_USER \\"
echo "       --from-literal=token=<YOUR_GITHUB_TOKEN> \\"
echo "       -n team1"
echo ""
echo "  2. Apply AgentBuild CRs:"
echo "     kubectl apply -f components/03-applications/agents/agent-builds/"
echo ""
echo "  3. Monitor builds:"
echo "     kubectl get agentbuild -n team1 -w"
echo ""
