#!/usr/bin/env bash
# Import agents and tools via kagenti-ui pattern (AgentBuild CRDs)
# Usage: ./import-agents-via-ui.sh <repo-url> <context-path> <agent-name> [namespace]
#
# This script creates AgentBuild CRDs that trigger Tekton pipelines to:
# 1. Clone the source repository
# 2. Build the agent Docker image
# 3. Push image to local registry
# 4. Deploy the agent
#
# Example:
#   ./import-agents-via-ui.sh \
#     "https://github.com/redhat-et/agent-examples.git" \
#     "agents/weather" \
#     "weather-agent"

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parameters
REPO_URL="${1:?Repository URL required (e.g., https://github.com/redhat-et/agent-examples.git)}"
CONTEXT_PATH="${2:?Context path required (e.g., agents/weather)}"
AGENT_NAME="${3:?Agent name required (e.g., weather-agent)}"
NAMESPACE="${4:-team1}"  # Default to team1
BUILD_MODE="${BUILD_MODE:-dev}"  # dev, dev-local, dev-external, preprod, prod
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-localhost:5000}"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Importing Agent via AgentBuild CRD${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Repository:${NC}    $REPO_URL"
echo -e "${YELLOW}Context Path:${NC}  $CONTEXT_PATH"
echo -e "${YELLOW}Agent Name:${NC}    $AGENT_NAME"
echo -e "${YELLOW}Namespace:${NC}     $NAMESPACE"
echo -e "${YELLOW}Build Mode:${NC}    $BUILD_MODE"
echo -e "${YELLOW}Image Tag:${NC}     $IMAGE_TAG"
echo -e "${YELLOW}Registry:${NC}      $REGISTRY"
echo ""

# Step 1: Ensure namespace exists
echo -e "${YELLOW}📝 Ensuring namespace exists...${NC}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo -e "${GREEN}✅ Namespace $NAMESPACE already exists${NC}"
else
  echo -e "${YELLOW}Creating namespace $NAMESPACE...${NC}"
  kubectl create namespace "$NAMESPACE"
  echo -e "${GREEN}✅ Namespace created${NC}"
fi
echo ""

# Step 2: Create AgentBuild CRD
echo -e "${YELLOW}🔨 Creating AgentBuild CRD...${NC}"

AGENT_BUILD_NAME="${AGENT_NAME}-build"

# Create the AgentBuild manifest
cat <<EOF | kubectl apply -f -
apiVersion: agent.kagenti.dev/v1alpha1
kind: AgentBuild
metadata:
  name: ${AGENT_BUILD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${AGENT_NAME}
    kagenti.io/type: agent
spec:
  mode: ${BUILD_MODE}

  # Source configuration
  pipeline:
    namespace: kagenti-system
    parameters:
      - name: SOURCE_URL
        value: "${REPO_URL}"
      - name: SOURCE_REVISION
        value: "main"
      - name: SOURCE_CONTEXT_DIR
        value: "${CONTEXT_PATH}"

  # Build output configuration
  buildOutput:
    image: "${AGENT_NAME}"
    imageTag: "${IMAGE_TAG}"
    imageRegistry: "${REGISTRY}"

  # Cleanup after successful build
  cleanupAfterBuild: true

  # Labels to apply to the agent
  labels:
    kagenti.io/agent-name: "${AGENT_NAME}"
    kagenti.io/imported-via: "script"
EOF

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ AgentBuild CRD created: ${AGENT_BUILD_NAME}${NC}"
else
  echo -e "${RED}❌ Failed to create AgentBuild CRD${NC}"
  exit 1
fi
echo ""

# Step 3: Monitor build progress
echo -e "${YELLOW}⏳ Monitoring build progress (timeout: 10 minutes)...${NC}"
echo ""

# Wait for AgentBuild to start
TIMEOUT=600  # 10 minutes
ELAPSED=0
POLL_INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT ]; do
  # Get build status
  BUILD_STATUS=$(kubectl get agentbuild "${AGENT_BUILD_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")

  BUILD_MESSAGE=$(kubectl get agentbuild "${AGENT_BUILD_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.message}' 2>/dev/null || echo "")

  # Show current status
  echo -ne "\r${YELLOW}Status:${NC} $BUILD_STATUS  "
  [ -n "$BUILD_MESSAGE" ] && echo -ne "${YELLOW}Message:${NC} $BUILD_MESSAGE"

  # Check if build completed
  case "$BUILD_STATUS" in
    "Succeeded"|"Complete")
      echo ""
      echo -e "${GREEN}✅ Build completed successfully!${NC}"
      break
      ;;
    "Failed")
      echo ""
      echo -e "${RED}❌ Build failed${NC}"
      echo ""
      echo -e "${YELLOW}Checking Tekton pipeline logs...${NC}"

      # Try to find the PipelineRun
      PIPELINE_RUN=$(kubectl get pipelinerun -n kagenti-system \
        --sort-by=.metadata.creationTimestamp \
        -l "agent.kagenti.dev/agentbuild=${AGENT_BUILD_NAME}" \
        -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || echo "")

      if [ -n "$PIPELINE_RUN" ]; then
        echo -e "${YELLOW}PipelineRun: ${PIPELINE_RUN}${NC}"
        echo ""
        kubectl logs -n kagenti-system -l tekton.dev/pipelineRun="$PIPELINE_RUN" --tail=50 || true
      fi

      exit 1
      ;;
    *)
      # Still building
      sleep $POLL_INTERVAL
      ELAPSED=$((ELAPSED + POLL_INTERVAL))
      ;;
  esac
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo ""
  echo -e "${YELLOW}⚠️  Build did not complete within ${TIMEOUT}s${NC}"
  echo -e "${YELLOW}Build status: ${BUILD_STATUS}${NC}"
  echo ""
  echo -e "${YELLOW}You can continue monitoring with:${NC}"
  echo -e "  kubectl get agentbuild ${AGENT_BUILD_NAME} -n ${NAMESPACE} -w"
  exit 1
fi

echo ""

# Step 4: Verify image in registry
echo -e "${YELLOW}📦 Verifying image in registry...${NC}"

# For localhost registry, we need to check via docker
if [[ "$REGISTRY" == localhost* ]]; then
  if docker exec kagenti-demo-control-plane crictl images | grep -q "${AGENT_NAME}:${IMAGE_TAG}"; then
    echo -e "${GREEN}✅ Image found in Kind cluster: ${AGENT_NAME}:${IMAGE_TAG}${NC}"
  else
    echo -e "${YELLOW}⚠️  Image not yet loaded into Kind cluster${NC}"
  fi
else
  echo -e "${YELLOW}External registry - skipping local verification${NC}"
fi
echo ""

# Step 5: Check if agent pod is deployed
echo -e "${YELLOW}🚀 Checking agent deployment...${NC}"

# Wait a bit for deployment to be created
sleep 5

if kubectl get deployment "${AGENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
  echo -e "${GREEN}✅ Agent deployment found: ${AGENT_NAME}${NC}"

  # Wait for pod to be ready
  echo -e "${YELLOW}Waiting for pod to be ready...${NC}"
  kubectl wait --for=condition=Ready pod -l app="${AGENT_NAME}" -n "${NAMESPACE}" --timeout=120s || {
    echo -e "${YELLOW}⚠️  Pod not ready after 120s${NC}"
    kubectl get pods -n "${NAMESPACE}" -l app="${AGENT_NAME}"
  }
else
  echo -e "${YELLOW}⚠️  Agent deployment not found (may be created by operator later)${NC}"
fi
echo ""

# Step 6: Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Agent import complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Check agent build status:"
echo -e "   ${BLUE}kubectl get agentbuild ${AGENT_BUILD_NAME} -n ${NAMESPACE}${NC}"
echo ""
echo "2. View agent pods:"
echo -e "   ${BLUE}kubectl get pods -n ${NAMESPACE} -l app=${AGENT_NAME}${NC}"
echo ""
echo "3. Check agent logs:"
echo -e "   ${BLUE}kubectl logs -n ${NAMESPACE} -l app=${AGENT_NAME} --tail=100 -f${NC}"
echo ""
echo "4. Test agent (if it has an HTTP endpoint):"
echo -e "   ${BLUE}kubectl run test-agent -n ${NAMESPACE} --image=curlimages/curl:latest --restart=Never --rm -it \\${NC}"
echo -e "   ${BLUE}  --command -- curl -s http://${AGENT_NAME}.${NAMESPACE}.svc:8000/.well-known/agent.json${NC}"
echo ""
