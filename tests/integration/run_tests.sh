#!/bin/bash
# Integration Test Runner for Kagenti Platform
#
# Usage:
#   ./run_tests.sh [options]
#
# Options:
#   --fast        Run only critical tests (quick smoke test)
#   --slow        Run all tests including slow tests
#   --parallel    Run tests in parallel (requires pytest-xdist)
#   --html        Generate HTML report
#   --category    Run specific category (infrastructure, observability, platform, agents)
#   --help        Show this help message

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default options
PYTEST_ARGS="-v"
RUN_MODE="default"
CATEGORY=""
GENERATE_HTML=false
PARALLEL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --fast)
      RUN_MODE="fast"
      shift
      ;;
    --slow)
      RUN_MODE="slow"
      shift
      ;;
    --parallel)
      PARALLEL=true
      shift
      ;;
    --html)
      GENERATE_HTML=true
      shift
      ;;
    --category)
      CATEGORY="$2"
      shift 2
      ;;
    --help)
      head -n 15 "$0" | tail -n 13
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Check kubectl context
echo -e "${YELLOW}Checking Kubernetes context...${NC}"
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")

if [[ -z "$CURRENT_CONTEXT" ]]; then
  echo -e "${RED}Error: No kubectl context set${NC}"
  echo "Please run: kubectl config use-context kind-kagenti-demo"
  exit 1
fi

if [[ "$CURRENT_CONTEXT" != *"kagenti"* ]]; then
  echo -e "${YELLOW}Warning: Current context is '$CURRENT_CONTEXT'${NC}"
  echo "Expected context containing 'kagenti' (e.g., kind-kagenti-demo)"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo -e "${GREEN}Using context: $CURRENT_CONTEXT${NC}"

# Check if cluster is accessible
echo -e "${YELLOW}Checking cluster accessibility...${NC}"
if ! kubectl get nodes &>/dev/null; then
  echo -e "${RED}Error: Cannot access Kubernetes cluster${NC}"
  exit 1
fi

echo -e "${GREEN}Cluster is accessible${NC}"

# Check Python dependencies
echo -e "${YELLOW}Checking Python dependencies...${NC}"
if ! python3 -c "import pytest" &>/dev/null; then
  echo -e "${RED}Error: pytest not installed${NC}"
  echo "Please run: pip install -r requirements.txt"
  exit 1
fi

echo -e "${GREEN}Python dependencies OK${NC}"

# Build pytest command based on options
if [[ "$RUN_MODE" == "fast" ]]; then
  echo -e "${YELLOW}Running fast tests (critical markers only)...${NC}"
  PYTEST_ARGS="$PYTEST_ARGS -m critical"
elif [[ "$RUN_MODE" == "slow" ]]; then
  echo -e "${YELLOW}Running all tests including slow tests...${NC}"
  PYTEST_ARGS="$PYTEST_ARGS"
else
  echo -e "${YELLOW}Running default tests (excluding slow)...${NC}"
  PYTEST_ARGS="$PYTEST_ARGS -m 'not slow'"
fi

# Add parallel execution
if [[ "$PARALLEL" == true ]]; then
  echo -e "${YELLOW}Enabling parallel execution...${NC}"
  PYTEST_ARGS="$PYTEST_ARGS -n auto"
fi

# Add HTML report generation
if [[ "$GENERATE_HTML" == true ]]; then
  echo -e "${YELLOW}Enabling HTML report generation...${NC}"
  PYTEST_ARGS="$PYTEST_ARGS --html=report.html --self-contained-html"
fi

# Add JUnit XML for CI
PYTEST_ARGS="$PYTEST_ARGS --junitxml=junit.xml"

# Add timeout
PYTEST_ARGS="$PYTEST_ARGS --timeout=600"

# Select test category
if [[ -n "$CATEGORY" ]]; then
  echo -e "${YELLOW}Running category: $CATEGORY${NC}"
  case $CATEGORY in
    infrastructure)
      TEST_FILE="test_infrastructure.py"
      ;;
    observability)
      TEST_FILE="test_observability.py"
      ;;
    platform)
      TEST_FILE="test_platform.py"
      ;;
    agents)
      TEST_FILE="test_agents.py"
      ;;
    *)
      echo -e "${RED}Unknown category: $CATEGORY${NC}"
      echo "Valid categories: infrastructure, observability, platform, agents"
      exit 1
      ;;
  esac
else
  echo -e "${YELLOW}Running all test categories${NC}"
  TEST_FILE=""
fi

# Display test plan
echo ""
echo -e "${GREEN}=== Test Execution Plan ===${NC}"
echo "Mode: $RUN_MODE"
echo "Category: ${CATEGORY:-all}"
echo "Parallel: $PARALLEL"
echo "HTML Report: $GENERATE_HTML"
echo "Pytest args: $PYTEST_ARGS"
echo "Test file: ${TEST_FILE:-.}"
echo ""

# Run tests
echo -e "${GREEN}=== Starting Tests ===${NC}"
pytest $PYTEST_ARGS $TEST_FILE

TEST_EXIT_CODE=$?

# Display results
echo ""
if [[ $TEST_EXIT_CODE -eq 0 ]]; then
  echo -e "${GREEN}=== All Tests Passed ===${NC}"
else
  echo -e "${RED}=== Some Tests Failed ===${NC}"
  echo "Exit code: $TEST_EXIT_CODE"
fi

if [[ "$GENERATE_HTML" == true ]]; then
  echo -e "${GREEN}HTML report generated: report.html${NC}"
fi

echo -e "${GREEN}JUnit XML report generated: junit.xml${NC}"

exit $TEST_EXIT_CODE
