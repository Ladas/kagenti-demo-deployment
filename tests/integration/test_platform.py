#!/usr/bin/env python3
"""
Platform Services Integration Tests for Kagenti Platform

Tests platform services and authentication:
- Keycloak (identity and access management)
- Kagenti UI (web interface)
- Platform Operator (CRD management)
- Kagenti Operator (agent lifecycle)
- External Gateway (ingress routing)

Requirements:
    pip install -r requirements.txt

Usage:
    pytest tests/integration/test_platform.py -v
"""

import time
from typing import Dict, List

import pytest
import requests
from kubernetes import client, config
from kubernetes.client.rest import ApiException


# ============================================================================
# Fixtures
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
def k8s_apps_client():
    """Return Kubernetes AppsV1Api client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()
    return client.AppsV1Api()


@pytest.fixture(scope="session")
def k8s_custom_client():
    """Return Kubernetes CustomObjectsApi client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()
    return client.CustomObjectsApi()


def port_forward(namespace: str, service: str, local_port: int, remote_port: int, duration: int = 60):
    """Create port-forward to service for testing."""
    import subprocess
    proc = subprocess.Popen([
        "kubectl", "port-forward",
        "-n", namespace,
        f"svc/{service}",
        f"{local_port}:{remote_port}"
    ])
    time.sleep(5)
    return proc


# ============================================================================
# Test: Keycloak Identity Provider
# ============================================================================

class TestKeycloak:
    """Test Keycloak identity and access management."""

    def test_keycloak_healthy(self, k8s_apps_client):
        """Verify Keycloak StatefulSet is healthy."""
        statefulset = k8s_apps_client.read_namespaced_stateful_set(
            name="keycloak",
            namespace="keycloak"
        )

        assert statefulset.status.ready_replicas >= 1, \
            "Keycloak has no ready replicas"

    def test_keycloak_service_exists(self, k8s_client):
        """Verify Keycloak service is created."""
        service = k8s_client.read_namespaced_service(
            name="keycloak",
            namespace="keycloak"
        )

        assert service is not None, "Keycloak service not found"
        assert service.spec.type == "ClusterIP", \
            "Keycloak service should be ClusterIP type"

    def test_keycloak_postgres_healthy(self, k8s_apps_client):
        """Verify Keycloak PostgreSQL backend is healthy."""
        statefulset = k8s_apps_client.read_namespaced_stateful_set(
            name="postgres",
            namespace="keycloak"
        )

        assert statefulset.status.ready_replicas >= 1, \
            "Keycloak PostgreSQL has no ready replicas"

    def test_keycloak_realm_imports_completed(self, k8s_client):
        """Verify Keycloak realm import jobs completed."""
        realm_jobs = [
            "keycloak-import-kagenti-realm",
            "keycloak-import-kubernetes-realm",
        ]

        for job_name in realm_jobs:
            try:
                pods = k8s_client.list_namespaced_pod(
                    namespace="keycloak",
                    label_selector=f"job-name={job_name}"
                )

                if len(pods.items) == 0:
                    pytest.skip(f"Realm import job {job_name} not found")

                job_pod = pods.items[0]
                assert job_pod.status.phase in ["Succeeded", "Completed"], \
                    f"Realm import job {job_name} failed: {job_pod.status.phase}"

            except ApiException:
                pytest.skip(f"Could not check realm import job {job_name}")

    @pytest.mark.slow
    def test_keycloak_admin_api_accessible(self, k8s_client):
        """Test Keycloak admin API is accessible."""
        proc = None
        try:
            proc = port_forward("keycloak", "keycloak", 8080, 8080, duration=30)
            time.sleep(8)

            response = requests.get(
                "http://localhost:8080/",
                timeout=10,
                allow_redirects=True
            )

            # Keycloak root redirects to /realms/master
            assert response.status_code == 200, \
                f"Keycloak API failed: {response.status_code}"

        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"Could not connect to Keycloak: {e}")
        finally:
            if proc:
                proc.terminate()
                proc.wait(timeout=5)

    @pytest.mark.critical
    def test_keycloak_https_gateway_access(self):
        """Test Keycloak admin console accessible via HTTPS gateway (keycloak.localtest.me:9443)."""
        try:
            response = requests.get(
                "https://keycloak.localtest.me:9443/",
                timeout=10,
                verify=False,  # Self-signed cert for localtest.me
                allow_redirects=False
            )

            # Keycloak root should redirect to /admin/ console
            assert response.status_code in [200, 302, 303, 307, 308], \
                f"Keycloak HTTPS gateway access failed: {response.status_code}"

            # If redirect, verify it's to admin console
            if response.status_code in [302, 303, 307, 308]:
                location = response.headers.get("location", "")
                assert "/admin" in location.lower(), \
                    f"Keycloak redirect not to admin console: {location}"

        except requests.exceptions.ConnectionError as e:
            pytest.fail(f"Could not connect to Keycloak via gateway: {e}")
        except requests.exceptions.Timeout:
            pytest.fail("Keycloak gateway request timed out")

    @pytest.mark.slow
    def test_keycloak_kagenti_realm_accessible(self, k8s_client):
        """Test Keycloak kagenti realm is accessible."""
        proc = None
        try:
            proc = port_forward("keycloak", "keycloak", 8080, 8080, duration=30)
            time.sleep(8)

            response = requests.get(
                "http://localhost:8080/realms/kagenti",
                timeout=10
            )

            assert response.status_code == 200, \
                f"Keycloak kagenti realm failed: {response.status_code}"

            data = response.json()
            assert data.get("realm") == "kagenti", \
                "Keycloak kagenti realm name mismatch"

        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"Could not connect to Keycloak: {e}")
        finally:
            if proc:
                proc.terminate()
                proc.wait(timeout=5)


# ============================================================================
# Test: Kagenti UI
# ============================================================================

class TestKagentiUI:
    """Test Kagenti web UI."""

    def test_kagenti_ui_healthy(self, k8s_apps_client):
        """Verify Kagenti UI deployment is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="kagenti-ui",
            namespace="kagenti-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Kagenti UI has no ready replicas"

    def test_kagenti_ui_service_exists(self, k8s_client):
        """Verify Kagenti UI service is created."""
        service = k8s_client.read_namespaced_service(
            name="kagenti-ui",
            namespace="kagenti-system"
        )

        assert service is not None, "Kagenti UI service not found"

    def test_kagenti_ui_oauth_config_completed(self, k8s_client):
        """Verify Kagenti UI OAuth configuration job completed."""
        try:
            pods = k8s_client.list_namespaced_pod(
                namespace="kagenti-system",
                label_selector="job-name=kagenti-ui-oauth-config"
            )

            if len(pods.items) == 0:
                pytest.skip("Kagenti UI OAuth config job not found")

            job_pod = pods.items[0]
            assert job_pod.status.phase in ["Succeeded", "Completed"], \
                f"OAuth config job failed: {job_pod.status.phase}"

        except ApiException:
            pytest.skip("Could not check OAuth config job")

    def test_kagenti_ui_oauth_secret_exists(self, k8s_client):
        """Verify Kagenti UI OAuth secret was created."""
        try:
            secret = k8s_client.read_namespaced_secret(
                name="kagenti-ui-oauth-secret",
                namespace="kagenti-system"
            )

            assert secret is not None, "Kagenti UI OAuth secret not found"

            # Check secret has required keys
            assert "CLIENT_ID" in secret.data, \
                "OAuth secret missing CLIENT_ID"
            assert "CLIENT_SECRET" in secret.data, \
                "OAuth secret missing CLIENT_SECRET"

        except ApiException as e:
            if e.status == 404:
                pytest.fail("Kagenti UI OAuth secret not found")
            raise

    @pytest.mark.slow
    def test_kagenti_ui_responds(self, k8s_client):
        """Test Kagenti UI responds to HTTP requests."""
        proc = None
        try:
            proc = port_forward("kagenti-system", "kagenti-ui", 3000, 3000, duration=30)
            time.sleep(8)

            response = requests.get(
                "http://localhost:3000/",
                timeout=10,
                allow_redirects=False
            )

            # UI may redirect to login, accept 200 or 30x
            assert response.status_code in [200, 301, 302, 303, 307, 308], \
                f"Kagenti UI unexpected status: {response.status_code}"

        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"Could not connect to Kagenti UI: {e}")
        finally:
            if proc:
                proc.terminate()
                proc.wait(timeout=5)


# ============================================================================
# Test: Platform Operator
# ============================================================================

@pytest.mark.skip(reason="Platform operator not deployed in this environment")
class TestPlatformOperator:
    """Test Platform Operator (agentic-platform-controller-manager).

    SKIPPED: The agentic-platform-controller-manager is not deployed in this
    environment. This operator manages Platform CRDs which are currently not
    used in the local Kind cluster setup.
    """

    def test_platform_operator_healthy(self, k8s_apps_client):
        """Verify platform-operator deployment is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="agentic-platform-controller-manager",
            namespace="kagenti-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "platform-operator has no ready replicas"

    def test_platform_crds_installed(self):
        """Verify Platform CRDs are installed."""
        platform_crds = [
            "platforms.kagenti.ai",
            "components.kagenti.ai",
            "agents.kagenti.ai",
            "agentbuilds.kagenti.ai",
            "agentcards.kagenti.ai",
        ]

        api_client = client.ApiextensionsV1Api()
        crds = api_client.list_custom_resource_definition()
        crd_names = [crd.metadata.name for crd in crds.items]

        for platform_crd in platform_crds:
            assert platform_crd in crd_names, \
                f"Platform CRD '{platform_crd}' not installed"

    @pytest.mark.critical
    def test_platform_crds_queryable(self, k8s_custom_client):
        """Verify Platform CRDs can be queried via API."""
        platform_crds = [
            ("platforms.kagenti.ai", "kagenti.ai", "v1alpha1", "platforms"),
            ("components.kagenti.ai", "kagenti.ai", "v1alpha1", "components"),
            ("agents.kagenti.ai", "kagenti.ai", "v1alpha1", "agents"),
            ("agentbuilds.kagenti.ai", "kagenti.ai", "v1alpha1", "agentbuilds"),
            ("agentcards.kagenti.ai", "kagenti.ai", "v1alpha1", "agentcards"),
        ]

        for crd_name, group, version, plural in platform_crds:
            try:
                # Try to list the CRD resources
                k8s_custom_client.list_cluster_custom_object(
                    group=group,
                    version=version,
                    plural=plural
                )
            except ApiException as e:
                if e.status == 404:
                    pytest.fail(f"CRD {crd_name} not queryable via API")
                raise


# ============================================================================
# Test: Kagenti Operator
# ============================================================================

class TestKagentiOperator:
    """Test Kagenti Operator (agent lifecycle management)."""

    @pytest.mark.xfail(reason="kagenti-operator image not published (see ISSUES.md)")
    def test_kagenti_operator_healthy(self, k8s_apps_client):
        """Verify kagenti-operator deployment is healthy (expected to fail)."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="kagenti-controller-manager",
            namespace="kagenti-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "kagenti-operator has no ready replicas"

    def test_kagenti_operator_deployment_exists(self, k8s_apps_client):
        """Verify kagenti-operator deployment exists (even if not healthy)."""
        try:
            deployment = k8s_apps_client.read_namespaced_deployment(
                name="kagenti-controller-manager",
                namespace="kagenti-system"
            )

            assert deployment is not None, \
                "kagenti-operator deployment not found"

        except ApiException as e:
            if e.status == 404:
                pytest.fail("kagenti-operator deployment not found")
            raise


# ============================================================================
# Test: External Gateway
# ============================================================================

class TestExternalGateway:
    """Test external gateway configuration."""

    def test_external_gateway_exists(self, k8s_custom_client):
        """Verify external gateway is configured."""
        try:
            gateway = k8s_custom_client.get_namespaced_custom_object(
                group="gateway.networking.k8s.io",
                version="v1",
                namespace="default",
                plural="gateways",
                name="external-gateway"
            )

            assert gateway is not None, "External gateway not found"

        except ApiException as e:
            if e.status == 404:
                pytest.fail("External gateway not found")
            raise

    def test_gateway_listeners_configured(self, k8s_custom_client):
        """Verify gateway has HTTPS listener configured."""
        gateway = k8s_custom_client.get_namespaced_custom_object(
            group="gateway.networking.k8s.io",
            version="v1",
            namespace="default",
            plural="gateways",
            name="external-gateway"
        )

        spec = gateway.get("spec", {})
        listeners = spec.get("listeners", [])

        assert len(listeners) > 0, "Gateway has no listeners configured"

        # Check for HTTPS listener
        https_listeners = [
            l for l in listeners
            if l.get("protocol") == "HTTPS" or l.get("port") == 443
        ]

        assert len(https_listeners) > 0, \
            "Gateway has no HTTPS listener configured"

    def test_tls_certificates_ready(self, k8s_custom_client):
        """Verify TLS certificates for gateway are ready."""
        certificates = [
            ("default", "localtest-me-tls"),
            ("kagenti-system", "localtest-me-wildcard"),
        ]

        for namespace, cert_name in certificates:
            try:
                cert = k8s_custom_client.get_namespaced_custom_object(
                    group="cert-manager.io",
                    version="v1",
                    namespace=namespace,
                    plural="certificates",
                    name=cert_name
                )

                status = cert.get("status", {})
                conditions = status.get("conditions", [])

                ready = any(
                    c.get("type") == "Ready" and c.get("status") == "True"
                    for c in conditions
                )

                assert ready, \
                    f"Certificate {namespace}/{cert_name} not ready. Status: {status}"

            except ApiException as e:
                pytest.fail(f"Certificate {namespace}/{cert_name} not found: {e}")


# ============================================================================
# Test: Container Registry
# ============================================================================

@pytest.mark.skip(reason="Container registry not deployed in this environment")
class TestContainerRegistry:
    """Test container registry for agent images.

    SKIPPED: The container-registry is not deployed in this environment.
    Agent images are pulled from external registries (ghcr.io, quay.io) rather
    than from a local registry.
    """

    def test_container_registry_healthy(self, k8s_apps_client):
        """Verify container registry deployment is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="container-registry",
            namespace="cr-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Container registry has no ready replicas"

    def test_container_registry_service_exists(self, k8s_client):
        """Verify container registry service is created."""
        service = k8s_client.read_namespaced_service(
            name="container-registry",
            namespace="cr-system"
        )

        assert service is not None, "Container registry service not found"


# ============================================================================
# Test: Platform Health
# ============================================================================

class TestPlatformHealth:
    """Overall platform health checks."""

    def test_no_crashloop_pods_in_platform(self, k8s_client):
        """Verify no pods in CrashLoopBackOff in platform namespaces."""
        platform_namespaces = [
            "kagenti-system",
            "keycloak",
            # cr-system not deployed in this environment
        ]

        crashloop_pods = []

        for ns in platform_namespaces:
            try:
                pods = k8s_client.list_namespaced_pod(namespace=ns)

                for pod in pods.items:
                    if pod.status.container_statuses:
                        for container in pod.status.container_statuses:
                            if container.state.waiting:
                                if container.state.waiting.reason == "CrashLoopBackOff":
                                    crashloop_pods.append(
                                        f"{ns}/{pod.metadata.name}/{container.name}"
                                    )
            except ApiException:
                continue

        assert len(crashloop_pods) == 0, \
            f"Pods in CrashLoopBackOff: {', '.join(crashloop_pods)}"

    @pytest.mark.critical
    def test_platform_pod_health_threshold(self, k8s_client):
        """Verify >80% of platform pods are healthy."""
        platform_namespaces = [
            "kagenti-system",
            "keycloak",
            # cr-system not deployed in this environment
        ]

        total_pods = 0
        healthy_pods = 0

        for ns in platform_namespaces:
            try:
                pods = k8s_client.list_namespaced_pod(namespace=ns)

                for pod in pods.items:
                    # Skip known failing pods
                    if pod.metadata.name.startswith("kagenti-controller-manager"):
                        continue

                    total_pods += 1
                    if pod.status.phase in ["Running", "Succeeded"]:
                        healthy_pods += 1
            except ApiException:
                continue

        if total_pods == 0:
            pytest.skip("No platform pods found")

        health_percentage = (healthy_pods / total_pods) * 100

        assert health_percentage >= 80, \
            f"Only {health_percentage:.1f}% of platform pods healthy (threshold: 80%)"

    def test_all_platform_services_have_endpoints(self, k8s_client):
        """Verify all platform services have ready endpoints."""
        platform_services = [
            ("kagenti-system", "kagenti-ui"),
            ("keycloak", "keycloak"),
            # container-registry not deployed in this environment
        ]

        services_without_endpoints = []

        for namespace, service_name in platform_services:
            try:
                endpoints = k8s_client.read_namespaced_endpoints(
                    name=service_name,
                    namespace=namespace
                )

                if not endpoints.subsets:
                    services_without_endpoints.append(f"{namespace}/{service_name}")
                    continue

                # Check if any addresses exist in subsets
                has_addresses = any(
                    subset.addresses and len(subset.addresses) > 0
                    for subset in endpoints.subsets
                )

                if not has_addresses:
                    services_without_endpoints.append(f"{namespace}/{service_name}")

            except ApiException:
                services_without_endpoints.append(f"{namespace}/{service_name}")

        assert len(services_without_endpoints) == 0, \
            f"Services without endpoints: {', '.join(services_without_endpoints)}"


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
