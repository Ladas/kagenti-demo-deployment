#!/usr/bin/env bash
# Capture Platform Status Snapshot
# Creates a timestamped snapshot of platform status, test results, and Loki logs
# Usage: ./scripts/capture-platform-snapshot.sh [description]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get description from argument or use default
DESCRIPTION="${1:-manual-snapshot}"

# Create timestamp directory
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_DIR="platform_status_history/${TIMESTAMP}-${DESCRIPTION}"

echo ""
echo -e "${BLUE}Creating Platform Status Snapshot...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Snapshot: $SNAPSHOT_DIR"
echo "Time: $(date)"
echo ""

# Create snapshot directory
mkdir -p "$SNAPSHOT_DIR"

# Function to run command and save output
capture() {
    local name="$1"
    local file="$2"
    shift 2

    echo -e "${CYAN}Capturing: $name${NC}"

    if "$@" > "$SNAPSHOT_DIR/$file" 2>&1; then
        echo -e "  ${GREEN}✓${NC} Saved to: $file"
    else
        echo -e "  ${YELLOW}⚠${NC}  Failed (saved error output): $file"
    fi
}

# 1. Platform Status
echo ""
echo -e "${BLUE}=== Platform Status ===${NC}"
capture "Platform status" "00-platform-status.log" ./scripts/platform-status.sh

# 2. ArgoCD Applications
echo ""
echo -e "${BLUE}=== ArgoCD Applications ===${NC}"
capture "ArgoCD app list" "01-argocd-apps.txt" \
    kubectl get applications -n argocd -o wide

capture "ArgoCD app details (JSON)" "01-argocd-apps.json" \
    kubectl get applications -n argocd -o json

capture "ArgoCD app health summary" "01-argocd-health.txt" \
    bash -c 'kubectl get applications -n argocd -o json | jq -r ".items[] | \"\(.metadata.name): \(.status.health.status) / \(.status.sync.status)\""'

# 3. Pods Status
echo ""
echo -e "${BLUE}=== Pods Status ===${NC}"
capture "All pods" "02-pods-all.txt" \
    kubectl get pods -A -o wide

capture "Pod events" "02-pod-events.txt" \
    kubectl get events -A --sort-by='.lastTimestamp'

capture "Failing pods" "02-pods-failing.txt" \
    bash -c 'kubectl get pods -A -o json | jq -r ".items[] | select(.status.phase != \"Running\" and .status.phase != \"Succeeded\") | \"\(.metadata.namespace)/\(.metadata.name): \(.status.phase)\""'

# 4. Test Results
echo ""
echo -e "${BLUE}=== Test Results ===${NC}"

# Run app state validation tests
echo -e "${CYAN}Running app state validation tests...${NC}"
if pytest tests/validation/test_app_state.py -v \
    --html="$SNAPSHOT_DIR/03-test-app-state.html" \
    --self-contained-html \
    --json-report \
    --json-report-file="$SNAPSHOT_DIR/03-test-app-state.json" \
    > "$SNAPSHOT_DIR/03-test-app-state.log" 2>&1; then
    echo -e "  ${GREEN}✓${NC} App state tests PASSED"
else
    echo -e "  ${RED}✗${NC} App state tests FAILED (see logs)"
fi

# Run E2E tests (optional, can be slow)
if [[ "${RUN_E2E_TESTS:-false}" == "true" ]]; then
    echo -e "${CYAN}Running E2E tests...${NC}"
    if pytest tests/e2e/test_platform_e2e.py -v --tb=short \
        --html="$SNAPSHOT_DIR/03-test-e2e.html" \
        --self-contained-html \
        --json-report \
        --json-report-file="$SNAPSHOT_DIR/03-test-e2e.json" \
        > "$SNAPSHOT_DIR/03-test-e2e.log" 2>&1; then
        echo -e "  ${GREEN}✓${NC} E2E tests PASSED"
    else
        echo -e "  ${RED}✗${NC} E2E tests FAILED (see logs)"
    fi
else
    echo -e "  ${YELLOW}⚠${NC}  E2E tests skipped (set RUN_E2E_TESTS=true to run)"
fi

# 5. Loki Logs (Error and Warning levels)
echo ""
echo -e "${BLUE}=== Loki Logs (Errors & Warnings) ===${NC}"

# Check if Grafana is accessible
if kubectl get pod -n observability -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -q Running; then
    echo -e "${CYAN}Fetching error logs from Loki...${NC}"

    # Get Loki query URL from Grafana
    # Query: {namespace=~".+"} |= "error" or "Error" or "ERROR" (last 6 hours)

    # Use kubectl exec to query Loki via Grafana
    kubectl exec -n observability deployment/grafana -- \
        curl -s -G "http://loki-gateway.observability.svc:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={namespace=~".+"} |~ "(?i)error"' \
        --data-urlencode 'limit=1000' \
        --data-urlencode "start=$(date -u -v-6H +%s)000000000" \
        --data-urlencode "end=$(date -u +%s)000000000" \
        > "$SNAPSHOT_DIR/04-loki-errors.json" 2>&1 || true

    if [ -f "$SNAPSHOT_DIR/04-loki-errors.json" ]; then
        # Parse and format error logs
        jq -r '.data.result[]? | .stream as $labels | .values[]? | "\(.[0] | tonumber / 1000000000 | strftime("%Y-%m-%d %H:%M:%S")) [\($labels.namespace):\($labels.pod)] \(.[1])"' \
            "$SNAPSHOT_DIR/04-loki-errors.json" \
            > "$SNAPSHOT_DIR/04-loki-errors.txt" 2>&1 || echo "No error logs found" > "$SNAPSHOT_DIR/04-loki-errors.txt"

        echo -e "  ${GREEN}✓${NC} Saved to: 04-loki-errors.txt ($(wc -l < "$SNAPSHOT_DIR/04-loki-errors.txt" | tr -d ' ') lines)"
    fi

    echo -e "${CYAN}Fetching warning logs from Loki...${NC}"
    kubectl exec -n observability deployment/grafana -- \
        curl -s -G "http://loki-gateway.observability.svc:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={namespace=~".+"} |~ "(?i)warn"' \
        --data-urlencode 'limit=1000' \
        --data-urlencode "start=$(date -u -v-6H +%s)000000000" \
        --data-urlencode "end=$(date -u +%s)000000000" \
        > "$SNAPSHOT_DIR/04-loki-warnings.json" 2>&1 || true

    if [ -f "$SNAPSHOT_DIR/04-loki-warnings.json" ]; then
        # Parse and format warning logs
        jq -r '.data.result[]? | .stream as $labels | .values[]? | "\(.[0] | tonumber / 1000000000 | strftime("%Y-%m-%d %H:%M:%S")) [\($labels.namespace):\($labels.pod)] \(.[1])"' \
            "$SNAPSHOT_DIR/04-loki-warnings.json" \
            > "$SNAPSHOT_DIR/04-loki-warnings.txt" 2>&1 || echo "No warning logs found" > "$SNAPSHOT_DIR/04-loki-warnings.txt"

        echo -e "  ${GREEN}✓${NC} Saved to: 04-loki-warnings.txt ($(wc -l < "$SNAPSHOT_DIR/04-loki-warnings.txt" | tr -d ' ') lines)"
    fi

    # Also capture recent logs per namespace (last 1 hour, any level)
    echo -e "${CYAN}Fetching recent logs by namespace...${NC}"
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E '^(kagenti|observability|tekton|istio|keycloak|oauth2-proxy)'); do
        kubectl exec -n observability deployment/grafana -- \
            curl -s -G "http://loki-gateway.observability.svc:3100/loki/api/v1/query_range" \
            --data-urlencode "query={namespace=\"$ns\"}" \
            --data-urlencode 'limit=500' \
            --data-urlencode "start=$(date -u -v-1H +%s)000000000" \
            --data-urlencode "end=$(date -u +%s)000000000" \
            2>/dev/null | \
            jq -r '.data.result[]? | .stream as $labels | .values[]? | "\(.[0] | tonumber / 1000000000 | strftime("%Y-%m-%d %H:%M:%S")) [\($labels.pod)] \(.[1])"' \
            > "$SNAPSHOT_DIR/04-loki-$ns.txt" 2>&1 || true

        if [ -f "$SNAPSHOT_DIR/04-loki-$ns.txt" ] && [ -s "$SNAPSHOT_DIR/04-loki-$ns.txt" ]; then
            echo -e "  ${GREEN}✓${NC} $ns: $(wc -l < "$SNAPSHOT_DIR/04-loki-$ns.txt" | tr -d ' ') log lines"
        fi
    done
else
    echo -e "  ${YELLOW}⚠${NC}  Grafana not running, skipping Loki logs"
fi

# 6. Resource Usage
echo ""
echo -e "${BLUE}=== Resource Usage ===${NC}"
capture "Node resources" "05-resources-nodes.txt" \
    kubectl top nodes 2>/dev/null || echo "Metrics not available"

capture "Pod resources" "05-resources-pods.txt" \
    kubectl top pods -A 2>/dev/null || echo "Metrics not available"

# 7. Service Status
echo ""
echo -e "${BLUE}=== Services & Networking ===${NC}"
capture "Services" "06-services.txt" \
    kubectl get svc -A

capture "Gateways" "06-gateways.txt" \
    kubectl get gateway -A -o wide

capture "HTTPRoutes" "06-httproutes.txt" \
    kubectl get httproute -A -o wide

capture "Certificates" "06-certificates.txt" \
    kubectl get certificate -A

# 8. Create summary
echo ""
echo -e "${BLUE}=== Creating Summary ===${NC}"

cat > "$SNAPSHOT_DIR/00-README.md" <<EOF
# Platform Status Snapshot

**Timestamp**: $(date)
**Description**: $DESCRIPTION

## Snapshot Contents

### Platform Status
- \`00-platform-status.log\` - Full platform status check output

### ArgoCD Applications
- \`01-argocd-apps.txt\` - Application list (wide format)
- \`01-argocd-apps.json\` - Application details (JSON)
- \`01-argocd-health.txt\` - Health & sync status summary

### Pods
- \`02-pods-all.txt\` - All pods across namespaces
- \`02-pod-events.txt\` - Recent Kubernetes events
- \`02-pods-failing.txt\` - Pods not in Running/Succeeded state

### Test Results
- \`03-test-app-state.html\` - App state validation test report
- \`03-test-app-state.json\` - App state validation test results (JSON)
- \`03-test-app-state.log\` - App state validation test output
- \`03-test-e2e.html\` - E2E test report (if run)
- \`03-test-e2e.json\` - E2E test results (JSON, if run)
- \`03-test-e2e.log\` - E2E test output (if run)

### Loki Logs
- \`04-loki-errors.json\` - Error logs (last 6 hours, raw JSON)
- \`04-loki-errors.txt\` - Error logs (formatted)
- \`04-loki-warnings.json\` - Warning logs (last 6 hours, raw JSON)
- \`04-loki-warnings.txt\` - Warning logs (formatted)
- \`04-loki-<namespace>.txt\` - Recent logs by namespace (last 1 hour)

### Resources
- \`05-resources-nodes.txt\` - Node resource usage
- \`05-resources-pods.txt\` - Pod resource usage

### Networking
- \`06-services.txt\` - Kubernetes services
- \`06-gateways.txt\` - Gateway API gateways
- \`06-httproutes.txt\` - HTTPRoute configurations
- \`06-certificates.txt\` - TLS certificates

## Quick Analysis

### ArgoCD App Status
\`\`\`
$(cat "$SNAPSHOT_DIR/01-argocd-health.txt" 2>/dev/null || echo "No data")
\`\`\`

### Failing Pods
\`\`\`
$(cat "$SNAPSHOT_DIR/02-pods-failing.txt" 2>/dev/null || echo "No failing pods")
\`\`\`

### Error Count (Last 6h)
\`\`\`
$(wc -l < "$SNAPSHOT_DIR/04-loki-errors.txt" 2>/dev/null | tr -d ' ' || echo "0") error log lines
\`\`\`

### Warning Count (Last 6h)
\`\`\`
$(wc -l < "$SNAPSHOT_DIR/04-loki-warnings.txt" 2>/dev/null | tr -d ' ' || echo "0") warning log lines
\`\`\`

## Grafana Loki Explorer

View logs in Grafana:
https://grafana.localtest.me:9443/d/kagenti-loki-logs/loki-logs-explorer?orgId=1&from=now-6h&to=now&timezone=browser&var-namespace=\$__all&var-pod=\$__all&var-level=\$__all&refresh=10s

## Usage

To compare snapshots:
\`\`\`bash
# Compare ArgoCD status
diff platform_status_history/snapshot1/01-argocd-health.txt platform_status_history/snapshot2/01-argocd-health.txt

# Compare error logs
diff platform_status_history/snapshot1/04-loki-errors.txt platform_status_history/snapshot2/04-loki-errors.txt
\`\`\`
EOF

echo -e "  ${GREEN}✓${NC} Created README.md with summary"

# Print summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Snapshot Complete!${NC}"
echo ""
echo "Location: $SNAPSHOT_DIR"
echo ""
echo "Files created:"
ls -lh "$SNAPSHOT_DIR" | tail -n +2 | awk '{printf "  - %-40s %8s\n", $9, $5}'
echo ""
echo "Total size: $(du -sh "$SNAPSHOT_DIR" | awk '{print $1}')"
echo ""
echo "View README: cat $SNAPSHOT_DIR/00-README.md"
echo ""
