#!/bin/bash
# Generate OAuth2 Proxy Keycloak Client Secrets
# This script configures Keycloak clients with credentials for OAuth2 Proxy

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.keycloak.svc:8080}"
ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

echo "=== Keycloak OAuth2 Proxy Client Secret Generator ==="
echo ""

# Get admin token
echo "1. Getting admin token..."
TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get admin token"
  exit 1
fi
echo "✓ Got admin token"

# Function to update client and get secret
update_client_secret() {
  local realm=$1
  local client_id=$2
  local secret_name=$3

  echo ""
  echo "Processing ${client_id} in ${realm} realm..."

  # Get client UUID
  CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${realm}/clients" \
    -H "Authorization: Bearer ${TOKEN}" | jq -r ".[] | select(.clientId==\"${client_id}\") | .id")

  if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" = "null" ]; then
    echo "  ✗ Client ${client_id} not found in ${realm} realm"
    return 1
  fi

  # Update client to use client secret
  curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${realm}/clients/${CLIENT_UUID}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"${client_id}\",
      \"publicClient\": false,
      \"serviceAccountsEnabled\": false,
      \"standardFlowEnabled\": true,
      \"directAccessGrantsEnabled\": false,
      \"secret\": \"$(openssl rand -base64 32)\"
    }" > /dev/null

  # Get the secret
  SECRET=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${realm}/clients/${CLIENT_UUID}/client-secret" \
    -H "Authorization: Bearer ${TOKEN}" | jq -r '.value')

  if [ -z "$SECRET" ] || [ "$SECRET" = "null" ]; then
    echo "  ✗ Failed to get secret for ${client_id}"
    return 1
  fi

  echo "  ✓ Client ${client_id} configured"
  echo "  Secret: ${SECRET}"

  # Create Kubernetes secret YAML
  cat > "/tmp/${secret_name}.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: oauth2-proxy
type: Opaque
stringData:
  client-secret: "${SECRET}"
EOF

  echo "  ✓ Secret YAML created: /tmp/${secret_name}.yaml"
}

# Update clients
echo ""
echo "2. Configuring Keycloak clients..."

update_client_secret "kubernetes" "tempo" "keycloak-tempo-client-secret"
update_client_secret "kagenti" "phoenix" "keycloak-phoenix-client-secret"
update_client_secret "kubernetes" "prometheus" "keycloak-prometheus-client-secret"

# Kiali client needs to be created first
echo ""
echo "Processing kiali in kubernetes realm..."
KIALI_CLIENT_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/kubernetes/clients" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.clientId=="kiali") | .id')

if [ -z "$KIALI_CLIENT_EXISTS" ] || [ "$KIALI_CLIENT_EXISTS" = "null" ]; then
  echo "  Creating kiali client..."
  KIALI_SECRET=$(openssl rand -base64 32)

  curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kubernetes/clients" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"kiali\",
      \"name\": \"Kiali Service Mesh\",
      \"description\": \"Istio service mesh visualization\",
      \"enabled\": true,
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"bearerOnly\": false,
      \"standardFlowEnabled\": true,
      \"implicitFlowEnabled\": false,
      \"directAccessGrantsEnabled\": false,
      \"redirectUris\": [
        \"https://kiali.localtest.me:9443/oauth2/callback\",
        \"https://kiali.localtest.me:9443/*\"
      ],
      \"webOrigins\": [
        \"https://kiali.localtest.me:9443\"
      ],
      \"secret\": \"${KIALI_SECRET}\"
    }" > /dev/null

  echo "  ✓ Kiali client created"
  echo "  Secret: ${KIALI_SECRET}"

  cat > "/tmp/keycloak-kiali-client-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-kiali-client-secret
  namespace: oauth2-proxy
type: Opaque
stringData:
  client-secret: "${KIALI_SECRET}"
EOF
  echo "  ✓ Secret YAML created: /tmp/keycloak-kiali-client-secret.yaml"
else
  update_client_secret "kubernetes" "kiali" "keycloak-kiali-client-secret"
fi

# Generate cookie secret
echo ""
echo "3. Generating OAuth2 Proxy cookie secret..."
COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)
cat > "/tmp/oauth2-proxy-cookie-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-secrets
  namespace: oauth2-proxy
type: Opaque
stringData:
  cookie-secret: "${COOKIE_SECRET}"
EOF
echo "  ✓ Cookie secret YAML created: /tmp/oauth2-proxy-cookie-secret.yaml"

echo ""
echo "=== Summary ==="
echo "✓ All client secrets generated"
echo ""
echo "Secret files created in /tmp/:"
ls -la /tmp/keycloak-*-secret.yaml /tmp/oauth2-proxy-cookie-secret.yaml 2>/dev/null | awk '{print "  " $9}'
echo ""
echo "To apply these secrets:"
echo "  kubectl apply -f /tmp/keycloak-tempo-client-secret.yaml"
echo "  kubectl apply -f /tmp/keycloak-phoenix-client-secret.yaml"
echo "  kubectl apply -f /tmp/keycloak-prometheus-client-secret.yaml"
echo "  kubectl apply -f /tmp/keycloak-kiali-client-secret.yaml"
echo "  kubectl apply -f /tmp/oauth2-proxy-cookie-secret.yaml"
echo ""
echo "Or apply all at once:"
echo "  kubectl apply -f /tmp/keycloak-*-secret.yaml -f /tmp/oauth2-proxy-cookie-secret.yaml"
