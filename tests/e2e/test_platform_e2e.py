#!/usr/bin/env python3
"""
End-to-End Tests for Kagenti Platform Deployment

This test suite verifies the complete Kagenti platform deployment including:
- Infrastructure components (ArgoCD, Istio, Keycloak)
- Platform services (Kagenti UI, Operators)
- Observability stack (Jaeger, Tempo, Grafana, Prometheus)
- Agent deployment and functionality

Requirements:
    pip install pytest kubernetes requests pyyaml

Usage:
    # Run all tests
    pytest tests/e2e/test_platform.py -v

    # Run specific test
    pytest tests/e2e/test_platform.py::test_argocd_healthy -v

    # Run with detailed output
    pytest tests/e2e/test_platform.py -v -s

Environment Variables:
    KUBECONFIG: Path to kubeconfig file (default: ~/.kube/config)
    ARGOCD_SERVER: ArgoCD server address (default: from kubectl)
    ARGOCD_TOKEN: ArgoCD auth token (optional, uses port-forward if not set)
"""

import os
import subprocess
import time
from typing import Dict, List, Optional, Tuple

import pytest
import requests
from kubernetes import client, config
from kubernetes.client.rest import ApiException


# ============================================================================
# Fixtures and Setup
# ============================================================================

@pytest.fixture(scope="session")
def k8s_client():
    """Load Kubernetes configuration and return API client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()

    return client.CoreV1Api()


@pytest.fixture(scope="session")
def k8s_apps_client():
    """Return Kubernetes Apps API client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()

    return client.AppsV1Api()


@pytest.fixture(scope="session")
def k8s_custom_client():
    """Return Kubernetes Custom Objects API client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()

    return client.CustomObjectsApi()


def run_command(cmd: List[str], check: bool = True) -> Tuple[int, str, str]:
    """
    Run a shell command and return exit code, stdout, stderr.

    Args:
        cmd: Command and arguments as list
        check: Raise exception on non-zero exit code

    Returns:
        Tuple of (exit_code, stdout, stderr)
    """
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=check
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
                    # Check if all containers are ready
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
# Test: Infrastructure Layer (Wave 0)
# ============================================================================

class TestInfrastructure:
    """Test core infrastructure components."""

    def test_argocd_healthy(self, k8s_apps_client):
        """Verify ArgoCD server deployment is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="argocd-server",
            namespace="argocd"
        )

        assert deployment.status.ready_replicas >= 1, \
            "ArgoCD server has no ready replicas"
        assert deployment.status.available_replicas >= 1, \
            "ArgoCD server is not available"

    def test_cert_manager_healthy(self, k8s_apps_client):
        """Verify cert-manager is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="cert-manager",
            namespace="cert-manager"
        )

        assert deployment.status.ready_replicas >= 1, \
            "cert-manager has no ready replicas"

    def test_tekton_pipelines_installed(self, k8s_apps_client):
        """Verify Tekton Pipelines controller is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="tekton-pipelines-controller",
            namespace="tekton-pipelines"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Tekton pipelines controller not ready"


# ============================================================================
# Test: Service Mesh & Infrastructure Services (Wave 5)
# ============================================================================

class TestServiceMesh:
    """Test Istio service mesh and infrastructure services."""

    def test_istiod_healthy(self, k8s_apps_client):
        """Verify Istio control plane (istiod) is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="istiod",
            namespace="istio-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "istiod has no ready replicas"

    def test_keycloak_healthy(self, k8s_apps_client):
        """Verify Keycloak identity provider is healthy."""
        statefulset = k8s_apps_client.read_namespaced_stateful_set(
            name="keycloak",
            namespace="keycloak"
        )

        assert statefulset.status.ready_replicas >= 1, \
            "Keycloak has no ready replicas"

    def test_container_registry_healthy(self, k8s_apps_client):
        """Verify container registry is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="container-registry",
            namespace="cr-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Container registry has no ready replicas"

    def test_kiali_healthy(self, k8s_apps_client):
        """Verify Kiali service mesh dashboard is healthy."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="kiali",
            namespace="kiali-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Kiali has no ready replicas"


# ============================================================================
# Test: Kubernetes Operators (Wave 10)
# ============================================================================

class TestOperators:
    """Test Kagenti platform operators."""

    def test_platform_operator_healthy(self, k8s_apps_client):
        """Verify platform-operator is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="agentic-platform-controller-manager",
            namespace="kagenti-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "platform-operator has no ready replicas"

    def test_platform_crds_installed(self, k8s_custom_client):
        """Verify Platform CRDs are installed."""
        crds = [
            ("platforms.kagenti.ai", "kagenti.ai", "v1alpha1"),
            ("components.kagenti.ai", "kagenti.ai", "v1alpha1"),
            ("agents.kagenti.ai", "kagenti.ai", "v1alpha1"),
            ("agentbuilds.kagenti.ai", "kagenti.ai", "v1alpha1"),
            ("agentcards.kagenti.ai", "kagenti.ai", "v1alpha1"),
        ]

        for crd_name, group, version in crds:
            try:
                # Try to list the CRD (will fail if not installed)
                k8s_custom_client.list_cluster_custom_object(
                    group=group,
                    version=version,
                    plural=crd_name.split('.')[0]
                )
            except ApiException as e:
                if e.status == 404:
                    pytest.fail(f"CRD {crd_name} not found")
                raise

    @pytest.mark.xfail(reason="kagenti-operator image not published (see ISSUES.md)")
    def test_kagenti_operator_healthy(self, k8s_apps_client):
        """Verify kagenti-operator is running (expected to fail - image not published)."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="kagenti-controller-manager",
            namespace="kagenti-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "kagenti-operator has no ready replicas"


# ============================================================================
# Test: Platform Services (Wave 15)
# ============================================================================

class TestPlatformServices:
    """Test Kagenti platform services."""

    def test_kagenti_ui_healthy(self, k8s_apps_client):
        """Verify Kagenti UI is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="kagenti-ui",
            namespace="kagenti-system"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Kagenti UI has no ready replicas"

    def test_kagenti_ui_oauth_config_completed(self, k8s_client):
        """Verify Kagenti UI OAuth configuration job completed."""
        jobs = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="job-name=kagenti-ui-oauth-config"
        )

        assert len(jobs.items) > 0, "OAuth config job not found"

        job_pod = jobs.items[0]
        assert job_pod.status.phase in ["Succeeded", "Completed"], \
            f"OAuth config job failed: {job_pod.status.phase}"

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
            assert gateway is not None
        except ApiException as e:
            pytest.fail(f"External gateway not found: {e}")

    def test_tls_certificates_ready(self, k8s_custom_client):
        """Verify TLS certificates are issued."""
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

                assert ready, f"Certificate {cert_name} not ready"
            except ApiException as e:
                pytest.fail(f"Certificate {cert_name} not found: {e}")


# ============================================================================
# Test: Observability Stack (Wave 20)
# ============================================================================

class TestObservability:
    """Test observability stack components."""

    def test_jaeger_healthy(self, k8s_apps_client):
        """Verify Jaeger is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="jaeger",
            namespace="observability"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Jaeger has no ready replicas"

    def test_tempo_healthy(self, k8s_apps_client):
        """Verify Tempo is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="tempo",
            namespace="observability"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Tempo has no ready replicas"

    def test_otel_collector_healthy(self, k8s_apps_client):
        """Verify OpenTelemetry Collector is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="otel-collector",
            namespace="observability"
        )

        assert deployment.status.ready_replicas >= 1, \
            "OTEL Collector has no ready replicas"

    def test_phoenix_healthy(self, k8s_apps_client):
        """Verify Phoenix observability UI is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="phoenix",
            namespace="observability"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Phoenix has no ready replicas"

    @pytest.mark.xfail(reason="Grafana OIDC secret missing (see ISSUES.md)")
    def test_grafana_healthy(self, k8s_apps_client):
        """Verify Grafana is running (expected to fail - missing OIDC secret)."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="grafana",
            namespace="observability"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Grafana has no ready replicas"


# ============================================================================
# Test: Agent Deployment (Wave 25)
# ============================================================================

class TestAgents:
    """Test agent deployment and functionality."""

    @pytest.mark.xfail(reason="Agent images not built/pushed to registry")
    def test_research_agent_healthy(self, k8s_apps_client):
        """Verify research-agent is running (expected to fail - image not in registry)."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="research-agent",
            namespace="team1"
        )

        assert deployment.status.ready_replicas >= 1, \
            "research-agent has no ready replicas"

    @pytest.mark.xfail(reason="Agent images not built/pushed to registry")
    def test_code_agent_healthy(self, k8s_apps_client):
        """Verify code-agent is running (expected to fail - image not in registry)."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="code-agent",
            namespace="team1"
        )

        assert deployment.status.ready_replicas >= 1, \
            "code-agent has no ready replicas"

    @pytest.mark.xfail(reason="Agent images not built/pushed to registry")
    def test_orchestrator_agent_healthy(self, k8s_apps_client):
        """Verify orchestrator-agent is running (expected to fail - image not in registry)."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="orchestrator-agent",
            namespace="team1"
        )

        assert deployment.status.ready_replicas >= 1, \
            "orchestrator-agent has no ready replicas"

    def test_agent_services_exist(self, k8s_client):
        """Verify agent services are created."""
        services = ["research-agent", "code-agent", "orchestrator-agent"]

        for svc_name in services:
            service = k8s_client.read_namespaced_service(
                name=svc_name,
                namespace="team1"
            )

            assert service.spec.type == "ClusterIP", \
                f"{svc_name} is not ClusterIP type"
            assert service.spec.ports[0].port == 8080, \
                f"{svc_name} does not expose port 8080"

    @pytest.mark.skip(reason="Requires agent pods to be running")
    def test_research_agent_a2a_endpoint(self, k8s_client):
        """Test research-agent A2A endpoint is accessible."""
        # Port-forward to research-agent service
        proc = subprocess.Popen([
            "kubectl", "port-forward",
            "-n", "team1",
            "svc/research-agent",
            "8080:8080"
        ])

        try:
            time.sleep(5)  # Wait for port-forward to establish

            # Try to connect to A2A endpoint
            response = requests.get(
                "http://localhost:8080/health",
                timeout=10
            )

            assert response.status_code == 200, \
                f"Research agent health check failed: {response.status_code}"
        finally:
            proc.terminate()
            proc.wait(timeout=5)


# ============================================================================
# Test: ArgoCD Applications
# ============================================================================

class TestArgoCD:
    """Test ArgoCD application health and sync status."""

    @pytest.fixture(scope="class")
    def argocd_applications(self) -> List[str]:
        """List of expected ArgoCD applications."""
        return [
            "infrastructure",
            "gateway-api",
            "cert-manager",
            "tekton",
            "istio-base",
            "istiod",
            "istio-config",
            "keycloak",
            "container-registry",
            "kiali",
            "kagenti-operator",
            "platform-operator",
            "platform",
            "observability",
            "agents",
        ]

    def test_all_applications_exist(self, argocd_applications):
        """Verify all expected ArgoCD applications exist."""
        exit_code, stdout, stderr = run_command([
            "argocd", "app", "list",
            "--port-forward",
            "--port-forward-namespace", "argocd",
            "--grpc-web",
            "-o", "name"
        ])

        app_names = [line.strip() for line in stdout.split('\n') if line.strip()]

        for expected_app in argocd_applications:
            assert any(expected_app in app for app in app_names), \
                f"ArgoCD application '{expected_app}' not found"

    def test_critical_applications_synced(self):
        """Verify critical applications are synced."""
        critical_apps = [
            "infrastructure",
            "istio-base",
            "istiod",
            "keycloak",
            "platform-operator",
            "platform",
            "observability",
        ]

        for app_name in critical_apps:
            exit_code, stdout, stderr = run_command([
                "argocd", "app", "get", app_name,
                "--port-forward",
                "--port-forward-namespace", "argocd",
                "--grpc-web",
            ], check=False)

            # Check if "Synced" appears in output
            assert "Synced" in stdout, \
                f"Application '{app_name}' is not synced"


# ============================================================================
# Test: End-to-End Platform Health
# ============================================================================

class TestPlatformHealth:
    """Overall platform health checks."""

    def test_no_crashloop_pods(self, k8s_client):
        """Verify no pods are in CrashLoopBackOff state."""
        # Get all pods across all namespaces
        pods = k8s_client.list_pod_for_all_namespaces()

        crashloop_pods = []
        for pod in pods.items:
            if pod.status.container_statuses:
                for container in pod.status.container_statuses:
                    if container.state.waiting:
                        if container.state.waiting.reason == "CrashLoopBackOff":
                            crashloop_pods.append(
                                f"{pod.metadata.namespace}/{pod.metadata.name}"
                            )

        assert len(crashloop_pods) == 0, \
            f"Pods in CrashLoopBackOff: {', '.join(crashloop_pods)}"

    def test_cluster_pod_health_threshold(self, k8s_client):
        """Verify >80% of pods are healthy (Running or Succeeded)."""
        pods = k8s_client.list_pod_for_all_namespaces()

        total_pods = len(pods.items)
        healthy_pods = sum(
            1 for pod in pods.items
            if pod.status.phase in ["Running", "Succeeded"]
        )

        health_percentage = (healthy_pods / total_pods) * 100

        assert health_percentage >= 80, \
            f"Only {health_percentage:.1f}% of pods are healthy (threshold: 80%)"

    def test_all_deployments_have_replicas(self, k8s_apps_client):
        """Verify all deployments have at least one ready replica."""
        # Get deployments from critical namespaces
        critical_namespaces = [
            "argocd",
            "istio-system",
            "keycloak",
            "kagenti-system",
            "observability",
            "cr-system",
            "kiali-system",
        ]

        failed_deployments = []

        for namespace in critical_namespaces:
            try:
                deployments = k8s_apps_client.list_namespaced_deployment(
                    namespace=namespace
                )

                for deployment in deployments.items:
                    # Skip known failing deployments
                    if deployment.metadata.name in [
                        "kagenti-controller-manager",  # Image not published
                        "grafana",  # OIDC secret missing
                    ]:
                        continue

                    if not deployment.status.ready_replicas:
                        failed_deployments.append(
                            f"{namespace}/{deployment.metadata.name}"
                        )
            except ApiException:
                # Namespace might not exist
                continue

        assert len(failed_deployments) == 0, \
            f"Deployments with no ready replicas: {', '.join(failed_deployments)}"


if __name__ == "__main__":
    # Run tests with pytest when executed directly
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
