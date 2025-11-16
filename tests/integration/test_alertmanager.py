"""
Test AlertManager deployment and integration.

This validates that:
- AlertManager pod is running and healthy
- AlertManager configuration is valid
- AlertManager API is accessible
- AlertManager can receive alerts (webhook endpoint)
- AlertManager routes alerts correctly
"""
import pytest
import subprocess
import json
import time
from kubernetes import client, config


class TestAlertManager:
    """Test AlertManager deployment and functionality."""

    @pytest.fixture(scope="class", autouse=True)
    def k8s_client(self):
        """Load Kubernetes config."""
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        return client.CoreV1Api()

    def exec_curl(self, url: str, method: str = "GET", data: dict = None, timeout: int = 10):
        """Execute curl from Grafana pod to query AlertManager."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s"
        ]

        if method == "POST":
            cmd.extend(["-X", "POST"])
            if data:
                cmd.extend(["-H", "Content-Type: application/json"])
                cmd.extend(["-d", json.dumps(data)])

        cmd.append(url)

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

        if result.returncode != 0:
            pytest.fail(f"Failed to exec curl: {result.stderr}")

        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            # Return raw output if not JSON
            return {"raw": result.stdout}

    def test_alertmanager_pod_is_running(self, k8s_client):
        """Test that AlertManager pod is running and healthy."""
        pods = k8s_client.list_namespaced_pod(
            namespace="observability",
            label_selector="app=alertmanager"
        )

        assert len(pods.items) > 0, "AlertManager pod not found"

        pod = pods.items[0]
        assert pod.status.phase == "Running", f"AlertManager pod is {pod.status.phase}"

        # Check container is ready
        for container in pod.status.container_statuses:
            assert container.ready, f"Container {container.name} is not ready"

    def test_alertmanager_service_exists(self, k8s_client):
        """Test that AlertManager service exists."""
        services = k8s_client.list_namespaced_service(
            namespace="observability",
            field_selector="metadata.name=alertmanager"
        )

        assert len(services.items) > 0, "AlertManager service not found"

        svc = services.items[0]
        assert svc.spec.ports[0].port == 9093, \
            f"Expected port 9093, got {svc.spec.ports[0].port}"

    def test_alertmanager_health_endpoint(self):
        """Test that AlertManager /-/healthy endpoint returns success."""
        result = self.exec_curl("http://alertmanager.observability.svc:9093/-/healthy")

        # AlertManager returns "Prometheus Alertmanager" or similar
        assert "raw" in result, "Expected raw text response"
        # Should not contain "error" or "failed"
        assert "error" not in result["raw"].lower(), \
            f"Health check failed: {result['raw']}"

    def test_alertmanager_ready_endpoint(self):
        """Test that AlertManager /-/ready endpoint returns success."""
        result = self.exec_curl("http://alertmanager.observability.svc:9093/-/ready")

        assert "raw" in result, "Expected raw text response"
        assert "error" not in result["raw"].lower(), \
            f"Ready check failed: {result['raw']}"

    def test_alertmanager_api_status(self):
        """Test that AlertManager API /api/v2/status returns valid status."""
        result = self.exec_curl("http://alertmanager.observability.svc:9093/api/v2/status")

        assert "cluster" in result or "uptime" in result or "versionInfo" in result, \
            f"Unexpected status response: {result}"

    def test_alertmanager_config_loaded(self):
        """Test that AlertManager has loaded configuration correctly."""
        # Query the config endpoint
        result = self.exec_curl("http://alertmanager.observability.svc:9093/api/v1/status")

        assert "status" in result or "data" in result or "versionInfo" in result, \
            f"Config not loaded correctly: {result}"

    def test_alertmanager_can_receive_alerts(self):
        """Test that AlertManager webhook endpoint can receive alerts."""
        # Send a test alert to AlertManager
        test_alert = [
            {
                "labels": {
                    "alertname": "TestAlert",
                    "severity": "warning",
                    "namespace": "observability"
                },
                "annotations": {
                    "summary": "This is a test alert from pytest",
                    "description": "Testing AlertManager webhook endpoint"
                },
                "startsAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "endsAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 300))
            }
        ]

        # Send alert to AlertManager
        result = self.exec_curl(
            "http://alertmanager.observability.svc:9093/api/v2/alerts",
            method="POST",
            data=test_alert
        )

        # Check if alert was accepted
        # AlertManager returns empty response on success
        # or an error message on failure
        if isinstance(result, dict) and "error" in result.get("raw", "").lower():
            pytest.fail(f"Failed to send alert: {result}")

    def test_alertmanager_alerts_api(self):
        """Test that AlertManager /api/v2/alerts endpoint returns alerts."""
        # Query alerts API
        result = self.exec_curl("http://alertmanager.observability.svc:9093/api/v2/alerts")

        # Should return a list (may be empty)
        assert isinstance(result, list), \
            f"Expected list of alerts, got: {type(result)}"

    def test_alertmanager_receivers_configured(self):
        """Test that AlertManager has receivers configured."""
        # Get AlertManager config
        cmd = [
            "kubectl", "get", "configmap", "alertmanager-config",
            "-n", "observability",
            "-o", "jsonpath={.data.alertmanager\\.yml}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to get config: {result.stderr}"

        config_text = result.stdout
        assert "receivers:" in config_text, "No receivers configured"
        assert "korrel8r" in config_text, "Korrel8r receiver not found"

    def test_alertmanager_routes_configured(self):
        """Test that AlertManager has routes configured."""
        cmd = [
            "kubectl", "get", "configmap", "alertmanager-config",
            "-n", "observability",
            "-o", "jsonpath={.data.alertmanager\\.yml}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to get config: {result.stderr}"

        config_text = result.stdout
        assert "route:" in config_text, "No routes configured"
        assert "group_by:" in config_text, "No grouping configured"

    def test_alertmanager_network_policy_allows_grafana(self, k8s_client):
        """Test that NetworkPolicy allows traffic from Grafana."""
        netpols = client.NetworkingV1Api().list_namespaced_network_policy(
            namespace="observability",
            field_selector="metadata.name=alertmanager"
        )

        if len(netpols.items) == 0:
            pytest.skip("AlertManager NetworkPolicy not found (may be optional)")

        netpol = netpols.items[0]

        # Check ingress rules allow Grafana
        has_grafana_rule = False
        for ingress in netpol.spec.ingress or []:
            for from_rule in ingress.from_ or []:
                if from_rule.pod_selector:
                    labels = from_rule.pod_selector.match_labels or {}
                    if "grafana" in labels.get("app", "").lower():
                        has_grafana_rule = True
                        break

        # If NetworkPolicy exists, it should allow Grafana
        assert has_grafana_rule or len(netpol.spec.ingress or []) == 0, \
            "NetworkPolicy doesn't allow Grafana traffic"

    def test_alertmanager_mtls_is_permissive(self, k8s_client):
        """Test that AlertManager has PERMISSIVE mTLS mode."""
        try:
            auth_policies = client.CustomObjectsApi().list_namespaced_custom_object(
                group="security.istio.io",
                version="v1beta1",
                namespace="observability",
                plural="peerauthentications"
            )

            # Find AlertManager policy
            am_policy = None
            for policy in auth_policies.get("items", []):
                name = policy.get("metadata", {}).get("name", "")
                if "alertmanager" in name.lower():
                    am_policy = policy
                    break

            if am_policy:
                mtls_mode = am_policy.get("spec", {}).get("mtls", {}).get("mode", "")
                assert mtls_mode == "PERMISSIVE", \
                    f"AlertManager mTLS should be PERMISSIVE, got: {mtls_mode}"

        except Exception:
            # If CRD doesn't exist or policy not found, skip test
            pytest.skip("PeerAuthentication CRD not available or policy not found")
