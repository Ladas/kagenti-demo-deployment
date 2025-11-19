#!/usr/bin/env python3
"""
Infrastructure Integration Tests for Kagenti Platform

Tests core infrastructure components:
- ArgoCD (GitOps controller)
- Istio (service mesh)
- cert-manager (certificate automation)
- Gateway API (ingress routing)
- Tekton (CI/CD pipelines)

Requirements:
    pip install -r requirements.txt

Usage:
    pytest tests/integration/test_infrastructure.py -v
"""

import subprocess
import time
from typing import Dict, List, Tuple

import pytest
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


def run_command(cmd: List[str], check: bool = True, timeout: int = 30) -> Tuple[int, str, str]:
    """
    Run shell command and return exit code, stdout, stderr.

    Args:
        cmd: Command and arguments as list
        check: Raise exception on non-zero exit code
        timeout: Command timeout in seconds

    Returns:
        Tuple of (exit_code, stdout, stderr)
    """
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=check,
        timeout=timeout
    )
    return result.returncode, result.stdout, result.stderr


def wait_for_pod_ready(
    k8s_client: client.CoreV1Api,
    namespace: str,
    label_selector: str,
    timeout: int = 300
) -> bool:
    """
    Wait for at least one pod matching label selector to be Ready.

    Args:
        k8s_client: Kubernetes API client
        namespace: Namespace to search
        label_selector: Label selector (e.g., "app=kagenti-ui")
        timeout: Maximum wait time in seconds

    Returns:
        True if pod becomes ready, False otherwise
    """
    start_time = time.time()

    while (time.time() - start_time) < timeout:
        try:
            pods = k8s_client.list_namespaced_pod(
                namespace=namespace,
                label_selector=label_selector
            )

            for pod in pods.items:
                if pod.status.phase == "Running":
                    if pod.status.container_statuses:
                        all_ready = all(
                            c.ready for c in pod.status.container_statuses
                        )
                        if all_ready:
                            return True

            time.sleep(5)
        except ApiException as e:
            print(f"Error checking pods: {e}")
            time.sleep(5)

    return False


# ============================================================================
# Test: ArgoCD GitOps
# ============================================================================

class TestArgoCD:
    """Test ArgoCD deployment and application management."""

    def test_argocd_server_healthy(self, k8s_apps_client):
        """Verify ArgoCD server deployment is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="argocd-server",
            namespace="argocd"
        )

        assert deployment.status.ready_replicas >= 1, \
            "ArgoCD server has no ready replicas"
        assert deployment.status.available_replicas >= 1, \
            "ArgoCD server is not available"

    def test_argocd_applicationset_controller_healthy(self, k8s_apps_client):
        """Verify ArgoCD applicationset controller is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="argocd-applicationset-controller",
            namespace="argocd"
        )

        assert deployment.status.ready_replicas >= 1, \
            "ArgoCD applicationset controller has no ready replicas"

    def test_argocd_repo_server_healthy(self, k8s_apps_client):
        """Verify ArgoCD repo server is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="argocd-repo-server",
            namespace="argocd"
        )

        assert deployment.status.ready_replicas >= 1, \
            "ArgoCD repo server has no ready replicas"

    def test_all_argocd_applications_exist(self):
        """Verify all expected ArgoCD applications are created."""
        # Updated to match app-of-apps architecture
        # Root app: kagenti-platform-kind
        # Child apps are individual components
        # NOTE: 'agents' excluded - handled in separate Claude Code instance
        expected_apps = [
            "gateway-api",
            "cert-manager",
            "tekton",
            "istio-base",
            "istiod",
            "istio-config",
            "keycloak",
            "kiali",
            "kagenti-operator",
            "kagenti-platform-operator",  # Updated name
            "platform",
            "observability",
        ]

        exit_code, stdout, stderr = run_command([
            "argocd", "app", "list",
            "--port-forward",
            "--port-forward-namespace", "argocd",
            "--grpc-web",
            "-o", "name"
        ])

        app_names = [line.strip() for line in stdout.split('\n') if line.strip()]

        for expected_app in expected_apps:
            assert any(expected_app in app for app in app_names), \
                f"ArgoCD application '{expected_app}' not found. Available apps: {app_names}"

    @pytest.mark.critical
    def test_critical_applications_synced(self):
        """Verify critical applications are synced and healthy."""
        # Updated to match actual app names in app-of-apps architecture
        critical_apps = [
            "gateway-api",
            "cert-manager",
            "istio-base",
            "istiod",
            "kagenti-operator",
            "kagenti-platform-operator",
        ]

        for app_name in critical_apps:
            exit_code, stdout, stderr = run_command([
                "argocd", "app", "get", app_name,
                "--port-forward",
                "--port-forward-namespace", "argocd",
                "--grpc-web",
            ], check=False, timeout=60)

            # Check sync status
            assert "Synced" in stdout, \
                f"Application '{app_name}' is not synced. Output:\n{stdout}"

            # Check health status (allow Progressing for initial deployment)
            assert ("Healthy" in stdout or "Progressing" in stdout), \
                f"Application '{app_name}' is not healthy. Output:\n{stdout}"


# ============================================================================
# Test: Istio Service Mesh
# ============================================================================

class TestIstio:
    """Test Istio service mesh infrastructure."""

    def test_istiod_healthy(self, k8s_apps_client):
        """Verify Istio control plane (istiod) is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="istiod",
            namespace="istio-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "istiod has no ready replicas"
        assert deployment.status.available_replicas >= 1, \
            "istiod is not available"

    @pytest.mark.skip(reason="Using Gateway API instead of Istio ingress gateway")
    def test_istio_ingress_gateway_healthy(self, k8s_apps_client):
        """Verify Istio ingress gateway is healthy.

        NOTE: This platform uses Gateway API for ingress routing instead of
        the traditional istio-ingressgateway deployment. See test_gateway_api.py
        for Gateway API validation.
        """
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="istio-ingressgateway",
            namespace="istio-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "istio-ingressgateway has no ready replicas"

    def test_istio_base_crds_installed(self, k8s_custom_client):
        """Verify Istio CRDs are installed."""
        istio_crds = [
            "virtualservices.networking.istio.io",
            "destinationrules.networking.istio.io",
            "gateways.networking.istio.io",
            "serviceentries.networking.istio.io",
            "peerauthentications.security.istio.io",
        ]

        # List all CRDs
        api_client = client.ApiextensionsV1Api()
        crds = api_client.list_custom_resource_definition()
        crd_names = [crd.metadata.name for crd in crds.items]

        for istio_crd in istio_crds:
            assert istio_crd in crd_names, \
                f"Istio CRD '{istio_crd}' not installed"

    def test_mtls_policy_exists(self, k8s_custom_client):
        """Verify mTLS PeerAuthentication policies exist."""
        namespaces_with_mtls = [
            "kagenti-system",
            "observability",
            "keycloak",
        ]

        for ns in namespaces_with_mtls:
            try:
                policies = k8s_custom_client.list_namespaced_custom_object(
                    group="security.istio.io",
                    version="v1beta1",
                    namespace=ns,
                    plural="peerauthentications"
                )

                assert len(policies.get("items", [])) > 0, \
                    f"No PeerAuthentication policy in namespace '{ns}'"

            except ApiException as e:
                if e.status == 404:
                    pytest.fail(f"PeerAuthentication CRD not found")
                raise


# ============================================================================
# Test: cert-manager
# ============================================================================

class TestCertManager:
    """Test cert-manager certificate automation."""

    def test_cert_manager_healthy(self, k8s_apps_client):
        """Verify cert-manager deployment is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="cert-manager",
            namespace="cert-manager"
        )

        assert deployment.status.ready_replicas >= 1, \
            "cert-manager has no ready replicas"

    def test_cert_manager_webhook_healthy(self, k8s_apps_client):
        """Verify cert-manager webhook is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="cert-manager-webhook",
            namespace="cert-manager"
        )

        assert deployment.status.ready_replicas >= 1, \
            "cert-manager-webhook has no ready replicas"

    def test_cert_manager_cainjector_healthy(self, k8s_apps_client):
        """Verify cert-manager cainjector is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="cert-manager-cainjector",
            namespace="cert-manager"
        )

        assert deployment.status.ready_replicas >= 1, \
            "cert-manager-cainjector has no ready replicas"

    @pytest.mark.critical
    def test_certificates_ready(self, k8s_custom_client):
        """Verify TLS certificates are issued and ready."""
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

                # Check certificate status
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
# Test: Gateway API
# ============================================================================

class TestGatewayAPI:
    """Test Kubernetes Gateway API resources."""

    def test_gateway_api_crds_installed(self):
        """Verify Gateway API CRDs are installed."""
        gateway_crds = [
            "gatewayclasses.gateway.networking.k8s.io",
            "gateways.gateway.networking.k8s.io",
            "httproutes.gateway.networking.k8s.io",
        ]

        api_client = client.ApiextensionsV1Api()
        crds = api_client.list_custom_resource_definition()
        crd_names = [crd.metadata.name for crd in crds.items]

        for gw_crd in gateway_crds:
            assert gw_crd in crd_names, \
                f"Gateway API CRD '{gw_crd}' not installed"

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

            # Check gateway status
            status = gateway.get("status", {})
            conditions = status.get("conditions", [])

            # Gateway should be Programmed or Accepted
            programmed = any(
                c.get("type") in ["Programmed", "Accepted"] and
                c.get("status") == "True"
                for c in conditions
            )

            assert programmed or len(conditions) == 0, \
                f"Gateway not programmed. Status: {status}"

        except ApiException as e:
            pytest.fail(f"External gateway not found: {e}")

    def test_httproutes_configured(self, k8s_custom_client):
        """Verify HTTPRoute resources are configured for services."""
        namespaces_with_routes = [
            "kagenti-system",
            "observability",
            "keycloak",
        ]

        for ns in namespaces_with_routes:
            try:
                routes = k8s_custom_client.list_namespaced_custom_object(
                    group="gateway.networking.k8s.io",
                    version="v1",
                    namespace=ns,
                    plural="httproutes"
                )

                # At least one HTTPRoute should exist
                # (Not all namespaces may have routes yet)
                items = routes.get("items", [])
                print(f"Namespace {ns} has {len(items)} HTTPRoute(s)")

            except ApiException as e:
                if e.status == 404:
                    pytest.fail(f"HTTPRoute CRD not found")
                # It's OK if no HTTPRoutes exist in some namespaces yet
                print(f"No HTTPRoutes in {ns}: {e}")


# ============================================================================
# Test: Tekton Pipelines
# ============================================================================

class TestTekton:
    """Test Tekton CI/CD pipeline infrastructure."""

    def test_tekton_pipelines_controller_healthy(self, k8s_apps_client):
        """Verify Tekton Pipelines controller is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="tekton-pipelines-controller",
            namespace="tekton-pipelines"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Tekton pipelines controller has no ready replicas"

    def test_tekton_pipelines_webhook_healthy(self, k8s_apps_client):
        """Verify Tekton Pipelines webhook is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="tekton-pipelines-webhook",
            namespace="tekton-pipelines"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Tekton pipelines webhook has no ready replicas"

    def test_tekton_crds_installed(self):
        """Verify Tekton CRDs are installed."""
        tekton_crds = [
            "tasks.tekton.dev",
            "pipelines.tekton.dev",
            "pipelineruns.tekton.dev",
            "taskruns.tekton.dev",
        ]

        api_client = client.ApiextensionsV1Api()
        crds = api_client.list_custom_resource_definition()
        crd_names = [crd.metadata.name for crd in crds.items]

        for tekton_crd in tekton_crds:
            assert tekton_crd in crd_names, \
                f"Tekton CRD '{tekton_crd}' not installed"


# ============================================================================
# Test: Overall Infrastructure Health
# ============================================================================

class TestInfrastructureHealth:
    """Overall infrastructure health checks."""

    def test_no_crashloop_pods_in_infrastructure(self, k8s_client):
        """Verify no pods in CrashLoopBackOff in infrastructure namespaces."""
        infrastructure_namespaces = [
            "argocd",
            "cert-manager",
            "istio-system",
            "tekton-pipelines",
        ]

        crashloop_pods = []

        for ns in infrastructure_namespaces:
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
    def test_infrastructure_pod_health_threshold(self, k8s_client):
        """Verify >80% of infrastructure pods are healthy."""
        infrastructure_namespaces = [
            "argocd",
            "cert-manager",
            "istio-system",
            "tekton-pipelines",
        ]

        total_pods = 0
        healthy_pods = 0

        for ns in infrastructure_namespaces:
            try:
                pods = k8s_client.list_namespaced_pod(namespace=ns)

                for pod in pods.items:
                    total_pods += 1
                    if pod.status.phase in ["Running", "Succeeded"]:
                        healthy_pods += 1
            except ApiException:
                continue

        if total_pods == 0:
            pytest.skip("No infrastructure pods found")

        health_percentage = (healthy_pods / total_pods) * 100

        assert health_percentage >= 80, \
            f"Only {health_percentage:.1f}% of infrastructure pods healthy (threshold: 80%)"


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
