#!/usr/bin/env bash
# Trigger Operator-Based Agent Builds via Tekton
#
# This script applies AgentBuild CRs to trigger kagenti-operator + Tekton builds
# and monitors the build progress.
#
# Prerequisites:
# - kagenti-operator running
# - Tekton deployed
# - Agent source code pushed to GitHub
# - github-token-secret created

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="${NAMESPACE:-team1}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-true}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      Trigger Operator-Based Agent Builds via Tekton        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
echo ""

# 1. Check kagenti-operator
if ! kubectl get deployment kagenti-operator-controller-manager -n kagenti-system &> /dev/null; then
    echo "❌ ERROR: kagenti-operator not found"
    echo ""
    echo "Deploy kagenti-operator:"
    echo "  argocd app sync kagenti-operator --port-forward --port-forward-namespace argocd --grpc-web"
    exit 1
fi

echo "✓ kagenti-operator deployed"

# 2. Check Tekton
if ! kubectl get deployment tekton-pipelines-controller -n tekton-pipelines &> /dev/null; then
    echo "❌ ERROR: Tekton not found"
    echo ""
    echo "Deploy Tekton:"
    echo "  argocd app sync tekton --port-forward --port-forward-namespace argocd --grpc-web"
    exit 1
fi

echo "✓ Tekton deployed"

# 3. Check container registry
if ! kubectl get deployment registry -n container-registry &> /dev/null; then
    echo "❌ ERROR: Container registry not found"
    echo ""
    echo "Deploy container registry:"
    echo "  argocd app sync container-registry --port-forward --port-forward-namespace argocd --grpc-web"
    exit 1
fi

echo "✓ Container registry deployed"

# 4. Check Agent CRDs
if ! kubectl get crd agents.agent.kagenti.dev &> /dev/null; then
    echo "❌ ERROR: Agent CRDs not installed"
    echo ""
    echo "Agent CRDs are required. Check kagenti-operator deployment."
    exit 1
fi

echo "✓ Agent CRDs installed"

# 5. Check github-token-secret
if ! kubectl get secret github-token-secret -n "$NAMESPACE" &> /dev/null; then
    echo "⚠️  WARNING: github-token-secret not found in namespace $NAMESPACE"
    echo ""
    echo "Create GitHub token secret:"
    echo "  kubectl create secret generic github-token-secret \\"
    echo "    --from-literal=username=Ladas \\"
    echo "    --from-literal=token=<YOUR_GITHUB_PAT> \\"
    echo "    -n $NAMESPACE"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo "✓ github-token-secret exists"
fi

echo ""
echo "All prerequisites met!"
echo ""

# Apply AgentBuild CRs
echo "Applying AgentBuild CRs..."
kubectl apply -k "$PROJECT_ROOT/components/03-applications/agents/agent-builds/"

echo ""
echo "✅ AgentBuild CRs applied!"
echo ""

# List AgentBuilds
echo "AgentBuilds in namespace $NAMESPACE:"
kubectl get agentbuild -n "$NAMESPACE"

echo ""

if [ "$WAIT_FOR_COMPLETION" = "true" ]; then
    echo "Monitoring build progress..."
    echo "(Press Ctrl+C to stop monitoring)"
    echo ""

    # Watch AgentBuild status
    kubectl get agentbuild -n "$NAMESPACE" -w &
    WATCH_PID=$!

    # Also show PipelineRuns
    echo ""
    echo "Tekton PipelineRuns:"
    kubectl get pipelineruns -n kagenti-system --watch=false

    # Wait for user interrupt
    wait $WATCH_PID || true
else
    echo "To monitor builds:"
    echo "  kubectl get agentbuild -n $NAMESPACE -w"
    echo ""
    echo "To view Tekton PipelineRuns:"
    echo "  kubectl get pipelineruns -n kagenti-system"
    echo ""
    echo "To view build logs:"
    echo "  kubectl logs -n kagenti-system -l tekton.dev/pipelineRun=<pipelinerun-name> -f"
fi

echo ""
echo "Next steps:"
echo "  1. Wait for builds to complete (check Status column)"
echo "  2. Verify images in registry:"
echo "     kubectl port-forward -n container-registry svc/registry 5000:5000"
echo "     curl http://localhost:5000/v2/_catalog"
echo ""
echo "  3. Sync agents application to deploy built images:"
echo "     argocd app sync agents --port-forward --port-forward-namespace argocd --grpc-web"
echo ""
