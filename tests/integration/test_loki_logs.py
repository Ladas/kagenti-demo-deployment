"""
Test Loki log ingestion and Grafana datasource configuration.

This validates that:
- Grafana Alloy is collecting logs from pods
- Loki is ingesting and storing logs
- Grafana can query logs from Loki
"""
import pytest
import subprocess
import json
import time
from kubernetes import client, config


class TestLokiLogs:
    """Test Loki log collection and querying."""

    @pytest.fixture(scope="class", autouse=True)
    def k8s_client(self):
        """Load Kubernetes config."""
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        return client.CoreV1Api()

    def query_loki(self, query: str, timeout: int = 10):
        """
        Query Loki via kubectl exec from Grafana pod.

        Returns:
            dict: Loki query result
        """
        import urllib.parse

        encoded_query = urllib.parse.quote(query)

        # Query for last hour of logs
        end_ns = int(time.time() * 1e9)
        start_ns = end_ns - (3600 * 1e9)  # 1 hour ago

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s",
            f"http://loki-query-frontend.observability.svc:3100/loki/api/v1/query_range?query={encoded_query}&start={int(start_ns)}&end={int(end_ns)}&limit=100"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

        if result.returncode != 0:
            pytest.fail(f"Failed to query Loki: {result.stderr}")

        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse Loki response: {e}\nOutput: {result.stdout}")

    def test_loki_is_running(self, k8s_client):
        """Test that Loki pod is running."""
        pods = k8s_client.list_namespaced_pod(
            namespace="observability",
            label_selector="app=loki"
        )

        assert len(pods.items) > 0, "Loki pod not found"

        pod = pods.items[0]
        assert pod.status.phase == "Running", f"Loki pod is {pod.status.phase}"

        # Check container is ready
        for container in pod.status.container_statuses:
            assert container.ready, f"Container {container.name} is not ready"

    def test_grafana_alloy_is_running(self, k8s_client):
        """Test that Grafana Alloy DaemonSet is running."""
        daemonsets = client.AppsV1Api().list_namespaced_daemon_set(
            namespace="observability",
            label_selector="app.kubernetes.io/name=alloy"
        )

        assert len(daemonsets.items) > 0, "Grafana Alloy DaemonSet not found"

        ds = daemonsets.items[0]
        assert ds.status.number_ready > 0, "No Grafana Alloy pods are ready"

    def test_loki_ready_endpoint(self):
        """Test that Loki /ready endpoint returns 200."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "http://loki-query-frontend.observability.svc:3100/ready"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"
        assert result.stdout == "200", f"Loki /ready returned {result.stdout}"

    def test_loki_has_log_streams(self):
        """Test that Loki has log streams (Grafana Alloy is sending logs)."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s",
            "http://loki-query-frontend.observability.svc:3100/loki/api/v1/label/namespace/values"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"

        response = json.loads(result.stdout)
        assert response["status"] == "success", f"Loki query failed: {response}"

        namespaces = response.get("data", [])
        assert len(namespaces) > 0, "No log streams found in Loki"

        # Verify we have logs from observability namespace at least
        assert "observability" in namespaces or "kube-system" in namespaces, \
            f"No logs from observability or kube-system. Found: {namespaces}"

    def test_loki_query_observability_logs(self):
        """Test querying logs from observability namespace."""
        result = self.query_loki('{namespace="observability"}')

        assert result["status"] == "success", f"Loki query failed: {result}"

        # Check if we have log entries
        streams = result.get("data", {}).get("result", [])
        assert len(streams) > 0, "No log streams returned for observability namespace"

        # Verify we have actual log entries
        total_entries = sum(len(stream.get("values", [])) for stream in streams)
        assert total_entries > 0, "No log entries found in observability namespace"

    def test_loki_query_with_pod_selector(self):
        """Test querying logs for a specific pod."""
        result = self.query_loki('{namespace="observability", app="grafana"}')

        assert result["status"] == "success", f"Loki query failed: {result}"

        streams = result.get("data", {}).get("result", [])
        # Grafana should have logs
        if len(streams) == 0:
            # Try prometheus instead
            result = self.query_loki('{namespace="observability", app="prometheus"}')
            assert result["status"] == "success"
            streams = result.get("data", {}).get("result", [])

        assert len(streams) > 0, \
            "No log streams found for observability pods (tried grafana and prometheus)"

    def test_grafana_loki_datasource_configured(self):
        """Test that Grafana has Loki datasource configured."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            "http://localhost:3000/api/datasources"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to query Grafana: {result.stderr}"

        datasources = json.loads(result.stdout)

        # Find Loki datasource
        loki_ds = next((ds for ds in datasources if ds.get("type") == "loki"), None)
        assert loki_ds is not None, "Loki datasource not found in Grafana"

        # Verify URL
        assert "loki" in loki_ds.get("url", "").lower(), \
            f"Loki datasource URL looks wrong: {loki_ds.get('url')}"

    def test_grafana_can_query_loki(self):
        """Test that Grafana can successfully query Loki."""
        # This tests the full integration: Grafana -> Loki -> Grafana Alloy
        # Use datasource ID instead of UID (more reliable)
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            "http://localhost:3000/api/datasources/proxy/3/loki/api/v1/label/namespace/values"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to query Grafana: {result.stderr}"

        try:
            response = json.loads(result.stdout)

            # Check if it's an error response
            if "message" in response:
                pytest.fail(f"Grafana returned error: {response['message']}")

            # Should have success status and data
            assert response.get("status") == "success", f"Query failed: {response}"
            assert "data" in response, f"No data in response: {response}"

            # Should have namespace labels
            namespaces = response.get("data", [])
            assert len(namespaces) > 0, "No namespaces found in Loki"

        except json.JSONDecodeError:
            # If not JSON, it might be a list directly
            assert "observability" in result.stdout or "kube-system" in result.stdout, \
                f"Expected namespace labels in response: {result.stdout}"

    def test_loki_logs_have_metadata(self):
        """Test that logs have proper Kubernetes metadata labels."""
        result = self.query_loki('{namespace="observability"}')

        assert result["status"] == "success", f"Loki query failed: {result}"

        streams = result.get("data", {}).get("result", [])
        assert len(streams) > 0, "No log streams returned"

        # Check that streams have expected labels
        stream = streams[0]
        labels = stream.get("stream", {})

        # Should have at least namespace label
        assert "namespace" in labels, f"Stream missing namespace label: {labels}"

        # Should have pod or container label
        has_pod_info = "pod" in labels or "container" in labels or "app" in labels
        assert has_pod_info, f"Stream missing pod/container/app labels: {labels}"
