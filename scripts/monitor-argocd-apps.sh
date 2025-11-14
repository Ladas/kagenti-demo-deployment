#!/usr/bin/env bash
# Monitor ArgoCD Application Sync Status with Sync Wave Visibility
# Monitors all ArgoCD applications for health and sync status, grouped by sync waves
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

echo ""
echo -e "${BLUE}Monitoring ArgoCD Applications (Sync Wave View)...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Timeout: ${MONITOR_TIMEOUT}s ($(($MONITOR_TIMEOUT / 60)) minutes)"
echo ""

# Function to get sync wave for an application
get_sync_wave() {
    local app_name="$1"
    # Remove namespace prefix if present (e.g., "argocd/cert-manager" -> "cert-manager")
    local app_short_name=$(echo "$app_name" | sed 's|^argocd/||')

    local wave=$(kubectl get application -n "$ARGOCD_NAMESPACE" "$app_short_name" \
        -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}' 2>/dev/null || echo "0")

    # Default to 0 if not found or empty
    if [ -z "$wave" ]; then
        wave="0"
    fi
    echo "$wave"
}

# Function to display wave status
display_wave_status() {
    local wave_number="$1"
    local wave_data_file="$2"

    if [ ! -f "$wave_data_file" ] || [ ! -s "$wave_data_file" ]; then
        return
    fi

    local wave_total=$(wc -l < "$wave_data_file" | tr -d ' \n')
    local wave_healthy=$(awk '{print $6}' "$wave_data_file" | grep -c "Healthy" 2>/dev/null)
    wave_healthy=$(echo "$wave_healthy" | tr -d ' \n')
    local wave_synced=$(awk '{print $5}' "$wave_data_file" | grep -c "Synced" 2>/dev/null)
    wave_synced=$(echo "$wave_synced" | tr -d ' \n')
    local wave_degraded=$(awk '{print $6}' "$wave_data_file" | grep -Ec "Degraded|Missing" 2>/dev/null)
    wave_degraded=$(echo "$wave_degraded" | tr -d ' \n')
    local wave_progressing=$(awk '{print $6}' "$wave_data_file" | grep -c "Progressing" 2>/dev/null)
    wave_progressing=$(echo "$wave_progressing" | tr -d ' \n')
    local wave_outofsync=$(awk '{print $5}' "$wave_data_file" | grep -Ec "OutOfSync|Unknown" 2>/dev/null)
    wave_outofsync=$(echo "$wave_outofsync" | tr -d ' \n')

    # Determine wave status
    local wave_icon=""
    local wave_color=""
    local wave_status=""

    if [ "$wave_degraded" -gt 0 ]; then
        wave_icon="✗"
        wave_color=$RED
        wave_status="DEGRADED"
    elif [ "$wave_healthy" -eq "$wave_total" ] && [ "$wave_synced" -eq "$wave_total" ]; then
        wave_icon="✓"
        wave_color=$GREEN
        wave_status="COMPLETE"
    elif [ "$wave_progressing" -gt 0 ] || [ "$wave_outofsync" -gt 0 ]; then
        wave_icon="⏳"
        wave_color=$YELLOW
        wave_status="IN PROGRESS"
    else
        wave_icon="○"
        wave_color=$CYAN
        wave_status="WAITING"
    fi

    printf "  ${wave_color}${wave_icon} Wave %-3s ${wave_status}${NC} " "$wave_number"
    printf "(${wave_healthy}/${wave_total} Healthy, ${wave_synced}/${wave_total} Synced)\n"

    # Show apps in this wave if degraded, progressing, or out of sync
    if [ "$wave_degraded" -gt 0 ] || [ "$wave_progressing" -gt 0 ] || [ "$wave_outofsync" -gt 0 ]; then
        while read -r line; do
            local app=$(echo "$line" | awk '{print $1}')
            local sync=$(echo "$line" | awk '{print $5}')
            local health=$(echo "$line" | awk '{print $6}')

            # Determine app icon and color
            local app_icon=""
            local app_color=$NC
            case "$health" in
                Healthy)
                    app_icon="✓"
                    app_color=$GREEN
                    ;;
                Progressing)
                    app_icon="⏳"
                    app_color=$YELLOW
                    ;;
                Degraded|Missing)
                    app_icon="✗"
                    app_color=$RED
                    ;;
                *)
                    app_icon="○"
                    app_color=$CYAN
                    ;;
            esac

            printf "      ${app_color}${app_icon} %-30s %-12s %-12s${NC}\n" "$app" "$sync" "$health"
        done < "$wave_data_file"
    fi
}

# Monitor application sync status
MONITOR_START=$(date +%s)
LAST_WAVE_STATUS=""

# Create temp directory for wave data
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

while [ $(($(date +%s) - MONITOR_START)) -lt $MONITOR_TIMEOUT ]; do
    # Get application list with health and sync status
    APP_STATUS=$(argocd app list --port-forward --port-forward-namespace "$ARGOCD_NAMESPACE" --grpc-web 2>/dev/null | tail -n +2 || echo "")

    if [ -z "$APP_STATUS" ]; then
        echo "Waiting for applications to appear..."
        sleep 5
        continue
    fi

    # Clear temp directory
    rm -f "$TEMP_DIR"/wave_*.txt

    # Build wave files and map
    while read -r app_line; do
        app_name=$(echo "$app_line" | awk '{print $1}')
        wave=$(get_sync_wave "$app_name")

        # Save app data to wave-specific file
        echo "$app_line" >> "$TEMP_DIR/wave_${wave}.txt"
    done < <(echo "$APP_STATUS")

    # Count overall stats
    TOTAL_APPS=$(echo "$APP_STATUS" | wc -l | tr -d ' ')
    HEALTHY_APPS=$(echo "$APP_STATUS" | awk '{print $6}' | grep -c "Healthy" 2>/dev/null || echo "0")
    SYNCED_APPS=$(echo "$APP_STATUS" | awk '{print $5}' | grep -c "Synced" 2>/dev/null || echo "0")
    PROGRESSING_APPS=$(echo "$APP_STATUS" | awk '{print $6}' | grep -c "Progressing" 2>/dev/null || echo "0")
    DEGRADED_APPS=$(echo "$APP_STATUS" | awk '{print $6}' | grep -Ec "Degraded|Missing" 2>/dev/null || echo "0")

    # Create status summary with wave counts
    WAVE_COUNT=$(ls -1 "$TEMP_DIR"/wave_*.txt 2>/dev/null | wc -l | tr -d ' ')
    CURRENT_STATUS="Apps: $TOTAL_APPS | Waves: $WAVE_COUNT | Healthy: $HEALTHY_APPS | Synced: $SYNCED_APPS | Progressing: $PROGRESSING_APPS | Degraded: $DEGRADED_APPS"

    # Only print if status changed
    if [ "$CURRENT_STATUS" != "$LAST_WAVE_STATUS" ]; then
        clear
        echo ""
        echo -e "${BLUE}Monitoring ArgoCD Applications (Sync Wave View)...${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        TIMESTAMP=$(date "+%H:%M:%S")
        ELAPSED=$(($(date +%s) - MONITOR_START))

        if [ "$DEGRADED_APPS" -gt 0 ]; then
            echo -e "[$TIMESTAMP] ${RED}$CURRENT_STATUS${NC} (elapsed: ${ELAPSED}s)"
        elif [ "$PROGRESSING_APPS" -gt 0 ]; then
            echo -e "[$TIMESTAMP] ${YELLOW}$CURRENT_STATUS${NC} (elapsed: ${ELAPSED}s)"
        else
            echo -e "[$TIMESTAMP] ${GREEN}$CURRENT_STATUS${NC} (elapsed: ${ELAPSED}s)"
        fi

        echo ""
        echo -e "${CYAN}Sync Wave Status:${NC}"
        echo ""

        # Display waves in numerical order
        # First, collect all wave numbers
        wave_numbers=$(ls -1 "$TEMP_DIR"/wave_*.txt 2>/dev/null | sed 's|.*/wave_||' | sed 's|\.txt||' | sort -n)

        # Display each wave in sorted order
        for wave_number in $wave_numbers; do
            wave_file="$TEMP_DIR/wave_${wave_number}.txt"
            if [ -f "$wave_file" ]; then
                display_wave_status "$wave_number" "$wave_file"
            fi
        done

        LAST_WAVE_STATUS="$CURRENT_STATUS"
    fi

    # Check if all apps are healthy and synced
    if [ "$HEALTHY_APPS" -eq "$TOTAL_APPS" ] && [ "$SYNCED_APPS" -eq "$TOTAL_APPS" ]; then
        echo ""
        echo -e "${GREEN}✓ All applications are healthy and synced!${NC}"
        break
    fi

    sleep 5
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Final status
ELAPSED=$(($(date +%s) - MONITOR_START))
echo ""
echo -e "${BLUE}Final ArgoCD Applications Status (after ${ELAPSED}s):${NC}"
argocd app list --port-forward --port-forward-namespace "$ARGOCD_NAMESPACE" --grpc-web 2>/dev/null || true
echo ""

# Exit with error if any apps are degraded
if [ "$DEGRADED_APPS" -gt 0 ]; then
    echo -e "${RED}⚠ $DEGRADED_APPS applications are degraded or missing${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All ArgoCD applications are healthy${NC}"
echo ""
