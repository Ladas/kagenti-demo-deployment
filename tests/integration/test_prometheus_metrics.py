"""
Test Prometheus metrics collection from kubelet and cAdvisor.

This validates that Prometheus is correctly scraping:
- kubelet metrics (node-level metrics)
- cAdvisor metrics (container CPU/memory usage)
"""
import pytest
import requests
import time
from kubernetes import client, config


class TestPrometheusMetrics:
    """Test Prometheus scraping of kubelet and cAdvisor metrics."""

    @pytest.fixture(scope="class", autouse=True)
    def k8s_client(self):
        """Load Kubernetes config."""
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        return client.CoreV1Api()

    def query_prometheus(self, query: str, timeout: int = 10):
        """
        Query Prometheus via kubectl exec from Grafana pod (has curl).

        Returns:
            dict: Prometheus query result
        """
        import subprocess
        import json
        import urllib.parse

        encoded_query = urllib.parse.quote(query)

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", f"http://prometheus.observability.svc:9090/api/v1/query?query={encoded_query}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

        if result.returncode != 0:
            pytest.fail(f"Failed to query Prometheus: {result.stderr}")

        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse Prometheus response: {e}\nOutput: {result.stdout}")

    def test_prometheus_is_running(self, k8s_client):
        """Test that Prometheus pod is running."""
        pods = k8s_client.list_namespaced_pod(
            namespace="observability",
            label_selector="app=prometheus"
        )

        assert len(pods.items) > 0, "Prometheus pod not found"

        pod = pods.items[0]
        assert pod.status.phase == "Running", f"Prometheus pod is {pod.status.phase}"

        # Check container is ready
        for container in pod.status.container_statuses:
            assert container.ready, f"Container {container.name} is not ready"

    def test_container_cpu_usage_metric_exists(self):
        """Test that container_cpu_usage_seconds_total metric exists."""
        result = self.query_prometheus("container_cpu_usage_seconds_total")

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "container_cpu_usage_seconds_total metric has no data"

    def test_machine_cpu_cores_metric_exists(self):
        """Test that machine_cpu_cores metric exists."""
        result = self.query_prometheus("machine_cpu_cores")

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "machine_cpu_cores metric has no data"

    def test_container_memory_working_set_bytes_exists(self):
        """Test that container_memory_working_set_bytes metric exists."""
        result = self.query_prometheus("container_memory_working_set_bytes")

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "container_memory_working_set_bytes metric has no data"

    def test_machine_memory_bytes_exists(self):
        """Test that machine_memory_bytes metric exists."""
        result = self.query_prometheus("machine_memory_bytes")

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "machine_memory_bytes metric has no data"

    def test_cluster_cpu_usage_query(self):
        """Test the actual dashboard query for cluster CPU usage."""
        query = 'sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) / sum(machine_cpu_cores) * 100'
        result = self.query_prometheus(query)

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "Cluster CPU usage query returned no data"

        # Check that the value is a reasonable percentage (0-100)
        value = float(result["data"]["result"][0]["value"][1])
        assert 0 <= value <= 100, f"CPU usage {value}% is out of range"

    def test_cluster_memory_usage_query(self):
        """Test the actual dashboard query for cluster memory usage."""
        query = 'sum(container_memory_working_set_bytes{container!=""}) / sum(machine_memory_bytes) * 100'
        result = self.query_prometheus(query)

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "Cluster memory usage query returned no data"

        # Check that the value is a reasonable percentage (0-100)
        value = float(result["data"]["result"][0]["value"][1])
        assert 0 <= value <= 100, f"Memory usage {value}% is out of range"

    def test_cpu_usage_by_namespace_query(self):
        """Test CPU usage by namespace query."""
        query = 'sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)'
        result = self.query_prometheus(query)

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "CPU usage by namespace query returned no data"

        # Verify we have data for multiple namespaces
        namespaces = [r["metric"]["namespace"] for r in result["data"]["result"]]
        assert len(namespaces) >= 3, \
            f"Expected at least 3 namespaces, got {len(namespaces)}: {namespaces}"

    def test_memory_usage_by_namespace_query(self):
        """Test memory usage by namespace query."""
        query = 'sum(container_memory_working_set_bytes{container!=""}) by (namespace)'
        result = self.query_prometheus(query)

        assert result["status"] == "success", f"Query failed: {result}"
        assert len(result["data"]["result"]) > 0, \
            "Memory usage by namespace query returned no data"

        # Verify we have data for multiple namespaces
        namespaces = [r["metric"]["namespace"] for r in result["data"]["result"]]
        assert len(namespaces) >= 3, \
            f"Expected at least 3 namespaces, got {len(namespaces)}: {namespaces}"

    def test_prometheus_scraping_kubelet(self):
        """Test that Prometheus is scraping kubelet targets."""
        import subprocess
        import json

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "http://prometheus.observability.svc:9090/api/v1/targets"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to get targets: {result.stderr}"

        targets = json.loads(result.stdout)
        assert targets["status"] == "success"

        # Find kubelet/cAdvisor targets
        kubelet_targets = [
            t for t in targets["data"]["activeTargets"]
            if t.get("labels", {}).get("job") in ["kubernetes-kubelet", "kubernetes-cadvisor"]
        ]

        assert len(kubelet_targets) > 0, \
            f"No kubelet/cAdvisor targets found. Active jobs: {set([t.get('labels', {}).get('job') for t in targets['data']['activeTargets']])}"

        # Verify targets are up
        for target in kubelet_targets:
            assert target["health"] == "up", \
                f"Kubelet target {target.get('labels', {}).get('job')} is not healthy: {target.get('lastError', 'unknown error')}"
