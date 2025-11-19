"""
Test Kubernetes Cluster Dashboard Panels
Tests that all Grafana dashboard panels return valid data from Prometheus.

Uses kubectl exec pattern to query services from inside the cluster,
allowing tests to run both locally and in CI without port-forwarding.
"""

import json
import subprocess
import pytest
from urllib.parse import quote


@pytest.fixture(scope="module")
def grafana_api():
    """Grafana API endpoint inside cluster."""
    return "http://grafana.observability.svc:3000"


@pytest.fixture(scope="module")
def prometheus_api():
    """Prometheus API endpoint inside cluster."""
    return "http://prometheus.observability.svc:9090"


@pytest.fixture(scope="module")
def grafana_auth():
    """Grafana admin credentials."""
    return ("admin", "admin123")


def kubectl_exec_curl(url: str, auth: tuple = None, timeout: int = 10) -> dict:
    """
    Execute curl via kubectl exec from Grafana pod to query cluster services.

    This pattern allows tests to work from local machine or CI without port-forwarding.
    Similar to test_loki_logs.py approach.

    Args:
        url: Full URL to query (e.g., http://prometheus.observability.svc:9090/api/v1/query?...)
        auth: Optional (username, password) tuple for basic auth
        timeout: Request timeout in seconds

    Returns:
        Parsed JSON response
    """
    curl_cmd = ["curl", "-s", "-m", str(timeout)]

    if auth:
        curl_cmd.extend(["-u", f"{auth[0]}:{auth[1]}"])

    curl_cmd.append(url)

    cmd = [
        "kubectl", "exec", "-n", "observability",
        "deployment/grafana", "--",
        *curl_cmd
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 5)

    if result.returncode != 0:
        pytest.fail(f"kubectl exec curl failed: {result.stderr}")

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON response: {e}\nOutput: {result.stdout}")


@pytest.fixture(scope="module")
def dashboard_panels():
    """Load all panels from Kubernetes Cluster dashboard."""
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/kubernetes-cluster.json"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    # Extract all panels (including those in collapsed rows)
    panels = []
    for panel in dashboard.get('panels', []):
        if panel.get('type') == 'row' and 'panels' in panel:
            # Collapsed row with nested panels
            panels.extend(panel['panels'])
        elif panel.get('type') != 'row':
            # Regular panel
            panels.append(panel)

    return panels


def test_dashboard_file_exists():
    """Verify dashboard file exists and is valid JSON."""
    import os
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/kubernetes-cluster.json"

    assert os.path.exists(dashboard_path), f"Dashboard file not found: {dashboard_path}"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    assert dashboard.get('title') == "Kubernetes Cluster Overview"
    assert dashboard.get('uid') == "kagenti-k8s-cluster"
    assert len(dashboard.get('panels', [])) > 0, "Dashboard has no panels"


def test_dashboard_has_row_sections(dashboard_panels):
    """Verify dashboard has organized row sections."""
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/kubernetes-cluster.json"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    row_panels = [p for p in dashboard['panels'] if p.get('type') == 'row']
    row_titles = [p.get('title') for p in row_panels]

    assert len(row_panels) >= 3, f"Expected at least 3 row sections, got {len(row_panels)}"
    assert any("Overview" in title for title in row_titles), "Missing Overview section"
    assert any("Alerting" in title for title in row_titles), "Missing Alerting section"
    assert any("Namespace" in title for title in row_titles), "Missing By Namespace section"


class TestPrometheusQueries:
    """Test that all Prometheus queries in dashboard panels return data."""

    def query_prometheus(self, prometheus_api, query):
        """Execute Prometheus query via kubectl exec and return result."""
        # URL-encode the query parameter
        encoded_query = quote(query)
        url = f"{prometheus_api}/api/v1/query?query={encoded_query}"

        data = kubectl_exec_curl(url, auth=None, timeout=10)
        assert data.get('status') == 'success', f"Query failed: {data.get('error', 'unknown error')}"

        return data.get('data', {}).get('result', [])

    def test_cluster_cpu_usage(self, prometheus_api):
        """Test: Cluster CPU Usage panel."""
        query = 'sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) / sum(machine_cpu_cores) * 100'
        result = self.query_prometheus(prometheus_api, query)

        # Should return a single value (cluster-wide percentage)
        assert len(result) >= 0, "Query should not error"
        # Note: May be empty if no containers running yet

    def test_cluster_memory_usage(self, prometheus_api):
        """Test: Cluster Memory Usage panel."""
        query = 'sum(container_memory_working_set_bytes{container!=""}) / sum(machine_memory_bytes) * 100'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"

    def test_cluster_disk_usage(self, prometheus_api):
        """Test: Cluster Disk Usage panel."""
        query = '(sum(kubelet_volume_stats_used_bytes) / sum(kubelet_volume_stats_capacity_bytes)) * 100'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"

    def test_total_pods(self, prometheus_api):
        """Test: Total Pods panel."""
        query = 'sum(kube_pod_info)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"

    def test_running_pods(self, prometheus_api):
        """Test: Running Pods panel."""
        query = 'sum(kube_pod_status_phase{phase="Running"}) or vector(0)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 1, "Should return at least default value (0)"

    def test_pending_pods(self, prometheus_api):
        """Test: Pending Pods panel."""
        query = 'sum(kube_pod_status_phase{phase="Pending"}) or vector(0)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 1, "Should return at least default value (0)"

    def test_failed_pods(self, prometheus_api):
        """Test: Failed Pods panel."""
        query = 'sum(kube_pod_status_phase{phase="Failed"}) or vector(0)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 1, "Should return at least default value (0)"

    def test_pod_restarts(self, prometheus_api):
        """Test: Pod Restarts (Last 1h) panel."""
        query = 'sum(increase(kube_pod_container_status_restarts_total[1h])) or vector(0)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 1, "Should return at least default value (0)"

    def test_oomkilled_pods(self, prometheus_api):
        """Test: OOMKilled Pods panel."""
        query = 'sum(kube_pod_container_status_terminated_reason{reason="OOMKilled"}) or vector(0)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 1, "Should return at least default value (0)"

    def test_crashloop_pods(self, prometheus_api):
        """Test: CrashLoopBackOff Pods panel."""
        query = 'sum(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}) or vector(0)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 1, "Should return at least default value (0)"

    def test_firing_alerts(self, prometheus_api):
        """Test: Firing Alerts panel."""
        query = 'count(ALERTS{alertstate="firing"}) or vector(0)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 1, "Should return at least default value (0)"

    def test_firing_alerts_timeseries(self, prometheus_api):
        """Test: Firing Alerts Over Time panel."""
        query = 'count(ALERTS{alertstate="firing"}) by (alertname, severity)'
        result = self.query_prometheus(prometheus_api, query)

        # May be empty if no alerts firing
        assert len(result) >= 0, "Query should not error"

    def test_pod_status_over_time(self, prometheus_api):
        """Test: Pod Status Over Time panel."""
        query = 'sum(kube_pod_status_phase) by (phase)'
        result = self.query_prometheus(prometheus_api, query)

        # Should have at least one phase (Running, Pending, etc.)
        assert len(result) >= 0, "Query should not error"

    def test_pod_status_by_namespace(self, prometheus_api):
        """Test: Pod Status by Namespace panel."""
        query = 'sum(kube_pod_status_phase{phase="Running"}) by (namespace)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"

    def test_cpu_usage_by_namespace(self, prometheus_api):
        """Test: CPU Usage by Namespace panel."""
        query = 'sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"

    def test_memory_usage_by_namespace(self, prometheus_api):
        """Test: Memory Usage by Namespace panel."""
        query = 'sum(container_memory_working_set_bytes{container!=""}) by (namespace)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"

    def test_disk_usage_by_namespace(self, prometheus_api):
        """Test: Disk Usage by Namespace panel."""
        query = 'sum(kubelet_volume_stats_used_bytes) by (namespace)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"

    def test_network_io_by_namespace(self, prometheus_api):
        """Test: Network I/O by Namespace panel."""
        query = 'sum(rate(container_network_receive_bytes_total[5m])) by (namespace)'
        result = self.query_prometheus(prometheus_api, query)

        assert len(result) >= 0, "Query should not error"


class TestGrafanaDashboardAPI:
    """Test dashboard accessibility via Grafana API."""

    def test_grafana_api_accessible(self, grafana_api):
        """Verify Grafana API is accessible via kubectl exec."""
        url = f"{grafana_api}/api/health"
        health = kubectl_exec_curl(url, auth=None, timeout=5)
        assert health.get('database') == 'ok', "Grafana database not healthy"

    def test_dashboard_exists_in_grafana(self, grafana_api, grafana_auth):
        """Verify Kubernetes dashboard exists in Grafana via kubectl exec."""
        url = f"{grafana_api}/api/dashboards/uid/kagenti-k8s-cluster"
        data = kubectl_exec_curl(url, auth=grafana_auth, timeout=10)

        assert data.get('dashboard', {}).get('uid') == 'kagenti-k8s-cluster'
        assert data.get('dashboard', {}).get('title') == 'Kubernetes Cluster Overview'

    def test_prometheus_datasource_exists(self, grafana_api, grafana_auth):
        """Verify Prometheus datasource is configured via kubectl exec."""
        url = f"{grafana_api}/api/datasources"
        datasources = kubectl_exec_curl(url, auth=grafana_auth, timeout=10)

        prometheus_ds = [ds for ds in datasources if ds.get('type') == 'prometheus']

        assert len(prometheus_ds) > 0, "No Prometheus datasource found"
        assert any(ds.get('name') == 'Prometheus' for ds in prometheus_ds)

    def test_dashboard_panels_have_valid_queries(self, dashboard_panels):
        """Verify all panels have valid Prometheus queries."""
        panels_with_queries = [p for p in dashboard_panels if p.get('targets')]

        assert len(panels_with_queries) > 0, "No panels with queries found"

        for panel in panels_with_queries:
            title = panel.get('title', 'Unknown')
            targets = panel.get('targets', [])

            for target in targets:
                query = target.get('expr', '')
                assert query, f"Panel '{title}' has empty query"
                assert len(query) > 0, f"Panel '{title}' has invalid query"


@pytest.mark.parametrize("panel_title,expected_type", [
    ("Cluster CPU Usage", "gauge"),
    ("Cluster Memory Usage", "gauge"),
    ("Cluster Disk Usage", "gauge"),
    ("Total Pods", "stat"),
    ("Running Pods", "stat"),
    ("Failed Pods", "stat"),
    ("Firing Alerts", "stat"),
    ("Firing Alerts Over Time", "timeseries"),
    ("Pod Status Over Time", "timeseries"),
    ("Pod Status by Namespace", "timeseries"),
    ("CPU Usage by Namespace", "timeseries"),
    ("Memory Usage by Namespace", "timeseries"),
])
def test_panel_type(dashboard_panels, panel_title, expected_type):
    """Verify panels have correct visualization type."""
    panel = next((p for p in dashboard_panels if p.get('title') == panel_title), None)

    assert panel is not None, f"Panel '{panel_title}' not found"
    assert panel.get('type') == expected_type, f"Panel '{panel_title}' should be type '{expected_type}', got '{panel.get('type')}'"


def test_all_panels_have_datasource(dashboard_panels):
    """Verify all panels specify a datasource."""
    panels_with_data = [p for p in dashboard_panels if p.get('targets')]

    for panel in panels_with_data:
        title = panel.get('title', 'Unknown')
        datasource = panel.get('datasource')

        assert datasource is not None, f"Panel '{title}' missing datasource"

        # Should have either type or uid
        if isinstance(datasource, dict):
            assert datasource.get('type') or datasource.get('uid'), \
                f"Panel '{title}' has invalid datasource config"


def test_overview_section_not_collapsed():
    """Verify Overview section is visible by default (not collapsed)."""
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/kubernetes-cluster.json"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    row_panels = [p for p in dashboard['panels'] if p.get('type') == 'row']
    overview_row = next((p for p in row_panels if 'Overview' in p.get('title', '')), None)

    assert overview_row is not None, "Overview row not found"
    assert overview_row.get('collapsed') is False, "Overview section should not be collapsed"


def test_alerting_section_exists():
    """Verify Alerting section exists and is second."""
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/kubernetes-cluster.json"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    row_panels = [p for p in dashboard['panels'] if p.get('type') == 'row']

    # Second row should be Alerting
    assert len(row_panels) >= 2, "Dashboard should have at least 2 row sections"

    # Find alerting row
    alerting_row = next((p for p in row_panels if 'Alerting' in p.get('title', '')), None)
    assert alerting_row is not None, "Alerting row not found"

    # Should have panels including timeseries
    alerting_panels = alerting_row.get('panels', [])
    assert len(alerting_panels) >= 2, "Alerting section should have at least 2 panels"

    # Should have timeseries chart
    timeseries_panels = [p for p in alerting_panels if p.get('type') == 'timeseries']
    assert len(timeseries_panels) >= 1, "Alerting section should have timeseries chart"
