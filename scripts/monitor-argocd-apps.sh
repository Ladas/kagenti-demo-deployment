#!/usr/bin/env bash
# Monitor ArgoCD Application Sync Status with Enhanced Tables
# Monitors all ArgoCD applications for health and sync status with pod-level visibility
# Usage: ./scripts/monitor-argocd-apps.sh [timeout_seconds]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
MONITOR_TIMEOUT="${1:-900}"  # Default: 15 minutes (900 seconds)
POLL_INTERVAL=30  # Check every 30 seconds (reduced from 10s for less noise)

echo ""
echo -e "${BLUE}Monitoring ArgoCD Applications with Enhanced Status Tables...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Timeout: ${MONITOR_TIMEOUT}s ($(($MONITOR_TIMEOUT / 60)) minutes)"
echo "Poll Interval: ${POLL_INTERVAL}s"
echo ""

# App classification (CRITICAL vs OPTIONAL)
CRITICAL_APPS=(
    "gateway-api"
    "cert-manager"
    "istio-base"
    "istiod"
    "istio-config"
    "tekton"
    "keycloak"
    "keycloak-operator"
    "kagenti-operator"
    "kagenti-platform-operator"
    "platform"
    "kagenti-ui"
)

# Optional apps can be Progressing without failing
OPTIONAL_APPS=(
    "observability"
    "kiali"
    "ollama"
    "agents"
)

# Function to check if app is critical
is_critical_app() {
    local app_name="$1"
    for critical in "${CRITICAL_APPS[@]}"; do
        if [[ "$app_name" == "$critical" ]] || [[ "$app_name" == *"oauth2-proxy"* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if app should be skipped from display (still monitored, just not shown in agent filtering)
is_agent_app() {
    local app_name="$1"
    [[ "$app_name" == *"-agent" ]] && return 0
    [[ "$app_name" == "agents" ]] && return 0
    return 1
}

# Function to print ArgoCD application status table
print_argocd_status_table() {
    echo ""
    echo -e "${CYAN}=== ArgoCD Applications Status ===${NC}"

    # Get all applications
    local all_apps=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null)
    if [ -z "$all_apps" ] || [ "$all_apps" = "null" ]; then
        echo "No applications found"
        return
    fi

    # Count totals
    local total_apps=$(echo "$all_apps" | jq -r '.items | length')
    local healthy_apps=$(echo "$all_apps" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')

    echo "Apps: ${healthy_apps}/${total_apps} Healthy"
    echo ""

    # Print table header
    printf "%-30s %-12s %-12s %-10s %s\n" "App Name" "Sync" "Health" "Type" "Status"
    echo "────────────────────────────────────────────────────────────────────────────────"

    # Print each app
    echo "$all_apps" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"' | while IFS='|' read -r app sync health; do
        # Determine app type
        local app_type="OPTIONAL"
        if is_critical_app "$app"; then
            app_type="CRITICAL"
        fi

        # Determine status icon
        local status_icon=""
        local color=$NC

        if [ "$health" = "Healthy" ] && [ "$sync" = "Synced" ]; then
            status_icon="✅"
            color=$GREEN
        elif [ "$health" = "Progressing" ]; then
            status_icon="⚠️ "
            color=$YELLOW
        elif [ "$health" = "Degraded" ] || [ "$health" = "Missing" ]; then
            status_icon="❌"
            color=$RED
        else
            status_icon="○"
            color=$CYAN
        fi

        printf "${color}%-30s %-12s %-12s %-10s %s${NC}\n" "$app" "$sync" "$health" "$app_type" "$status_icon"
    done

    echo ""
}

# Function to print pod status by namespace
print_pod_status_table() {
    echo ""
    echo -e "${CYAN}=== Pods by Namespace ===${NC}"

    # Get all pods across all namespaces
    local all_pods=$(kubectl get pods -A -o json 2>/dev/null)
    if [ -z "$all_pods" ] || [ "$all_pods" = "null" ]; then
        echo "No pods found"
        return
    fi

    # Get unique namespaces
    local namespaces=$(echo "$all_pods" | jq -r '.items[].metadata.namespace' | sort -u)

    # Count totals across all namespaces
    local total_pods=0
    local total_ready=0
    local total_running=0
    local total_pending=0
    local total_crashloop=0
    local total_imagepull=0

    # Print table header
    printf "%-25s %-8s %-8s %-8s %-10s %-10s %s\n" "Namespace" "Ready" "Running" "Pending" "CrashLoop" "ImagePull" "Status"
    echo "────────────────────────────────────────────────────────────────────────────────────────"

    # Process each namespace
    for ns in $namespaces; do
        # Get pods in this namespace
        local ns_pods=$(echo "$all_pods" | jq -r --arg ns "$ns" '.items[] | select(.metadata.namespace == $ns)')

        if [ -z "$ns_pods" ]; then
            continue
        fi

        # Count pod states
        local pod_count=$(echo "$ns_pods" | jq -s 'length')
        local running=$(echo "$ns_pods" | jq -s '[.[] | select(.status.phase == "Running")] | length')
        local pending=$(echo "$ns_pods" | jq -s '[.[] | select(.status.phase == "Pending")] | length')

        # Count CrashLoopBackOff and ImagePullBackOff
        local crashloop=$(echo "$ns_pods" | jq -s '[.[] | select(.status.containerStatuses[]? | .state.waiting?.reason == "CrashLoopBackOff")] | length')
        local imagepull=$(echo "$ns_pods" | jq -s '[.[] | select(.status.containerStatuses[]? | .state.waiting?.reason == "ImagePullBackOff")] | length')

        # Count ready pods (all containers ready)
        local ready=$(echo "$ns_pods" | jq -s '[.[] | select(.status.conditions[]? | select(.type == "Ready" and .status == "True"))] | length')

        # Update totals
        total_pods=$((total_pods + pod_count))
        total_ready=$((total_ready + ready))
        total_running=$((total_running + running))
        total_pending=$((total_pending + pending))
        total_crashloop=$((total_crashloop + crashloop))
        total_imagepull=$((total_imagepull + imagepull))

        # Determine status
        local status_icon=""
        local color=$NC

        if [ "$ready" -eq "$pod_count" ] && [ "$crashloop" -eq 0 ] && [ "$imagepull" -eq 0 ]; then
            status_icon="✅"
            color=$GREEN
        elif [ "$crashloop" -gt 0 ] || [ "$imagepull" -gt 0 ]; then
            status_icon="❌"
            color=$RED
        elif [ "$pending" -gt 0 ] || [ "$ready" -lt "$pod_count" ]; then
            status_icon="⚠️ "
            color=$YELLOW
        else
            status_icon="○"
            color=$CYAN
        fi

        printf "${color}%-25s %-8s %-8s %-8s %-10s %-10s %s${NC}\n" \
            "$ns" "${ready}/${pod_count}" "$running" "$pending" "$crashloop" "$imagepull" "$status_icon"
    done

    # Print totals
    echo "────────────────────────────────────────────────────────────────────────────────────────"
    printf "%-25s %-8s %-8s %-8s %-10s %-10s\n" \
        "TOTAL" "${total_ready}/${total_pods}" "$total_running" "$total_pending" "$total_crashloop" "$total_imagepull"

    echo ""
}

# Function to print resource usage
print_resource_usage() {
    echo ""
    echo -e "${CYAN}=== Resource Usage ===${NC}"

    # Total memory (GitHub Actions runner: 15.62 GB)
    TOTAL_MEM_GB=15.62

    # Get memory usage (in GB)
    if [ -f /proc/meminfo ]; then
        MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        MEM_AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))

        MEM_USED_GB=$(echo "scale=2; $MEM_USED / 1024 / 1024" | bc)
        MEM_AVAILABLE_GB=$(echo "scale=2; $MEM_AVAILABLE / 1024 / 1024" | bc)
        MEM_PCT=$(echo "scale=1; ($MEM_USED * 100) / $MEM_TOTAL" | bc)

        local color=$GREEN
        if (( $(echo "$MEM_PCT > 85" | bc -l) )); then
            color=$RED
        elif (( $(echo "$MEM_PCT > 70" | bc -l) )); then
            color=$YELLOW
        fi

        printf "${color}Memory: %.2f GB / %.2f GB used (%.1f%%)${NC}\n" \
            "$MEM_USED_GB" "$TOTAL_MEM_GB" "$MEM_PCT"
        printf "Available: %.2f GB\n" "$MEM_AVAILABLE_GB"
    fi

    # Disk usage
    if command -v df &> /dev/null; then
        DISK_USAGE=$(df -BG /var/lib/docker 2>/dev/null | tail -1 | awk '{print $3,$2,$5}' || echo "N/A N/A N/A")
        DISK_USED=$(echo $DISK_USAGE | awk '{print $1}')
        DISK_TOTAL=$(echo $DISK_USAGE | awk '{print $2}')
        DISK_PCT=$(echo $DISK_USAGE | awk '{print $3}')

        printf "Disk (docker): %s / %s (%s)\n" "$DISK_USED" "$DISK_TOTAL" "$DISK_PCT"
    fi

    # CPU load
    if [ -f /proc/loadavg ]; then
        LOAD_AVG=$(cat /proc/loadavg | awk '{print $1,$2,$3}')
        printf "Load Average: %s (1/5/15 min)\n" "$LOAD_AVG"
    fi

    # Docker stats
    if command -v docker &> /dev/null; then
        CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
        printf "Docker Containers: %d running\n" "$CONTAINER_COUNT"
    fi

    # Kind cluster
    if command -v kind &> /dev/null; then
        CLUSTER_NAME=$(kind get clusters 2>/dev/null | head -1)
        if [ -n "$CLUSTER_NAME" ]; then
            printf "Kind Cluster: %s\n" "$CLUSTER_NAME"
        fi
    fi

    echo ""
}

# Monitor application sync status
MONITOR_START=$(date +%s)
LAST_STATUS=""

while [ $(($(date +%s) - MONITOR_START)) -lt $MONITOR_TIMEOUT ]; do
    ELAPSED=$(($(date +%s) - MONITOR_START))

    # Get all applications
    ALL_APPS=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null)

    if [ -z "$ALL_APPS" ] || [ "$ALL_APPS" = "null" ]; then
        echo "Waiting for applications to appear..."
        sleep $POLL_INTERVAL
        continue
    fi

    # Count apps by status
    TOTAL_APPS=$(echo "$ALL_APPS" | jq -r '.items | length')
    HEALTHY_APPS=$(echo "$ALL_APPS" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')
    SYNCED_APPS=$(echo "$ALL_APPS" | jq -r '[.items[] | select(.status.sync.status == "Synced")] | length')
    PROGRESSING_APPS=$(echo "$ALL_APPS" | jq -r '[.items[] | select(.status.health.status == "Progressing")] | length')
    DEGRADED_APPS=$(echo "$ALL_APPS" | jq -r '[.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing")] | length')

    # Count critical vs optional app health
    CRITICAL_HEALTHY=0
    CRITICAL_TOTAL=0
    OPTIONAL_HEALTHY=0
    OPTIONAL_PROGRESSING=0
    OPTIONAL_TOTAL=0

    while read -r app_line; do
        app_name=$(echo "$app_line" | jq -r '.metadata.name')
        health=$(echo "$app_line" | jq -r '.status.health.status // "Unknown"')

        if is_critical_app "$app_name"; then
            CRITICAL_TOTAL=$((CRITICAL_TOTAL + 1))
            [ "$health" = "Healthy" ] && CRITICAL_HEALTHY=$((CRITICAL_HEALTHY + 1))
        else
            # Skip agent apps from optional count (they're examples)
            if ! is_agent_app "$app_name"; then
                OPTIONAL_TOTAL=$((OPTIONAL_TOTAL + 1))
                [ "$health" = "Healthy" ] && OPTIONAL_HEALTHY=$((OPTIONAL_HEALTHY + 1))
                [ "$health" = "Progressing" ] && OPTIONAL_PROGRESSING=$((OPTIONAL_PROGRESSING + 1))
            fi
        fi
    done < <(echo "$ALL_APPS" | jq -c '.items[]')

    # Create status summary
    CURRENT_STATUS="Apps: $HEALTHY_APPS/$TOTAL_APPS Healthy | Synced: $SYNCED_APPS/$TOTAL_APPS | Progressing: $PROGRESSING_APPS | Degraded: $DEGRADED_APPS"

    # Only update display if status changed
    if [ "$CURRENT_STATUS" != "$LAST_STATUS" ]; then
        # Only clear screen if in interactive terminal (not CI)
        if [ -t 1 ] && [ -n "${TERM:-}" ]; then
            clear
        else
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        fi
        echo ""
        echo -e "${BLUE}Monitoring ArgoCD Applications with Enhanced Status Tables...${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        TIMESTAMP=$(date "+%H:%M:%S")

        if [ "$DEGRADED_APPS" -gt 0 ]; then
            echo -e "[$TIMESTAMP] ${RED}$CURRENT_STATUS${NC}"
        elif [ "$PROGRESSING_APPS" -gt 0 ]; then
            echo -e "[$TIMESTAMP] ${YELLOW}$CURRENT_STATUS${NC}"
        else
            echo -e "[$TIMESTAMP] ${GREEN}$CURRENT_STATUS${NC}"
        fi

        # Print status tables
        print_argocd_status_table
        print_pod_status_table
        print_resource_usage

        # Print progress summary
        echo -e "${CYAN}Progress Summary:${NC}"
        echo "  Elapsed: ${ELAPSED}s / Timeout: ${MONITOR_TIMEOUT}s ($(($ELAPSED / 60))m / $(($MONITOR_TIMEOUT / 60))m)"

        if [ $CRITICAL_TOTAL -gt 0 ]; then
            if [ "$CRITICAL_HEALTHY" -eq "$CRITICAL_TOTAL" ]; then
                echo -e "  CRITICAL: ${GREEN}${CRITICAL_HEALTHY}/${CRITICAL_TOTAL} Healthy ✅${NC}"
            else
                echo -e "  CRITICAL: ${YELLOW}${CRITICAL_HEALTHY}/${CRITICAL_TOTAL} Healthy ⚠️${NC}"
            fi
        fi

        if [ $OPTIONAL_TOTAL -gt 0 ]; then
            if [ "$OPTIONAL_PROGRESSING" -gt 0 ]; then
                echo -e "  OPTIONAL: ${YELLOW}${OPTIONAL_HEALTHY}/${OPTIONAL_TOTAL} Healthy, ${OPTIONAL_PROGRESSING}/${OPTIONAL_TOTAL} Progressing ⚠️${NC}"
            else
                echo -e "  OPTIONAL: ${GREEN}${OPTIONAL_HEALTHY}/${OPTIONAL_TOTAL} Healthy ✅${NC}"
            fi
        fi

        echo ""

        # Memory pressure check
        if [ -f /proc/meminfo ]; then
            MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            MEM_AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            MEM_AVAILABLE_GB=$(echo "scale=2; $MEM_AVAILABLE / 1024 / 1024" | bc)

            if (( $(echo "$MEM_AVAILABLE_GB < 2.0" | bc -l) )); then
                echo ""
                echo -e "${RED}⚠️  WARNING: Low memory! Only ${MEM_AVAILABLE_GB} GB available${NC}"
                echo -e "${RED}Platform may experience slowdowns or OOM errors${NC}"
                echo ""
            fi
        fi

        LAST_STATUS="$CURRENT_STATUS"
    fi

    # Check for immediate failure conditions
    # FAIL if any CRITICAL app is Degraded
    CRITICAL_DEGRADED_APPS=$(echo "$ALL_APPS" | jq -r '[.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing") | .metadata.name] | .[]')

    if [ -n "$CRITICAL_DEGRADED_APPS" ]; then
        for degraded_app in $CRITICAL_DEGRADED_APPS; do
            if is_critical_app "$degraded_app"; then
                echo ""
                echo -e "${RED}❌ CRITICAL app '$degraded_app' is Degraded or Missing${NC}"
                echo -e "${RED}Cannot proceed with degraded critical applications${NC}"
                echo ""
                exit 1
            fi
        done
    fi

    # Success: All apps healthy and synced
    if [ "$TOTAL_APPS" -gt 0 ] && [ "$HEALTHY_APPS" -eq "$TOTAL_APPS" ] && [ "$SYNCED_APPS" -eq "$TOTAL_APPS" ]; then
        echo ""
        echo -e "${GREEN}✅ All applications are healthy and synced!${NC}"
        echo "Total time: ${ELAPSED}s ($(($ELAPSED / 60))m)"
        echo ""
        exit 0
    fi

    # Wait before next check
    sleep $POLL_INTERVAL
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${YELLOW}⚠️  Timeout reached after ${MONITOR_TIMEOUT}s ($(($MONITOR_TIMEOUT / 60))m)${NC}"
echo ""

# Final status check
FINAL_APPS=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null)
FINAL_HEALTHY=$(echo "$FINAL_APPS" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')
FINAL_TOTAL=$(echo "$FINAL_APPS" | jq -r '.items | length')
FINAL_SYNCED=$(echo "$FINAL_APPS" | jq -r '[.items[] | select(.status.sync.status == "Synced")] | length')

echo "Final status: $FINAL_HEALTHY/$FINAL_TOTAL healthy, $FINAL_SYNCED/$FINAL_TOTAL synced"
echo ""

# Check if CRITICAL apps are healthy
echo "Checking critical applications..."
CRITICAL_FAILED=0

for critical_app in "${CRITICAL_APPS[@]}"; do
    APP_HEALTH=$(echo "$FINAL_APPS" | jq -r --arg app "$critical_app" '[.items[] | select(.metadata.name == $app) | .status.health.status] | .[0] // "Missing"')

    if [ "$APP_HEALTH" != "Healthy" ]; then
        echo -e "  ${RED}❌ Critical app '$critical_app' is $APP_HEALTH${NC}"
        CRITICAL_FAILED=1
    else
        echo -e "  ${GREEN}✓ $critical_app is Healthy${NC}"
    fi
done

# Also check oauth2-proxy apps (they're critical)
OAUTH_APPS=$(echo "$FINAL_APPS" | jq -r '[.items[] | select(.metadata.name | contains("oauth2-proxy")) | .metadata.name] | .[]')
for oauth_app in $OAUTH_APPS; do
    APP_HEALTH=$(echo "$FINAL_APPS" | jq -r --arg app "$oauth_app" '[.items[] | select(.metadata.name == $app) | .status.health.status] | .[0] // "Missing"')

    if [ "$APP_HEALTH" != "Healthy" ]; then
        echo -e "  ${RED}❌ Critical app '$oauth_app' is $APP_HEALTH${NC}"
        CRITICAL_FAILED=1
    else
        echo -e "  ${GREEN}✓ $oauth_app is Healthy${NC}"
    fi
done

echo ""

if [ $CRITICAL_FAILED -eq 1 ]; then
    echo -e "${RED}❌ Some critical applications are not healthy${NC}"
    echo ""
    exit 1
fi

# Check if ALL apps are Degraded (total failure)
if [ "$FINAL_HEALTHY" -eq 0 ] && [ "$FINAL_TOTAL" -gt 0 ]; then
    echo -e "${RED}❌ No healthy applications found${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ All critical applications are healthy${NC}"
echo -e "${YELLOW}⚠️  Some optional applications may still be progressing (observability, Kiali, Ollama)${NC}"
echo ""

exit 0
