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
MONITOR_TIMEOUT="${1:-1800}"  # Default: 30 minutes (1800 seconds)
POLL_INTERVAL=15  # Check every 15 seconds
DEGRADED_GRACE_PERIOD=600  # 10 minutes grace period for Degraded apps to recover
KUBECTL_TIMEOUT=60  # Timeout for kubectl commands (seconds) - increased for resource-constrained CI

# Helper function: Run kubectl with timeout
kubectl_with_timeout() {
    local timeout_duration=${KUBECTL_TIMEOUT}
    local cmd="$@"

    # Run command in background
    eval "$cmd" &
    local cmd_pid=$!

    # Wait with timeout
    local count=0
    while kill -0 $cmd_pid 2>/dev/null; do
        if [ $count -ge $timeout_duration ]; then
            kill -9 $cmd_pid 2>/dev/null
            echo "ERROR: kubectl command timed out after ${timeout_duration}s" >&2
            return 124  # timeout exit code
        fi
        sleep 1
        count=$((count + 1))
    done

    # Get exit code
    wait $cmd_pid
    return $?
}

# Track when apps first became Degraded (file-based, bash 3.2 compatible)
# Creates timestamped files in /tmp/argocd-monitor-degraded-<app-name>
DEGRADED_TRACKING_DIR="/tmp/argocd-monitor-degraded-$$"
mkdir -p "$DEGRADED_TRACKING_DIR"

# Cleanup on exit
trap "rm -rf $DEGRADED_TRACKING_DIR" EXIT

echo ""
echo -e "${BLUE}Monitoring ArgoCD Applications with Enhanced Status Tables...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Timeout: ${MONITOR_TIMEOUT}s ($(($MONITOR_TIMEOUT / 60)) minutes)"
echo "Poll Interval: ${POLL_INTERVAL}s"
echo "Degraded Grace Period: ${DEGRADED_GRACE_PERIOD}s ($(($DEGRADED_GRACE_PERIOD / 60)) minutes)"
echo ""
echo -e "${CYAN}Smart Failure Logic:${NC}"
echo "  - CRITICAL apps: Immediate warning when Degraded, fail after ${DEGRADED_GRACE_PERIOD}s"
echo "  - OPTIONAL apps: Can remain Progressing indefinitely"
echo "  - Allows self-healing: Degraded → Progressing → Healthy"
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
    "container-registry"
    "keycloak-platform-rbac"
    "opentelemetry-operator"
    "reflector"
)

# Optional apps can be Progressing without failing
OPTIONAL_APPS=(
    "observability"
    "kiali"
    "ollama"
    "agents"
    "spire"
    "spire-crds"
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

# Function to print detailed failure information for degraded pods
print_degraded_pod_details() {
    local degraded_apps="$1"

    if [ -z "$degraded_apps" ] || [ "$degraded_apps" = "0" ]; then
        return
    fi

    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}⚠️  DEGRADED PODS DETECTED - Failure Details${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Get all degraded applications
    kubectl get applications -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing") | .metadata.name' | \
        while read -r app_name; do

        echo -e "${YELLOW}Application: ${app_name}${NC}"

        # Get the namespace from the app spec
        local app_namespace=$(kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || echo "$app_name")

        # Find failing pods in the namespace
        local failing_pods=$(kubectl get pods -n "$app_namespace" --no-headers 2>/dev/null | grep -v "Running\|Completed" || echo "")

        if [ -n "$failing_pods" ]; then
            echo -e "${CYAN}  Namespace: ${app_namespace}${NC}"
            echo ""

            while IFS= read -r pod_line; do
                local pod_name=$(echo "$pod_line" | awk '{print $1}')
                local pod_status=$(echo "$pod_line" | awk '{print $3}')
                local pod_ready=$(echo "$pod_line" | awk '{print $2}')

                echo -e "${RED}    Pod: ${pod_name}${NC}"
                echo -e "${RED}    Status: ${pod_status} (Ready: ${pod_ready})${NC}"

                # Get pod reason/message from conditions
                local pod_reason=$(kubectl get pod "$pod_name" -n "$app_namespace" -o jsonpath='{.status.conditions[?(@.status=="False")].reason}' 2>/dev/null || echo "Unknown")
                local pod_message=$(kubectl get pod "$pod_name" -n "$app_namespace" -o jsonpath='{.status.conditions[?(@.status=="False")].message}' 2>/dev/null || echo "No message")

                # Get container statuses
                local container_states=$(kubectl get pod "$pod_name" -n "$app_namespace" -o jsonpath='{range .status.containerStatuses[*]}{.name}{"|"}{.state}{"\n"}{end}' 2>/dev/null)

                if [ -n "$container_states" ]; then
                    echo -e "${CYAN}    Container States:${NC}"
                    while IFS='|' read -r container_name container_state; do
                        if [ -n "$container_name" ]; then
                            # Parse the state JSON
                            local state_reason=$(echo "$container_state" | jq -r '.waiting.reason // .terminated.reason // "running"' 2>/dev/null || echo "unknown")
                            local state_message=$(echo "$container_state" | jq -r '.waiting.message // .terminated.message // ""' 2>/dev/null || echo "")

                            if [ "$state_reason" != "running" ] && [ "$state_reason" != "null" ]; then
                                echo -e "${RED}      - ${container_name}: ${state_reason}${NC}"
                                if [ -n "$state_message" ] && [ "$state_message" != "null" ]; then
                                    echo -e "${RED}        Message: ${state_message}${NC}"
                                fi
                            fi
                        fi
                    done <<< "$container_states"
                fi

                # Get recent events for the pod
                local recent_events=$(kubectl get events -n "$app_namespace" --field-selector involvedObject.name="$pod_name" --sort-by='.lastTimestamp' 2>/dev/null | tail -3 || echo "")
                if [ -n "$recent_events" ]; then
                    echo -e "${CYAN}    Recent Events:${NC}"
                    echo "$recent_events" | tail -n +2 | while read -r event_line; do
                        local event_reason=$(echo "$event_line" | awk '{print $4}')
                        local event_message=$(echo "$event_line" | cut -d' ' -f5-)
                        if [ -n "$event_reason" ]; then
                            echo -e "${YELLOW}      - ${event_reason}: ${event_message}${NC}"
                        fi
                    done
                fi

                # Get recent error logs from failing containers
                echo -e "${CYAN}    Recent Container Logs (last 20 lines with errors):${NC}"
                local has_logs=false

                # Try current pod logs
                local current_logs=$(kubectl logs "$pod_name" -n "$app_namespace" --all-containers=true --tail=20 2>/dev/null | grep -iE "error|fatal|panic|exception|failed" || echo "")
                if [ -n "$current_logs" ]; then
                    has_logs=true
                    echo -e "${RED}      [Current]${NC}"
                    echo "$current_logs" | while IFS= read -r log_line; do
                        echo -e "${RED}        $log_line${NC}"
                    done
                fi

                # Try previous pod logs (for CrashLoopBackOff)
                local previous_logs=$(kubectl logs "$pod_name" -n "$app_namespace" --all-containers=true --previous --tail=20 2>/dev/null | grep -iE "error|fatal|panic|exception|failed" || echo "")
                if [ -n "$previous_logs" ]; then
                    has_logs=true
                    echo -e "${RED}      [Previous - before crash]${NC}"
                    echo "$previous_logs" | while IFS= read -r log_line; do
                        echo -e "${RED}        $log_line${NC}"
                    done
                fi

                if [ "$has_logs" = false ]; then
                    echo -e "${YELLOW}      (no error logs found in last 20 lines)${NC}"
                fi

                echo ""
            done <<< "$failing_pods"
        else
            echo -e "${CYAN}  Namespace: ${app_namespace} (no failing pods found - may be resource issue)${NC}"
            echo ""
        fi

        echo "────────────────────────────────────────────────────"
        echo ""
    done

    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
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

    # Disk usage - use docker system df (works on Linux and macOS)
    if command -v docker &> /dev/null; then
        # Get Docker disk usage
        DOCKER_DISK=$(docker system df 2>/dev/null | grep "Images\|Containers\|Volumes\|Build" | awk '{sum+=$4} END {printf "%.1fGB", sum}')

        # Get total disk (Linux: /var/lib/docker, macOS: root filesystem)
        if [ -d /var/lib/docker ]; then
            # Linux (CI)
            DISK_TOTAL=$(df -BG /var/lib/docker 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G/GB/')
            DISK_AVAIL=$(df -BG /var/lib/docker 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G/GB/')
            DISK_PCT=$(df -BG /var/lib/docker 2>/dev/null | tail -1 | awk '{print $5}')
        else
            # macOS (local dev)
            DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')
            DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
            DISK_PCT=$(df -h / | tail -1 | awk '{print $5}')
        fi

        printf "Disk: %s total, %s Docker, %s avail (%s used)\n" "$DISK_TOTAL" "$DOCKER_DISK" "$DISK_AVAIL" "$DISK_PCT"
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

    # Get all applications (with timeout)
    KUBECTL_OUTPUT_FILE=$(mktemp)
    (kubectl get applications -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null > "$KUBECTL_OUTPUT_FILE") &
    KUBECTL_PID=$!

    # Wait for kubectl with timeout
    KUBECTL_COUNT=0
    while kill -0 $KUBECTL_PID 2>/dev/null; do
        if [ $KUBECTL_COUNT -ge $KUBECTL_TIMEOUT ]; then
            kill -9 $KUBECTL_PID 2>/dev/null
            rm -f "$KUBECTL_OUTPUT_FILE"
            echo -e "${RED}ERROR: kubectl get applications timed out after ${KUBECTL_TIMEOUT}s${NC}"
            echo -e "${RED}ArgoCD may be unresponsive. Waiting ${POLL_INTERVAL}s before retry...${NC}"
            sleep $POLL_INTERVAL
            continue
        fi
        sleep 1
        KUBECTL_COUNT=$((KUBECTL_COUNT + 1))
    done

    # Read result
    ALL_APPS=$(cat "$KUBECTL_OUTPUT_FILE" 2>/dev/null)
    rm -f "$KUBECTL_OUTPUT_FILE"

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
        # Don't clear screen, just print separator
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

        # Print degraded pod details if any
        print_degraded_pod_details "$DEGRADED_APPS"

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
    else
        # Status unchanged - print heartbeat every 30 seconds
        if [ $((ELAPSED % 30)) -eq 0 ] && [ "$ELAPSED" -gt 0 ]; then
            TIMESTAMP=$(date "+%H:%M:%S")
            echo ""
            echo -e "${CYAN}[$TIMESTAMP] Heartbeat: Monitoring... (${ELAPSED}s elapsed, status unchanged)${NC}"
            echo -e "${CYAN}  Apps: ${HEALTHY_APPS}/${TOTAL_APPS} Healthy | Synced: ${SYNCED_APPS}/${TOTAL_APPS}${NC}"
        fi
    fi

    # Check for failure conditions with grace period
    # Track when CRITICAL apps first became Degraded, only fail after grace period
    CRITICAL_DEGRADED_APPS=$(echo "$ALL_APPS" | jq -r '[.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing") | .metadata.name] | .[]')

    CURRENT_TIME=$(date +%s)

    if [ -n "$CRITICAL_DEGRADED_APPS" ]; then
        for degraded_app in $CRITICAL_DEGRADED_APPS; do
            if is_critical_app "$degraded_app"; then
                TRACKING_FILE="$DEGRADED_TRACKING_DIR/$degraded_app"

                # Track when this app first became degraded (file-based)
                if [ ! -f "$TRACKING_FILE" ]; then
                    echo "$CURRENT_TIME" > "$TRACKING_FILE"
                    echo ""
                    echo -e "${YELLOW}⚠️  CRITICAL app '$degraded_app' is Degraded (grace period: ${DEGRADED_GRACE_PERIOD}s)${NC}"
                fi

                # Calculate how long it's been degraded
                DEGRADED_START=$(cat "$TRACKING_FILE")
                DEGRADED_DURATION=$((CURRENT_TIME - DEGRADED_START))

                # Only fail if degraded beyond grace period
                if [ $DEGRADED_DURATION -ge $DEGRADED_GRACE_PERIOD ]; then
                    echo ""
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "${RED}❌ CRITICAL FAILURE: Platform deployment failed${NC}"
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo ""
                    echo -e "${RED}Reason: CRITICAL app '$degraded_app' has been ${RED}Degraded/Missing${NC} for ${DEGRADED_DURATION}s${NC}"
                    echo -e "${RED}Grace period: ${DEGRADED_GRACE_PERIOD}s (exceeded by $((DEGRADED_DURATION - DEGRADED_GRACE_PERIOD))s)${NC}"
                    echo -e "${RED}This indicates a persistent failure, not just initialization${NC}"
                    echo ""

                    # Show all degraded/missing apps before exit
                    echo -e "${YELLOW}Degraded/Missing Applications Summary:${NC}"
                    ALL_DEGRADED=$(echo "$ALL_APPS" | jq -r '[.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing") | "\(.metadata.name): \(.status.health.status)"] | .[]')
                    echo "$ALL_DEGRADED" | while read -r app_status; do
                        echo -e "${RED}  ❌ $app_status${NC}"
                    done
                    echo ""

                    # Call existing function to show detailed pod failure information
                    print_degraded_pod_details "$DEGRADED_APPS"

                    echo ""
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "${RED}FAILURE: Platform did not become healthy within grace period${NC}"
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo ""
                    echo -e "${CYAN}[EXIT POINT 1] Exiting with code 1${NC}"
                    echo -e "${CYAN}Reason: Critical app '$degraded_app' degraded for ${DEGRADED_DURATION}s (grace period: ${DEGRADED_GRACE_PERIOD}s)${NC}"
                    echo -e "${CYAN}Elapsed time: ${ELAPSED}s / Timeout: ${MONITOR_TIMEOUT}s${NC}"
                    echo ""
                    exit 1
                fi
            fi
        done
    fi

    # Clear tracking for apps that recovered
    for tracking_file in "$DEGRADED_TRACKING_DIR"/*; do
        [ -f "$tracking_file" ] || continue
        app_name=$(basename "$tracking_file")

        APP_HEALTH=$(echo "$ALL_APPS" | jq -r --arg app "$app_name" '[.items[] | select(.metadata.name == $app) | .status.health.status] | .[0] // "Missing"')
        if [ "$APP_HEALTH" != "Degraded" ] && [ "$APP_HEALTH" != "Missing" ]; then
            DEGRADED_START=$(cat "$tracking_file")
            RECOVERY_TIME=$((CURRENT_TIME - DEGRADED_START))
            echo -e "${GREEN}✓ App '$app_name' recovered after ${RECOVERY_TIME}s${NC}"
            rm -f "$tracking_file"
        fi
    done

    # Success: All CRITICAL apps healthy (allow optional apps to be progressing, sync status not required)
    if [ $CRITICAL_TOTAL -gt 0 ] && [ "$CRITICAL_HEALTHY" -eq "$CRITICAL_TOTAL" ]; then
        echo ""
        echo -e "${GREEN}✅ All CRITICAL applications are healthy!${NC}"
        echo "Total time: ${ELAPSED}s ($(($ELAPSED / 60))m)"
        echo ""
        echo -e "${CYAN}[EXIT POINT 2a] Exiting with code 0 (SUCCESS - CRITICAL APPS HEALTHY)${NC}"
        echo -e "${CYAN}Reason: All ${CRITICAL_TOTAL} CRITICAL apps are Healthy${NC}"
        echo -e "${CYAN}Optional apps: ${OPTIONAL_HEALTHY}/${OPTIONAL_TOTAL} Healthy (may still be Progressing)${NC}"
        echo -e "${CYAN}Note: Some apps may be OutOfSync but that's OK for local development${NC}"
        echo -e "${CYAN}Elapsed time: ${ELAPSED}s / Timeout: ${MONITOR_TIMEOUT}s${NC}"
        echo ""
        exit 0
    fi

    # Success: All apps healthy and synced
    if [ "$TOTAL_APPS" -gt 0 ] && [ "$HEALTHY_APPS" -eq "$TOTAL_APPS" ] && [ "$SYNCED_APPS" -eq "$TOTAL_APPS" ]; then
        echo ""
        echo -e "${GREEN}✅ All applications are healthy and synced!${NC}"
        echo "Total time: ${ELAPSED}s ($(($ELAPSED / 60))m)"
        echo ""
        echo -e "${CYAN}[EXIT POINT 2] Exiting with code 0 (SUCCESS - ALL APPS HEALTHY)${NC}"
        echo -e "${CYAN}Reason: All ${TOTAL_APPS} apps are Healthy and Synced${NC}"
        echo -e "${CYAN}Elapsed time: ${ELAPSED}s / Timeout: ${MONITOR_TIMEOUT}s${NC}"
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

# Final status check (with timeout)
FINAL_APPS_FILE=$(mktemp)
(kubectl get applications -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null > "$FINAL_APPS_FILE") &
FINAL_KUBECTL_PID=$!

# Wait with timeout
FINAL_COUNT=0
while kill -0 $FINAL_KUBECTL_PID 2>/dev/null; do
    if [ $FINAL_COUNT -ge $KUBECTL_TIMEOUT ]; then
        kill -9 $FINAL_KUBECTL_PID 2>/dev/null
        echo -e "${RED}WARNING: Final kubectl check timed out - using last known status${NC}"
        echo "$ALL_APPS" > "$FINAL_APPS_FILE"  # Use last successful result
        break
    fi
    sleep 1
    FINAL_COUNT=$((FINAL_COUNT + 1))
done

FINAL_APPS=$(cat "$FINAL_APPS_FILE" 2>/dev/null)
rm -f "$FINAL_APPS_FILE"

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
    echo -e "${CYAN}[EXIT POINT 3] Exiting with code 1${NC}"
    echo -e "${CYAN}Reason: TIMEOUT reached (${MONITOR_TIMEOUT}s) with critical apps unhealthy${NC}"
    echo -e "${CYAN}Final status: ${FINAL_HEALTHY}/${FINAL_TOTAL} healthy, ${FINAL_SYNCED}/${FINAL_TOTAL} synced${NC}"
    echo ""
    exit 1
fi

# Check if ALL apps are Degraded (total failure)
if [ "$FINAL_HEALTHY" -eq 0 ] && [ "$FINAL_TOTAL" -gt 0 ]; then
    echo -e "${RED}❌ No healthy applications found${NC}"
    echo ""
    echo -e "${CYAN}[EXIT POINT 4] Exiting with code 1${NC}"
    echo -e "${CYAN}Reason: TIMEOUT reached (${MONITOR_TIMEOUT}s) with ZERO healthy apps${NC}"
    echo -e "${CYAN}Final status: 0/${FINAL_TOTAL} healthy${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ All critical applications are healthy${NC}"
echo -e "${YELLOW}⚠️  Some optional applications may still be progressing (observability, Kiali, Ollama)${NC}"
echo ""
echo -e "${CYAN}[EXIT POINT 5] Exiting with code 0 (SUCCESS - TIMEOUT WITH CRITICAL APPS HEALTHY)${NC}"
echo -e "${CYAN}Reason: TIMEOUT reached (${MONITOR_TIMEOUT}s) but all critical apps are healthy${NC}"
echo -e "${CYAN}Final status: ${FINAL_HEALTHY}/${FINAL_TOTAL} healthy (critical apps: OK, optional apps: may be progressing)${NC}"
echo ""

exit 0
