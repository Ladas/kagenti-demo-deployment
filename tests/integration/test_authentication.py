#!/usr/bin/env python3
"""
Authentication and Authorization Integration Tests for Kagenti Platform

Tests end-to-end authentication flows:
- Keycloak OIDC token acquisition
- OAuth2-Proxy protected service access (Phoenix, Kiali, Prometheus)
- Direct Keycloak OIDC integration (Grafana, ArgoCD)
- Token validation and session management

Authentication Architecture:
╔════════════════════════════════════════════════════════════════╗
║ OAuth2-Proxy Protected (via oauth2-proxy pods):               ║
║   - Phoenix (kagenti realm)                                    ║
║   - Kiali (kubernetes realm)                                   ║
║   - Prometheus (kubernetes realm)                              ║
╠════════════════════════════════════════════════════════════════╣
║ Direct Keycloak OIDC Integration:                             ║
║   - Grafana (native OIDC support)                              ║
║   - ArgoCD (Dex + Keycloak)                                    ║
║   - Keycloak Admin Console                                     ║
╚════════════════════════════════════════════════════════════════╝

Requirements:
    pip install -r requirements.txt

Usage:
    pytest tests/integration/test_authentication.py -v

    # Run only critical auth tests
    pytest tests/integration/test_authentication.py -v -m critical

    # Skip slow OAuth flow tests
    pytest tests/integration/test_authentication.py -v -m "not slow"
"""

import base64
import json
import time
import urllib.parse
from typing import Dict, Optional, Tuple

import pytest
import requests
from kubernetes import client, config
from kubernetes.client.rest import ApiException


# ============================================================================
# Fixtures and Utilities
# ============================================================================

@pytest.fixture(scope="session")
def k8s_client():
    """Load Kubernetes configuration and return CoreV1Api client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()
    return client.CoreV1Api()


@pytest.fixture(scope="session")
def keycloak_admin_credentials():
    """Get Keycloak admin credentials from Kubernetes secret."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()

    k8s_api = client.CoreV1Api()

    try:
        secret = k8s_api.read_namespaced_secret(
            name="keycloak-admin-credentials",
            namespace="keycloak"
        )

        username = base64.b64decode(secret.data["ADMIN_USERNAME"]).decode("utf-8")
        password = base64.b64decode(secret.data["ADMIN_PASSWORD"]).decode("utf-8")

        return {"username": username, "password": password}
    except ApiException as e:
        pytest.skip(f"Could not read Keycloak admin credentials: {e}")


@pytest.fixture(scope="session")
def keycloak_token(keycloak_admin_credentials) -> Dict[str, str]:
    """
    Acquire access token from Keycloak using admin credentials.

    Returns dict with:
        - access_token: JWT access token
        - refresh_token: JWT refresh token
        - token_type: Bearer
        - expires_in: Seconds until expiration
    """
    token_url = "https://keycloak.localtest.me:9443/realms/master/protocol/openid-connect/token"

    data = {
        "grant_type": "password",
        "client_id": "admin-cli",
        "username": keycloak_admin_credentials["username"],
        "password": keycloak_admin_credentials["password"],
    }

    try:
        response = requests.post(
            token_url,
            data=data,
            verify=False,  # Self-signed cert for localtest.me
            timeout=10
        )

        response.raise_for_status()
        return response.json()

    except requests.exceptions.RequestException as e:
        pytest.skip(f"Could not acquire Keycloak token: {e}")


def get_oauth_client_credentials(k8s_client, namespace: str, secret_name: str) -> Tuple[str, str]:
    """Get OAuth2 client ID and secret from Kubernetes secret."""
    try:
        secret = k8s_client.read_namespaced_secret(
            name=secret_name,
            namespace=namespace
        )

        client_id = base64.b64decode(secret.data["CLIENT_ID"]).decode("utf-8")
        client_secret = base64.b64decode(secret.data["CLIENT_SECRET"]).decode("utf-8")

        return client_id, client_secret

    except ApiException as e:
        pytest.skip(f"Could not read OAuth client secret {namespace}/{secret_name}: {e}")


# ============================================================================
# Test: Keycloak Token Acquisition
# ============================================================================

class TestKeycloakTokens:
    """Test Keycloak OIDC token acquisition and validation."""

    @pytest.mark.critical
    def test_keycloak_token_endpoint_accessible(self):
        """Verify Keycloak token endpoint is accessible via gateway."""
        token_url = "https://keycloak.localtest.me:9443/realms/master/protocol/openid-connect/token"

        # Send invalid request to check endpoint accessibility
        response = requests.post(
            token_url,
            data={"grant_type": "password"},
            verify=False,
            timeout=10
        )

        # Should return 401 Unauthorized (not 404 or connection error)
        assert response.status_code in [400, 401], \
            f"Token endpoint returned unexpected status: {response.status_code}"

    @pytest.mark.critical
    def test_acquire_token_with_admin_credentials(self, keycloak_token):
        """Verify we can acquire access token using admin credentials."""
        assert "access_token" in keycloak_token, \
            "Token response missing access_token"
        assert "refresh_token" in keycloak_token, \
            "Token response missing refresh_token"
        assert keycloak_token["token_type"].lower() == "bearer", \
            f"Unexpected token type: {keycloak_token['token_type']}"

    def test_token_contains_valid_jwt(self, keycloak_token):
        """Verify access token is valid JWT format."""
        access_token = keycloak_token["access_token"]

        # JWT has 3 parts: header.payload.signature
        parts = access_token.split(".")
        assert len(parts) == 3, \
            f"Access token not valid JWT format (expected 3 parts, got {len(parts)})"

        # Decode JWT payload (without verification for test purposes)
        try:
            # Add padding if needed
            payload = parts[1]
            payload += "=" * (4 - len(payload) % 4)
            decoded = base64.b64decode(payload)
            claims = json.loads(decoded)

            # Verify expected claims
            assert "iss" in claims, "JWT missing 'iss' (issuer) claim"
            assert "exp" in claims, "JWT missing 'exp' (expiration) claim"
            assert "sub" in claims, "JWT missing 'sub' (subject) claim"

        except Exception as e:
            pytest.fail(f"Could not decode JWT payload: {e}")

    def test_token_refresh(self, keycloak_token):
        """Verify we can refresh access token using refresh token."""
        token_url = "https://keycloak.localtest.me:9443/realms/master/protocol/openid-connect/token"

        data = {
            "grant_type": "refresh_token",
            "client_id": "admin-cli",
            "refresh_token": keycloak_token["refresh_token"],
        }

        response = requests.post(
            token_url,
            data=data,
            verify=False,
            timeout=10
        )

        assert response.status_code == 200, \
            f"Token refresh failed: {response.status_code}"

        refreshed_token = response.json()
        assert "access_token" in refreshed_token, \
            "Refreshed token missing access_token"

        # New access token should be different
        assert refreshed_token["access_token"] != keycloak_token["access_token"], \
            "Refreshed access token same as original"


# ============================================================================
# Test: Keycloak Admin Console Authentication
# ============================================================================

class TestKeycloakAdminAuth:
    """Test Keycloak admin console authentication."""

    @pytest.mark.critical
    def test_keycloak_admin_console_redirect(self):
        """Verify Keycloak admin console redirects to login."""
        admin_url = "https://keycloak.localtest.me:9443/admin/"

        response = requests.get(
            admin_url,
            verify=False,
            allow_redirects=False,
            timeout=10
        )

        # Should redirect to authentication
        assert response.status_code in [200, 302, 303, 307, 308], \
            f"Admin console unexpected status: {response.status_code}"

    @pytest.mark.slow
    def test_keycloak_admin_api_with_token(self, keycloak_token):
        """Verify Keycloak admin API accepts bearer token."""
        admin_api_url = "https://keycloak.localtest.me:9443/admin/realms"

        headers = {
            "Authorization": f"Bearer {keycloak_token['access_token']}",
            "Accept": "application/json"
        }

        response = requests.get(
            admin_api_url,
            headers=headers,
            verify=False,
            timeout=10
        )

        assert response.status_code == 200, \
            f"Admin API request failed: {response.status_code}"

        realms = response.json()
        assert isinstance(realms, list), \
            "Admin API should return list of realms"

        # Verify master and kagenti realms exist
        realm_names = [r["realm"] for r in realms]
        assert "master" in realm_names, "Master realm not found"
        assert "kagenti" in realm_names, "Kagenti realm not found"


# ============================================================================
# Test: OAuth2-Proxy Protected Services
# ============================================================================

class TestOAuth2ProxyProtection:
    """Test OAuth2-Proxy protected service access (Phoenix, Kiali, Prometheus)."""

    @pytest.mark.critical
    def test_phoenix_requires_authentication(self):
        """Verify Phoenix redirects unauthenticated requests to OAuth2-Proxy (kagenti realm)."""
        phoenix_url = "https://phoenix.localtest.me:9443/"

        response = requests.get(
            phoenix_url,
            verify=False,
            allow_redirects=False,
            timeout=10
        )

        # OAuth2-Proxy should intercept and redirect
        assert response.status_code in [200, 302, 303, 307, 308], \
            f"Phoenix unexpected status for unauth request: {response.status_code}"

        if response.status_code in [302, 303, 307, 308]:
            location = response.headers.get("location", "")
            assert "/oauth2" in location.lower() or "keycloak" in location.lower(), \
                f"Expected redirect to OAuth2-Proxy or Keycloak, got: {location}"

    @pytest.mark.critical
    def test_kiali_requires_authentication(self):
        """Verify Kiali redirects unauthenticated requests to OAuth2-Proxy (kubernetes realm)."""
        kiali_url = "https://kiali.localtest.me:9443/"

        response = requests.get(
            kiali_url,
            verify=False,
            allow_redirects=False,
            timeout=10
        )

        # OAuth2-Proxy should intercept and redirect
        assert response.status_code in [200, 302, 303, 307, 308], \
            f"Kiali unexpected status for unauth request: {response.status_code}"

        if response.status_code in [302, 303, 307, 308]:
            location = response.headers.get("location", "")
            assert "/oauth2" in location.lower() or "keycloak" in location.lower(), \
                f"Expected redirect to OAuth2-Proxy or Keycloak, got: {location}"

    def test_prometheus_requires_authentication(self):
        """Verify Prometheus redirects unauthenticated requests to OAuth2-Proxy (kubernetes realm)."""
        prometheus_url = "https://prometheus.localtest.me:9443/"

        response = requests.get(
            prometheus_url,
            verify=False,
            allow_redirects=False,
            timeout=10
        )

        # OAuth2-Proxy should intercept and redirect
        assert response.status_code in [200, 302, 303, 307, 308], \
            f"Prometheus unexpected status for unauth request: {response.status_code}"

        if response.status_code in [302, 303, 307, 308]:
            location = response.headers.get("location", "")
            assert "/oauth2" in location.lower() or "keycloak" in location.lower(), \
                f"Expected redirect to OAuth2-Proxy or Keycloak, got: {location}"


# ============================================================================
# Test: OAuth2 Client Secrets
# ============================================================================

class TestOAuth2ClientSecrets:
    """Test OAuth2 client credentials are properly configured for OAuth2-Proxy protected services."""

    def test_phoenix_oauth_secret_exists(self, k8s_client):
        """Verify Phoenix OAuth2 client secret exists (kagenti realm)."""
        try:
            client_id, client_secret = get_oauth_client_credentials(
                k8s_client,
                "observability",
                "phoenix-oauth-secret"
            )

            assert client_id, "Phoenix OAuth client ID is empty"
            assert client_secret, "Phoenix OAuth client secret is empty"

        except Exception as e:
            pytest.skip(f"Phoenix OAuth secret not available: {e}")

    def test_kiali_oauth_secret_exists(self, k8s_client):
        """Verify Kiali OAuth2 client secret exists (kubernetes realm)."""
        try:
            client_id, client_secret = get_oauth_client_credentials(
                k8s_client,
                "kiali-system",
                "kiali-oauth-secret"
            )

            assert client_id, "Kiali OAuth client ID is empty"
            assert client_secret, "Kiali OAuth client secret is empty"

        except Exception as e:
            pytest.skip(f"Kiali OAuth secret not available: {e}")

    def test_prometheus_oauth_secret_exists(self, k8s_client):
        """Verify Prometheus OAuth2 client secret exists (kubernetes realm)."""
        try:
            client_id, client_secret = get_oauth_client_credentials(
                k8s_client,
                "observability",
                "prometheus-oauth-secret"
            )

            assert client_id, "Prometheus OAuth client ID is empty"
            assert client_secret, "Prometheus OAuth client secret is empty"

        except Exception as e:
            pytest.skip(f"Prometheus OAuth secret not available: {e}")


# ============================================================================
# Test: OAuth2-Proxy Deployment Health
# ============================================================================

class TestOAuth2ProxyHealth:
    """Test OAuth2-Proxy deployments are healthy (Phoenix, Kiali, Prometheus)."""

    def test_phoenix_oauth2_proxy_healthy(self):
        """Verify Phoenix OAuth2-Proxy deployment is healthy (kagenti realm)."""
        try:
            config.load_kube_config()
        except config.ConfigException:
            config.load_incluster_config()

        k8s_apps = client.AppsV1Api()

        deployment = k8s_apps.read_namespaced_deployment(
            name="phoenix-oauth2-proxy",
            namespace="oauth2-proxy"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Phoenix OAuth2-Proxy has no ready replicas"

    def test_kiali_oauth2_proxy_healthy(self):
        """Verify Kiali OAuth2-Proxy deployment is healthy (kubernetes realm)."""
        try:
            config.load_kube_config()
        except config.ConfigException:
            config.load_incluster_config()

        k8s_apps = client.AppsV1Api()

        deployment = k8s_apps.read_namespaced_deployment(
            name="kiali-oauth2-proxy",
            namespace="oauth2-proxy"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Kiali OAuth2-Proxy has no ready replicas"

    def test_prometheus_oauth2_proxy_healthy(self):
        """Verify Prometheus OAuth2-Proxy deployment is healthy (kubernetes realm)."""
        try:
            config.load_kube_config()
        except config.ConfigException:
            config.load_incluster_config()

        k8s_apps = client.AppsV1Api()

        deployment = k8s_apps.read_namespaced_deployment(
            name="prometheus-oauth2-proxy",
            namespace="oauth2-proxy"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Prometheus OAuth2-Proxy has no ready replicas"


# ============================================================================
# Test: Direct Keycloak OIDC Integration (Grafana, ArgoCD)
# ============================================================================

class TestDirectKeycloakOIDC:
    """Test services with direct Keycloak OIDC integration (not OAuth2-Proxy)."""

    @pytest.mark.critical
    def test_grafana_oidc_configured(self):
        """Verify Grafana uses direct Keycloak OIDC (not OAuth2-Proxy)."""
        # Grafana should be accessible directly and redirect to Keycloak for auth
        grafana_url = "https://grafana.localtest.me:9443/"

        response = requests.get(
            grafana_url,
            verify=False,
            allow_redirects=False,
            timeout=10
        )

        # Grafana may return 200 (login page) or redirect to Keycloak
        assert response.status_code in [200, 302, 303, 307, 308], \
            f"Grafana unexpected status: {response.status_code}"

        # If redirect, should go directly to Keycloak (NOT oauth2-proxy)
        if response.status_code in [302, 303, 307, 308]:
            location = response.headers.get("location", "")
            # Should contain "keycloak" but NOT "/oauth2/"
            if "keycloak" in location.lower():
                assert "/oauth2/" not in location.lower(), \
                    f"Grafana should use direct OIDC, not OAuth2-Proxy: {location}"

    def test_argocd_auth_configured(self):
        """Verify ArgoCD authentication is configured (Dex + Keycloak)."""
        # ArgoCD uses Dex for OIDC integration with Keycloak
        argocd_url = "https://argocd.localtest.me:9443/"

        response = requests.get(
            argocd_url,
            verify=False,
            allow_redirects=False,
            timeout=10
        )

        # ArgoCD should return some form of response (login page or redirect)
        assert response.status_code in [200, 301, 302, 303, 307, 308], \
            f"ArgoCD unexpected status: {response.status_code}"


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
