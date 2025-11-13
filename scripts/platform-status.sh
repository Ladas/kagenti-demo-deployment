#!/usr/bin/env bash
# Platform Health Check Script
# Provides quick status of ArgoCD apps and platform pods
# Usage: ./scripts/platform-status.sh

set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
USE_PORT_FORWARD="${USE_PORT_FORWARD:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Kagenti Platform Health Check"
echo "=========================================="
echo ""

# Function to check if ArgoCD is running
check_argocd() {
    echo -e "${BLUE}Checking ArgoCD Status...${NC}"
    if kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" &>/dev/null; then
        local ready=$(kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.spec.replicas}')
        if [ "$ready" == "$desired" ]; then
            echo -e "${GREEN}✓ ArgoCD Server: Running ($ready/$desired)${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ ArgoCD Server: Not Ready ($ready/$desired)${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ ArgoCD Server: Not Found${NC}"
        return 1
    fi
}

# Function to get ArgoCD app status
get_argocd_apps() {
    echo ""
    echo -e "${BLUE}ArgoCD Application Status:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local argocd_cmd="argocd app list"
    if [ "$USE_PORT_FORWARD" == "true" ]; then
        argocd_cmd="$argocd_cmd --port-forward --port-forward-namespace ${ARGOCD_NAMESPACE} --grpc-web"
    fi

    # Get app list
    local app_list=$($argocd_cmd 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$app_list" ]; then
        echo -e "${YELLOW}⚠ Could not fetch ArgoCD apps (is ArgoCD running?)${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return 1
    fi

    # Counters for summary
    local total_apps=0
    local healthy_apps=0
    local degraded_apps=0
    local progressing_apps=0
    local synced_apps=0
    local outof_sync_apps=0

    # Process and display apps
    echo "$app_list" | tail -n +2 | while read -r line; do
        local app=$(echo "$line" | awk '{print $1}')
        local sync=$(echo "$line" | awk '{print $5}')
        local health=$(echo "$line" | awk '{print $6}')

        # Color code health status
        local health_color=$NC
        local health_icon=""
        case "$health" in
            Healthy)
                health_color=$GREEN
                health_icon="✓"
                ;;
            Progressing)
                health_color=$YELLOW
                health_icon="⏳"
                ;;
            Degraded)
                health_color=$RED
                health_icon="✗"
                ;;
            Missing)
                health_color=$RED
                health_icon="❌"
                ;;
            Unknown)
                health_color=$YELLOW
                health_icon="?"
                ;;
            *)
                health_color=$NC
                health_icon="-"
                ;;
        esac

        # Color code sync status
        local sync_color=$NC
        case "$sync" in
            Synced)
                sync_color=$GREEN
                ;;
            OutOfSync)
                sync_color=$YELLOW
                ;;
        esac

        printf "${health_color}${health_icon}${NC} %-28s ${sync_color}%-12s${NC} ${health_color}%-12s${NC}\n" "$app" "$sync" "$health"
    done

    # Calculate summary from app_list
    total_apps=$(echo "$app_list" | tail -n +2 | wc -l | tr -d ' \n')
    healthy_apps=$(echo "$app_list" | tail -n +2 | awk '{print $6}' | grep -c "Healthy" 2>/dev/null || echo "0")
    healthy_apps=$(echo "$healthy_apps" | tr -d ' \n')
    progressing_apps=$(echo "$app_list" | tail -n +2 | awk '{print $6}' | grep -c "Progressing" 2>/dev/null || echo "0")
    progressing_apps=$(echo "$progressing_apps" | tr -d ' \n')
    degraded_apps=$(echo "$app_list" | tail -n +2 | awk '{print $6}' | grep -Ec "Degraded|Missing" 2>/dev/null || echo "0")
    degraded_apps=$(echo "$degraded_apps" | tr -d ' \n')
    synced_apps=$(echo "$app_list" | tail -n +2 | awk '{print $5}' | grep -c "Synced" 2>/dev/null || echo "0")
    synced_apps=$(echo "$synced_apps" | tr -d ' \n')
    outof_sync_apps=$(echo "$app_list" | tail -n +2 | awk '{print $5}' | grep -c "OutOfSync" 2>/dev/null || echo "0")
    outof_sync_apps=$(echo "$outof_sync_apps" | tr -d ' \n')

    # Summary
    echo ""
    echo "Summary:"
    printf "  Total: %d apps" "$total_apps"
    [ "$healthy_apps" -gt 0 ] && printf " | ${GREEN}✓ %d Healthy${NC}" "$healthy_apps"
    [ "$progressing_apps" -gt 0 ] && printf " | ${YELLOW}⏳ %d Progressing${NC}" "$progressing_apps"
    [ "$degraded_apps" -gt 0 ] && printf " | ${RED}✗ %d Degraded/Missing${NC}" "$degraded_apps"
    echo ""
    printf "  Sync: "
    [ "$synced_apps" -gt 0 ] && printf "${GREEN}%d Synced${NC}" "$synced_apps"
    [ "$outof_sync_apps" -gt 0 ] && printf " | ${YELLOW}%d OutOfSync${NC}" "$outof_sync_apps"
    echo ""

    # Show problematic apps if any
    if [ "$degraded_apps" -gt 0 ]; then
        echo ""
        echo -e "${RED}⚠ Problematic Applications - Need Investigation:${NC}"
        echo "$app_list" | tail -n +2 | while read -r line; do
            local app=$(echo "$line" | awk '{print $1}')
            local health=$(echo "$line" | awk '{print $6}')
            if [[ "$health" == "Degraded" || "$health" == "Missing" ]]; then
                echo "  → $app (Health: $health)"
                echo "    Check with: argocd app get $app --port-forward --port-forward-namespace argocd --grpc-web"
            fi
        done
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to check pod status by namespace
check_pods() {
    echo ""
    echo -e "${BLUE}Platform Pods Status:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local namespaces=(
        "argocd:ArgoCD"
        "istio-system:Istio Service Mesh"
        "cert-manager:Certificate Manager"
        "tekton-pipelines:Tekton Pipelines"
        "keycloak:Keycloak IAM"
        "kagenti-system:Kagenti Platform"
        "observability:Observability Stack"
        "kiali-system:Kiali Service Mesh UI"
        "default:Gateway"
        "team1:Team1 Agents"
    )

    for ns_entry in "${namespaces[@]}"; do
        local ns=$(echo "$ns_entry" | cut -d: -f1)
        local label=$(echo "$ns_entry" | cut -d: -f2)

        if kubectl get namespace "$ns" &>/dev/null; then
            local total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')

            # Count truly healthy pods (all containers ready, not waiting)
            local healthy=0
            local failed=0
            local waiting=0

            while IFS= read -r pod_line; do
                local pod_name=$(echo "$pod_line" | awk '{print $1}')
                local ready=$(echo "$pod_line" | awk '{print $2}')
                local status=$(echo "$pod_line" | awk '{print $3}')

                # Check if all containers are ready
                local ready_containers=$(echo "$ready" | cut -d'/' -f1)
                local total_containers=$(echo "$ready" | cut -d'/' -f2)

                if [ "$ready_containers" -eq "$total_containers" ] && [[ "$status" == "Running" || "$status" == "Succeeded" ]]; then
                    healthy=$((healthy + 1))
                elif [[ "$status" == "Failed" || "$status" == "Error" ]]; then
                    failed=$((failed + 1))
                elif [[ "$status" == *"Back"* || "$status" == *"Error"* || "$status" == "Pending" ]]; then
                    waiting=$((waiting + 1))
                fi
            done < <(kubectl get pods -n "$ns" --no-headers 2>/dev/null)

            if [ "$total" -eq 0 ]; then
                printf "%-30s ${YELLOW}No pods${NC}\n" "$label"
            elif [ "$healthy" -eq "$total" ]; then
                printf "%-30s ${GREEN}✓ %d/%d Running${NC}\n" "$label" "$healthy" "$total"
            else
                printf "%-30s ${YELLOW}⚠ %d/%d Running${NC}" "$label" "$healthy" "$total"
                [ "$failed" -gt 0 ] && printf " ${RED}(%d Failed)${NC}" "$failed"
                [ "$waiting" -gt 0 ] && printf " ${YELLOW}(%d Waiting)${NC}" "$waiting"
                echo ""
            fi
        fi
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to check problematic pods
check_problem_pods() {
    echo ""
    echo -e "${BLUE}Problematic Pods:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local problem_pods=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null)

    if [ -z "$problem_pods" ]; then
        echo -e "${GREEN}✓ No problematic pods found${NC}"
    else
        echo "$problem_pods" | while read -r line; do
            local ns=$(echo "$line" | awk '{print $1}')
            local pod=$(echo "$line" | awk '{print $2}')
            local status=$(echo "$line" | awk '{print $4}')
            printf "${RED}✗${NC} %-20s %-40s ${YELLOW}%s${NC}\n" "$ns" "$pod" "$status"
        done
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to check gateway status
check_gateway() {
    echo ""
    echo -e "${BLUE}Gateway Status:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if kubectl get gateway external-gateway -n default &>/dev/null; then
        local programmed=$(kubectl get gateway external-gateway -n default -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')
        local address=$(kubectl get gateway external-gateway -n default -o jsonpath='{.status.addresses[0].value}')

        if [ "$programmed" == "True" ]; then
            echo -e "${GREEN}✓ Gateway: Programmed${NC}"
            echo "  Address: $address"
        else
            echo -e "${YELLOW}⚠ Gateway: Not Programmed${NC}"
        fi

        # Check gateway services
        echo ""
        echo "Gateway Services:"
        kubectl get svc -n default | grep gateway | while read -r line; do
            local svc=$(echo "$line" | awk '{print $1}')
            local type=$(echo "$line" | awk '{print $2}')
            local ports=$(echo "$line" | awk '{print $5}')
            printf "  %-30s %-12s %s\n" "$svc" "$type" "$ports"
        done

        # Check HTTPRoutes
        echo ""
        local route_count=$(kubectl get httproute -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        echo "HTTPRoutes: $route_count configured"
    else
        echo -e "${RED}✗ Gateway: Not Found${NC}"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to check certificates
check_certificates() {
    echo ""
    echo -e "${BLUE}TLS Certificates:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local certs=$(kubectl get certificate -A --no-headers 2>/dev/null)
    if [ -z "$certs" ]; then
        echo -e "${YELLOW}⚠ No certificates found${NC}"
    else
        local total=$(echo "$certs" | wc -l | tr -d ' ')
        local ready=$(echo "$certs" | grep -c "True" || echo "0")

        if [ "$ready" -eq "$total" ]; then
            echo -e "${GREEN}✓ Certificates: $ready/$total Ready${NC}"
        else
            echo -e "${YELLOW}⚠ Certificates: $ready/$total Ready${NC}"
        fi

        # Show certificate details
        echo "$certs" | while read -r line; do
            local ns=$(echo "$line" | awk '{print $1}')
            local name=$(echo "$line" | awk '{print $2}')
            local ready=$(echo "$line" | awk '{print $3}')

            local status_icon
            local status_color
            if [ "$ready" == "True" ]; then
                status_icon="✓"
                status_color=$GREEN
            else
                status_icon="✗"
                status_color=$RED
            fi

            printf "  ${status_color}${status_icon}${NC} %-20s %s\n" "$ns" "$name"
        done
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to check mTLS status
check_mtls() {
    echo ""
    echo -e "${BLUE}Istio mTLS Status:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check global mTLS policy
    if kubectl get peerauthentication -n istio-system default-strict-mtls &>/dev/null; then
        local mode=$(kubectl get peerauthentication -n istio-system default-strict-mtls -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
        if [ "$mode" == "STRICT" ]; then
            echo -e "${GREEN}✓ Global mTLS: STRICT${NC}"
        else
            echo -e "${YELLOW}⚠ Global mTLS: $mode${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Global mTLS policy not found${NC}"
    fi

    # Check namespace-specific policies
    local ns_with_mtls=$(kubectl get peerauthentication -A --no-headers 2>/dev/null | grep -v "istio-system" | wc -l | tr -d ' ')
    if [ "$ns_with_mtls" -gt 0 ]; then
        echo "Namespace mTLS policies: $ns_with_mtls configured"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to test service accessibility with Keycloak authentication
check_service_accessibility() {
    echo ""
    echo -e "${BLUE}Service Accessibility (via Gateway):${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check if gateway is ready first
    if ! kubectl get gateway external-gateway -n default &>/dev/null; then
        echo -e "${YELLOW}⚠ Gateway not found - skipping accessibility tests${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    local programmed=$(kubectl get gateway external-gateway -n default -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
    if [ "$programmed" != "True" ]; then
        echo -e "${YELLOW}⚠ Gateway not programmed - services not yet accessible${NC}"
        echo "  Wait for Gateway to become ready, then re-run this check"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    # Test services without authentication (public endpoints)
    local services=(
        "keycloak:9443"
        "kagenti:9443"
        "grafana:9443"
        "kiali:9443"
        "phoenix:9443"
        "tempo:9443"
    )

    echo "Testing service endpoints (HTTPS):"
    echo ""

    for service_entry in "${services[@]}"; do
        local service=$(echo "$service_entry" | cut -d: -f1)
        local port=$(echo "$service_entry" | cut -d: -f2)
        local url="https://${service}.localtest.me:${port}"

        # Test with curl (follow redirects, check SSL, timeout 5s)
        local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
        local curl_exit=$?

        local status_icon
        local status_color
        local status_msg

        if [ $curl_exit -ne 0 ]; then
            status_icon="✗"
            status_color=$RED
            status_msg="Connection Failed"
        else
            case "$http_code" in
                200|201|202|204)
                    status_icon="✓"
                    status_color=$GREEN
                    status_msg="HTTP $http_code - OK"
                    ;;
                301|302|303|307|308)
                    status_icon="↻"
                    status_color=$YELLOW
                    status_msg="HTTP $http_code - Redirect"
                    ;;
                401|403)
                    status_icon="🔒"
                    status_color=$YELLOW
                    status_msg="HTTP $http_code - Auth Required (Expected)"
                    ;;
                404)
                    status_icon="✗"
                    status_color=$RED
                    status_msg="HTTP $http_code - Not Found"
                    ;;
                500|502|503|504)
                    status_icon="✗"
                    status_color=$RED
                    status_msg="HTTP $http_code - Server Error"
                    ;;
                *)
                    status_icon="?"
                    status_color=$YELLOW
                    status_msg="HTTP $http_code"
                    ;;
            esac
        fi

        printf "  ${status_color}${status_icon}${NC} %-20s ${status_color}%s${NC}\n" "$service" "$status_msg"
    done

    echo ""
    echo "Legend:"
    echo "  ✓ = Service accessible"
    echo "  🔒 = Auth required (normal for OAuth2-protected services)"
    echo "  ↻ = Redirect (check HTTPRoute configuration)"
    echo "  ✗ = Service unavailable or error"
    echo ""
    echo "Note: Many services redirect to Keycloak for login (401/403 is expected)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to test OAuth authentication and API access
check_oauth_authentication() {
    echo ""
    echo -e "${BLUE}OAuth Authentication & API Access:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check if Keycloak is accessible
    local keycloak_ready=$(kubectl get pod -n keycloak -l app=keycloak --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$keycloak_ready" -eq 0 ]; then
        echo -e "${YELLOW}⚠ Keycloak not ready - skipping OAuth tests${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    echo "Testing OAuth token acquisition and API access:"
    echo ""

    # Test Keycloak Admin API (master realm)
    echo -e "${BLUE}[1/2] Testing Keycloak Admin API (master realm)${NC}"

    # Use kubectl port-forward or direct API access via gateway
    local KEYCLOAK_URL="https://keycloak.localtest.me:9443"
    local ADMIN_USER="admin"
    local ADMIN_PASS="admin123"

    # Get admin token
    local TOKEN=$(curl -k -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=${ADMIN_USER}" \
      -d "password=${ADMIN_PASS}" \
      -d "grant_type=password" \
      -d "client_id=admin-cli" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

    if [ -z "$TOKEN" ]; then
        printf "  ${RED}✗${NC} %-30s ${RED}%s${NC}\n" "Keycloak Admin API" "Token acquisition failed"
    else
        # Test API access with token (list realms)
        local REALMS=$(curl -k -sf -H "Authorization: Bearer $TOKEN" \
          "${KEYCLOAK_URL}/admin/realms" 2>/dev/null | grep -o '"realm":"[^"]*' | wc -l | tr -d ' ')

        if [ "$REALMS" -gt 0 ]; then
            printf "  ${GREEN}✓${NC} %-30s ${GREEN}%s${NC}\n" "Keycloak Admin API" "Token valid, API accessible ($REALMS realms found)"
        else
            printf "  ${RED}✗${NC} %-30s ${RED}%s${NC}\n" "Keycloak Admin API" "API returned no data"
        fi
    fi

    # Test Grafana OAuth (kubernetes realm)
    echo -e "${BLUE}[2/2] Testing Grafana OAuth (kubernetes realm)${NC}"

    # Get the Grafana OAuth client secret
    local grafana_secret=$(kubectl get secret grafana-oauth-secret -n observability -o jsonpath='{.data.GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}' 2>/dev/null | base64 -d)

    if [ -z "$grafana_secret" ]; then
        printf "  ${YELLOW}⚠${NC} %-30s ${YELLOW}%s${NC}\n" "Grafana OAuth" "OAuth secret not found in cluster"
    else
        local CLIENT_ID="grafana"
        local CLIENT_SECRET="$grafana_secret"

        # Get OAuth token using client credentials
        local TOKEN=$(curl -k -sf -X POST "${KEYCLOAK_URL}/realms/kubernetes/protocol/openid-connect/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "grant_type=client_credentials" \
          -d "client_id=${CLIENT_ID}" \
          -d "client_secret=${CLIENT_SECRET}" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

        if [ -z "$TOKEN" ]; then
            printf "  ${RED}✗${NC} %-30s ${RED}%s${NC}\n" "Grafana OAuth (kubernetes)" "Token acquisition failed (check client secret)"
        else
            # Verify token by checking introspection endpoint
            local ACTIVE=$(curl -k -sf -X POST "${KEYCLOAK_URL}/realms/kubernetes/protocol/openid-connect/token/introspect" \
              -H "Content-Type: application/x-www-form-urlencoded" \
              -d "token=${TOKEN}" \
              -d "client_id=${CLIENT_ID}" \
              -d "client_secret=${CLIENT_SECRET}" 2>/dev/null | grep -o '"active":[^,]*' | cut -d: -f2 | tr -d ' ')

            if [ "$ACTIVE" == "true" ]; then
                printf "  ${GREEN}✓${NC} %-30s ${GREEN}%s${NC}\n" "Grafana OAuth (kubernetes)" "Token valid and active"
            else
                printf "  ${RED}✗${NC} %-30s ${RED}%s${NC}\n" "Grafana OAuth (kubernetes)" "Token not active"
            fi
        fi
    fi

    echo ""
    echo "OAuth Flow Summary:"
    echo "  - Keycloak Admin API uses password grant (admin credentials)"
    echo "  - Grafana OAuth uses client credentials grant (OAuth secret)"
    echo "  - Tokens are validated against Keycloak introspection endpoint"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to track pytest test results
track_test_results() {
    local repo_root="$1"
    local test_output="$2"
    local test_exit="$3"

    local test_tracking_file="$repo_root/TODO_TESTS.md"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Parse test results
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0

    if echo "$test_output" | grep -q "passed"; then
        passed_tests=$(echo "$test_output" | grep -o "[0-9]* passed" | grep -o "[0-9]*")
        total_tests=$((total_tests + passed_tests))
    fi
    if echo "$test_output" | grep -q "failed"; then
        failed_tests=$(echo "$test_output" | grep -o "[0-9]* failed" | grep -o "[0-9]*")
        total_tests=$((total_tests + failed_tests))
    fi
    if echo "$test_output" | grep -q "skipped"; then
        skipped_tests=$(echo "$test_output" | grep -o "[0-9]* skipped" | grep -o "[0-9]*")
        total_tests=$((total_tests + skipped_tests))
    fi

    # Create or update TODO_TESTS.md
    if [ ! -f "$test_tracking_file" ]; then
        cat > "$test_tracking_file" <<EOF
# Test Execution Tracking

This file tracks pytest test execution history to enable comparison between deployments.

## Test Run History

| Timestamp | Total | Passed | Failed | Skipped | Status |
|-----------|-------|--------|--------|---------|--------|
EOF
    fi

    # Determine overall status
    local status="✓ PASS"
    [ "$failed_tests" -gt 0 ] && status="✗ FAIL"
    [ "$total_tests" -eq 0 ] && status="⚠ NO TESTS"

    # Append test run summary
    echo "| $timestamp | $total_tests | $passed_tests | $failed_tests | $skipped_tests | $status |" >> "$test_tracking_file"

    # Add detailed test results section
    echo "" >> "$test_tracking_file"
    echo "### Test Run: $timestamp" >> "$test_tracking_file"
    echo "" >> "$test_tracking_file"

    if [ "$total_tests" -eq 0 ]; then
        echo "⚠ No tests executed" >> "$test_tracking_file"
    else
        echo "**Summary**: $total_tests tests ($passed_tests passed, $failed_tests failed, $skipped_tests skipped)" >> "$test_tracking_file"
        echo "" >> "$test_tracking_file"

        # List individual test results
        echo "| Test | Status | Duration |" >> "$test_tracking_file"
        echo "|------|--------|----------|" >> "$test_tracking_file"

        echo "$test_output" | grep -E "PASSED|FAILED|SKIPPED|ERROR" | while IFS= read -r test_line; do
            local test_name=$(echo "$test_line" | sed 's/^tests\///' | sed 's/ PASSED$//' | sed 's/ FAILED$//' | sed 's/ SKIPPED$//' | sed 's/ ERROR$//')
            local test_status=""

            if echo "$test_line" | grep -q "PASSED"; then
                test_status="✓ PASSED"
            elif echo "$test_line" | grep -q "FAILED"; then
                test_status="✗ FAILED"
            elif echo "$test_line" | grep -q "SKIPPED"; then
                test_status="○ SKIPPED"
            elif echo "$test_line" | grep -q "ERROR"; then
                test_status="✗ ERROR"
            fi

            echo "| $test_name | $test_status | - |" >> "$test_tracking_file"
        done

        echo "" >> "$test_tracking_file"
    fi

    echo "" >> "$test_tracking_file"
    echo "---" >> "$test_tracking_file"
    echo "" >> "$test_tracking_file"
}

# Function to show comprehensive health summary
show_comprehensive_summary() {
    local argocd_healthy="$1"
    local argocd_progressing="$2"
    local argocd_degraded="$3"
    local total_pods="$4"
    local healthy_pods="$5"
    local failed_pods="$6"
    local waiting_pods="$7"
    local gateway_ready="$8"
    local certs_ready="$9"
    local certs_total="${10}"
    local mtls_mode="${11}"
    local services_accessible="${12}"
    local services_auth="${13}"
    local services_failed="${14}"
    local oauth_working="${15}"
    local tests_passed="${16}"
    local tests_failed="${17}"
    local tests_skipped="${18}"
    local duration="${19}"

    echo ""
    echo "=========================================="
    echo "  📊 PLATFORM HEALTH SUMMARY"
    echo "=========================================="
    echo ""

    printf "%-30s %s\n" "Component" "Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ArgoCD Applications
    local argocd_status="${GREEN}✓ Healthy${NC}"
    [ "$argocd_degraded" -gt 0 ] && argocd_status="${RED}✗ Degraded ($argocd_degraded apps)${NC}"
    [ "$argocd_progressing" -gt 0 ] && [ "$argocd_degraded" -eq 0 ] && argocd_status="${YELLOW}⏳ Progressing ($argocd_progressing apps)${NC}"
    printf "%-30s " "ArgoCD Applications"
    echo -e "$argocd_status"

    # Pods
    local pods_status="${GREEN}✓ All Running ($healthy_pods/$total_pods)${NC}"
    [ "$failed_pods" -gt 0 ] && pods_status="${RED}✗ $failed_pods Failed${NC}"
    [ "$waiting_pods" -gt 0 ] && [ "$failed_pods" -eq 0 ] && pods_status="${YELLOW}⚠ $waiting_pods Waiting${NC}"
    printf "%-30s " "Platform Pods"
    echo -e "$pods_status"

    # Gateway
    local gateway_status="${GREEN}✓ Ready${NC}"
    [ "$gateway_ready" != "true" ] && gateway_status="${RED}✗ Not Ready${NC}"
    printf "%-30s " "Gateway"
    echo -e "$gateway_status"

    # Certificates
    local cert_status="${GREEN}✓ All Ready ($certs_ready/$certs_total)${NC}"
    [ "$certs_ready" -lt "$certs_total" ] && cert_status="${YELLOW}⚠ $certs_ready/$certs_total Ready${NC}"
    printf "%-30s " "TLS Certificates"
    echo -e "$cert_status"

    # mTLS
    local mtls_status="${GREEN}✓ STRICT${NC}"
    [ "$mtls_mode" != "STRICT" ] && mtls_status="${YELLOW}⚠ $mtls_mode${NC}"
    printf "%-30s " "Istio mTLS"
    echo -e "$mtls_status"

    # Service Accessibility
    local svc_status="${GREEN}✓ Accessible ($services_accessible)${NC}"
    [ "$services_failed" -gt 0 ] && svc_status="${RED}✗ $services_failed Failed${NC}"
    [ "$services_auth" -gt 0 ] && [ "$services_failed" -eq 0 ] && svc_status="${YELLOW}🔒 $services_auth Auth Required${NC}"
    printf "%-30s " "Service Endpoints"
    echo -e "$svc_status"

    # OAuth
    local oauth_status="${GREEN}✓ Working${NC}"
    [ "$oauth_working" != "true" ] && oauth_status="${RED}✗ Failed${NC}"
    printf "%-30s " "OAuth Authentication"
    echo -e "$oauth_status"

    # Tests
    local total_tests=$((tests_passed + tests_failed + tests_skipped))
    local test_status="${GREEN}✓ All Passed ($tests_passed/$total_tests)${NC}"
    [ "$tests_failed" -gt 0 ] && test_status="${RED}✗ $tests_failed Failed${NC}"
    [ "$total_tests" -eq 0 ] && test_status="${YELLOW}⚠ No Tests${NC}"
    printf "%-30s " "Integration Tests"
    echo -e "$test_status"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Overall Status
    local overall_status="✅ HEALTHY"
    local overall_color=$GREEN

    if [ "$argocd_degraded" -gt 0 ] || [ "$failed_pods" -gt 0 ] || [ "$gateway_ready" != "true" ] || [ "$tests_failed" -gt 0 ] || [ "$oauth_working" != "true" ]; then
        overall_status="🚨 DEGRADED"
        overall_color=$RED
    elif [ "$argocd_progressing" -gt 0 ] || [ "$waiting_pods" -gt 0 ] || [ "$certs_ready" -lt "$certs_total" ]; then
        overall_status="⏳ PROGRESSING"
        overall_color=$YELLOW
    fi

    echo -e "Overall Status: ${overall_color}${overall_status}${NC}"
    echo ""
    echo "Health check completed in ${duration}s"
    echo "=========================================="
    echo ""
}

# Function to show quick access info
show_access_info() {
    echo ""
    echo -e "${BLUE}Quick Access:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Show full service access information:"
    echo "  ./scripts/show-access-info.sh"
    echo ""
    echo "Gateway Access URLs:"
    echo "  Kagenti UI:    https://kagenti.localtest.me:9443"
    echo "  Keycloak:      https://keycloak.localtest.me:9443"
    echo "  Grafana:       https://grafana.localtest.me:9443"
    echo "  Phoenix:       https://phoenix.localtest.me:9443"
    echo "  Kiali:         https://kiali.localtest.me:9443"
    echo "  Tempo:         https://tempo.localtest.me:9443"
    echo ""
    echo "Note: Ensure /etc/hosts has correct entries (see docs/GATEWAY-ACCESS-KIND.md)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to run pytest integration tests
run_pytest_tests() {
    # All display output goes to stderr so it's visible but not captured
    echo "" >&2
    echo -e "${BLUE}Integration Tests (pytest):${NC}" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # Check if pytest is available
    if ! command -v pytest &>/dev/null; then
        echo -e "${YELLOW}⚠ pytest not installed - skipping integration tests${NC}" >&2
        echo "  Install with: pip install pytest pytest-html" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "0:0:0"  # Return zeros for counts
        return
    fi

    # Change to repository root (script is in scripts/ directory)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_root="$(cd "$script_dir/.." && pwd)"

    echo "Running tests from: $repo_root/tests/" >&2
    echo "" >&2

    # Counters for test results
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    local test_output=""

    # Run pytest with real-time output processing
    while IFS= read -r line; do
        # Capture output for later processing
        test_output+="$line"$'\n'

        # Display test results in real-time (only lines with PASSED/FAILED/SKIPPED/ERROR)
        if echo "$line" | grep -qE " PASSED | FAILED | SKIPPED | ERROR "; then
            # Extract test name (remove percentage and status)
            local test_name=$(echo "$line" | sed 's/ PASSED.*$//' | sed 's/ FAILED.*$//' | sed 's/ SKIPPED.*$//' | sed 's/ ERROR.*$//' | sed 's/^tests\///')
            local test_status=""
            local status_icon=""
            local status_color=$NC

            if echo "$line" | grep -q " PASSED "; then
                test_status="PASSED"
                status_icon="✓"
                status_color=$GREEN
                passed_tests=$((passed_tests + 1))
            elif echo "$line" | grep -q " FAILED "; then
                test_status="FAILED"
                status_icon="✗"
                status_color=$RED
                failed_tests=$((failed_tests + 1))
            elif echo "$line" | grep -q " SKIPPED "; then
                test_status="SKIPPED"
                status_icon="○"
                status_color=$YELLOW
                skipped_tests=$((skipped_tests + 1))
            elif echo "$line" | grep -q " ERROR "; then
                test_status="ERROR"
                status_icon="✗"
                status_color=$RED
                failed_tests=$((failed_tests + 1))
            fi

            printf "  ${status_color}${status_icon}${NC} %-80s ${status_color}%s${NC}\n" "$test_name" "$test_status" >&2
        fi
    done < <(cd "$repo_root" && pytest tests/ -v --tb=no --no-header 2>&1)

    local test_exit=$?
    total_tests=$((passed_tests + failed_tests + skipped_tests))

    echo "" >&2
    echo "Test Summary:" >&2
    printf "  Total: %d tests" "$total_tests" >&2
    [ "$passed_tests" -gt 0 ] && printf " | ${GREEN}✓ %d Passed${NC}" "$passed_tests" >&2
    [ "$failed_tests" -gt 0 ] && printf " | ${RED}✗ %d Failed${NC}" "$failed_tests" >&2
    [ "$skipped_tests" -gt 0 ] && printf " | ${YELLOW}○ %d Skipped${NC}" "$skipped_tests" >&2
    echo "" >&2

    # Show failed tests details if any
    if [ "$failed_tests" -gt 0 ]; then
        echo "" >&2
        echo -e "${RED}Failed Tests - Need Investigation:${NC}" >&2
        echo "$test_output" | grep "FAILED" | while IFS= read -r test_line; do
            local test_name=$(echo "$test_line" | sed 's/^tests\///' | sed 's/ FAILED$//')
            echo "  → $test_name" >&2
        done
        echo "" >&2
        echo "  Run for details: cd $repo_root && pytest tests/ -v" >&2
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # Track test results to TODO_TESTS.md
    track_test_results "$repo_root" "$test_output" "$test_exit"

    # Return test counts for summary
    echo "$passed_tests:$failed_tests:$skipped_tests"
}

# Global variables for summary metrics
SUMMARY_ARGOCD_HEALTHY=0
SUMMARY_ARGOCD_PROGRESSING=0
SUMMARY_ARGOCD_DEGRADED=0
SUMMARY_TOTAL_PODS=0
SUMMARY_HEALTHY_PODS=0
SUMMARY_FAILED_PODS=0
SUMMARY_WAITING_PODS=0
SUMMARY_GATEWAY_READY="false"
SUMMARY_CERTS_READY=0
SUMMARY_CERTS_TOTAL=0
SUMMARY_MTLS_MODE="unknown"
SUMMARY_SERVICES_ACCESSIBLE=0
SUMMARY_SERVICES_AUTH=0
SUMMARY_SERVICES_FAILED=0
SUMMARY_OAUTH_WORKING="false"
SUMMARY_TESTS_PASSED=0
SUMMARY_TESTS_FAILED=0
SUMMARY_TESTS_SKIPPED=0

# Wrapper to collect ArgoCD app metrics
collect_argocd_metrics() {
    local argocd_cmd="argocd app list"
    if [ "$USE_PORT_FORWARD" == "true" ]; then
        argocd_cmd="$argocd_cmd --port-forward --port-forward-namespace ${ARGOCD_NAMESPACE} --grpc-web"
    fi

    local app_list=$($argocd_cmd 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$app_list" ]; then
        SUMMARY_ARGOCD_HEALTHY=$(echo "$app_list" | tail -n +2 | awk '{print $6}' | grep -c "Healthy" 2>/dev/null || echo "0")
        SUMMARY_ARGOCD_HEALTHY=$(echo "$SUMMARY_ARGOCD_HEALTHY" | tr -d ' \n')
        SUMMARY_ARGOCD_PROGRESSING=$(echo "$app_list" | tail -n +2 | awk '{print $6}' | grep -c "Progressing" 2>/dev/null || echo "0")
        SUMMARY_ARGOCD_PROGRESSING=$(echo "$SUMMARY_ARGOCD_PROGRESSING" | tr -d ' \n')
        SUMMARY_ARGOCD_DEGRADED=$(echo "$app_list" | tail -n +2 | awk '{print $6}' | grep -Ec "Degraded|Missing" 2>/dev/null || echo "0")
        SUMMARY_ARGOCD_DEGRADED=$(echo "$SUMMARY_ARGOCD_DEGRADED" | tr -d ' \n')
    fi
}

# Wrapper to collect pod metrics
collect_pod_metrics() {
    local namespaces=("argocd" "istio-system" "cert-manager" "tekton-pipelines" "keycloak" "kagenti-system" "observability" "kiali-system" "default" "team1")

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            SUMMARY_TOTAL_PODS=$((SUMMARY_TOTAL_PODS + total))

            while IFS= read -r pod_line; do
                local ready=$(echo "$pod_line" | awk '{print $2}')
                local status=$(echo "$pod_line" | awk '{print $3}')
                local ready_containers=$(echo "$ready" | cut -d'/' -f1)
                local total_containers=$(echo "$ready" | cut -d'/' -f2)

                if [ "$ready_containers" -eq "$total_containers" ] && [[ "$status" == "Running" || "$status" == "Succeeded" ]]; then
                    SUMMARY_HEALTHY_PODS=$((SUMMARY_HEALTHY_PODS + 1))
                elif [[ "$status" == "Failed" || "$status" == "Error" ]]; then
                    SUMMARY_FAILED_PODS=$((SUMMARY_FAILED_PODS + 1))
                elif [[ "$status" == *"Back"* || "$status" == *"Error"* || "$status" == "Pending" ]]; then
                    SUMMARY_WAITING_PODS=$((SUMMARY_WAITING_PODS + 1))
                fi
            done < <(kubectl get pods -n "$ns" --no-headers 2>/dev/null)
        fi
    done
}

# Wrapper to collect gateway metrics
collect_gateway_metrics() {
    if kubectl get gateway external-gateway -n default &>/dev/null; then
        local programmed=$(kubectl get gateway external-gateway -n default -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
        [ "$programmed" == "True" ] && SUMMARY_GATEWAY_READY="true"
    fi
}

# Wrapper to collect certificate metrics
collect_cert_metrics() {
    local certs=$(kubectl get certificate -A --no-headers 2>/dev/null)
    if [ -n "$certs" ]; then
        SUMMARY_CERTS_TOTAL=$(echo "$certs" | wc -l | tr -d ' ')
        SUMMARY_CERTS_READY=$(echo "$certs" | grep -c "True" || echo "0")
    fi
}

# Wrapper to collect mTLS metrics
collect_mtls_metrics() {
    if kubectl get peerauthentication -n istio-system default-strict-mtls &>/dev/null; then
        SUMMARY_MTLS_MODE=$(kubectl get peerauthentication -n istio-system default-strict-mtls -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
    fi
}

# Wrapper to collect service accessibility metrics
collect_service_metrics() {
    local services=("keycloak:9443" "kagenti:9443" "grafana:9443" "kiali:9443" "phoenix:9443" "tempo:9443")

    for service_entry in "${services[@]}"; do
        local service=$(echo "$service_entry" | cut -d: -f1)
        local port=$(echo "$service_entry" | cut -d: -f2)
        local url="https://${service}.localtest.me:${port}"
        local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
        local curl_exit=$?

        if [ $curl_exit -ne 0 ]; then
            SUMMARY_SERVICES_FAILED=$((SUMMARY_SERVICES_FAILED + 1))
        elif [[ "$http_code" =~ ^(200|201|202|204)$ ]]; then
            SUMMARY_SERVICES_ACCESSIBLE=$((SUMMARY_SERVICES_ACCESSIBLE + 1))
        elif [[ "$http_code" =~ ^(401|403)$ ]]; then
            SUMMARY_SERVICES_AUTH=$((SUMMARY_SERVICES_AUTH + 1))
        elif [[ "$http_code" =~ ^(404|500|502|503|504)$ ]]; then
            SUMMARY_SERVICES_FAILED=$((SUMMARY_SERVICES_FAILED + 1))
        fi
    done
}

# Wrapper to collect OAuth metrics
collect_oauth_metrics() {
    local keycloak_ready=$(kubectl get pod -n keycloak -l app=keycloak --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$keycloak_ready" -gt 0 ]; then
        # Test Keycloak Admin API token acquisition via gateway
        local KEYCLOAK_URL="https://keycloak.localtest.me:9443"
        local TOKEN=$(curl -k -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "username=admin" \
          -d "password=admin123" \
          -d "grant_type=password" \
          -d "client_id=admin-cli" 2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

        [ -n "$TOKEN" ] && SUMMARY_OAUTH_WORKING="true"
    fi
}

# Main execution
main() {
    local start_time=$(date +%s)

    check_argocd || true
    get_argocd_apps || true
    check_pods || true
    check_problem_pods || true
    check_gateway || true
    check_certificates || true
    check_mtls || true
    check_service_accessibility || true
    check_oauth_authentication || true

    # Run tests and capture results
    local test_results=$(run_pytest_tests)
    if [ -n "$test_results" ]; then
        SUMMARY_TESTS_PASSED=$(echo "$test_results" | cut -d: -f1)
        SUMMARY_TESTS_FAILED=$(echo "$test_results" | cut -d: -f2)
        SUMMARY_TESTS_SKIPPED=$(echo "$test_results" | cut -d: -f3)
    fi

    # Collect metrics for summary
    collect_argocd_metrics
    collect_pod_metrics
    collect_gateway_metrics
    collect_cert_metrics
    collect_mtls_metrics
    collect_service_metrics
    collect_oauth_metrics

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Show comprehensive summary
    show_comprehensive_summary \
        "$SUMMARY_ARGOCD_HEALTHY" \
        "$SUMMARY_ARGOCD_PROGRESSING" \
        "$SUMMARY_ARGOCD_DEGRADED" \
        "$SUMMARY_TOTAL_PODS" \
        "$SUMMARY_HEALTHY_PODS" \
        "$SUMMARY_FAILED_PODS" \
        "$SUMMARY_WAITING_PODS" \
        "$SUMMARY_GATEWAY_READY" \
        "$SUMMARY_CERTS_READY" \
        "$SUMMARY_CERTS_TOTAL" \
        "$SUMMARY_MTLS_MODE" \
        "$SUMMARY_SERVICES_ACCESSIBLE" \
        "$SUMMARY_SERVICES_AUTH" \
        "$SUMMARY_SERVICES_FAILED" \
        "$SUMMARY_OAUTH_WORKING" \
        "$SUMMARY_TESTS_PASSED" \
        "$SUMMARY_TESTS_FAILED" \
        "$SUMMARY_TESTS_SKIPPED" \
        "$duration"

    show_access_info
}

main "$@"
