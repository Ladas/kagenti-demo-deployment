"""
Test that Loki dashboard panels actually load data (not just spin).

This is the critical test that verifies the dashboard fix works.
Following TDD approach from claude.md - test that panels query successfully.
"""
import pytest
import subprocess
import json
import time
import urllib.parse


class TestDashboardDataLoading:
    """Test that dashboard panels can actually query and load data."""

    def test_dashboard_variables_use_valid_regex(self):
        """Test that dashboard variables use .+ instead of .* (Loki requirement)."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            "http://localhost:3000/api/dashboards/uid/kagenti-loki-logs"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to query Grafana: {result.stderr}"

        dashboard = json.loads(result.stdout)
        variables = dashboard["dashboard"]["templating"]["list"]

        # Check all variables with allValue
        for var in variables:
            if "allValue" in var:
                all_value = var["allValue"]
                var_name = var["name"]

                # Must NOT be .* (empty-compatible, rejected by Loki)
                assert all_value != ".*", \
                    f"Variable '{var_name}' uses .* which Loki rejects"

                # Should be .+ (non-empty compatible)
                assert all_value == ".+", \
                    f"Variable '{var_name}' should use .+ but uses: {all_value}"

    def test_namespace_variable_can_query_loki(self):
        """Test that namespace variable can successfully query Loki for values."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            "http://localhost:3000/api/datasources/proxy/3/loki/api/v1/label/namespace/values"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"

        response = json.loads(result.stdout)
        assert response["status"] == "success", f"Loki query failed: {response}"

        namespaces = response.get("data", [])
        assert len(namespaces) > 0, "No namespaces found in Loki"
        assert "observability" in namespaces, \
            f"observability namespace not found. Got: {namespaces}"

    def test_pod_variable_query_with_all_namespaces(self):
        """Test that pod variable can query with all namespaces selected."""
        # Simulate the pod variable query with namespace=.+ (all namespaces)
        query = '{namespace=~".+"}'
        encoded_query = urllib.parse.quote(query)

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            f"http://localhost:3000/api/datasources/proxy/3/loki/api/v1/label/pod/values?query={encoded_query}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"

        response = json.loads(result.stdout)
        assert response["status"] == "success", \
            f"Pod variable query failed with namespace=.+: {response}"

        pods = response.get("data", [])
        assert len(pods) > 0, "No pods found when querying with namespace=.+"

    def test_panel_query_with_all_variables_selected(self):
        """Test that panel can query logs with all variables set to 'All' (using .+)."""
        # Simulate the "All Logs" panel query with all variables = .+
        end_ns = int(time.time() * 1e9)
        start_ns = end_ns - (3600 * 1e9)  # 1 hour ago

        query = '{namespace=~".+",pod=~".+",level=~".+"}'
        encoded_query = urllib.parse.quote(query)

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            f"http://localhost:3000/api/datasources/proxy/3/loki/api/v1/query_range?query={encoded_query}&start={int(start_ns)}&end={int(end_ns)}&limit=10"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"

        response = json.loads(result.stdout)
        assert response["status"] == "success", \
            f"Panel query failed with all variables=.+: {response}"

    def test_error_logs_panel_query(self):
        """Test that Error Logs panel can query successfully."""
        end_ns = int(time.time() * 1e9)
        start_ns = end_ns - (3600 * 1e9)

        # Error logs panel uses a filter for error level
        query = '{namespace=~".+",pod=~".+"} |~ "(?i)error"'
        encoded_query = urllib.parse.quote(query)

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            f"http://localhost:3000/api/datasources/proxy/3/loki/api/v1/query_range?query={encoded_query}&start={int(start_ns)}&end={int(end_ns)}&limit=10"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"

        response = json.loads(result.stdout)
        assert response["status"] == "success", \
            f"Error logs panel query failed: {response}"

    def test_logs_per_second_stat_panel(self):
        """Test that 'Logs per Second' stat panel can query successfully."""
        end_ns = int(time.time() * 1e9)
        start_ns = end_ns - (3600 * 1e9)

        # Logs per second uses rate aggregation
        query = 'sum(rate({namespace=~".+"}[5m]))'
        encoded_query = urllib.parse.quote(query)

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            f"http://localhost:3000/api/datasources/proxy/3/loki/api/v1/query_range?query={encoded_query}&start={int(start_ns)}&end={int(end_ns)}&step=60"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"

        response = json.loads(result.stdout)
        assert response["status"] == "success", \
            f"Logs per second panel query failed: {response}"

    def test_no_empty_compatible_regex_in_queries(self):
        """Test that no dashboard panel uses .* (empty-compatible regex)."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            "http://localhost:3000/api/dashboards/uid/kagenti-loki-logs"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0

        dashboard = json.loads(result.stdout)
        panels = dashboard["dashboard"]["panels"]

        for panel in panels:
            targets = panel.get("targets", [])
            for target in targets:
                expr = target.get("expr", "")
                if expr and "=~" in expr:
                    # Check if query uses .*" pattern (empty-compatible)
                    assert '=~".*"' not in expr and "=~'.*'" not in expr, \
                        f"Panel '{panel.get('title')}' uses empty-compatible regex .* in query: {expr}"

    @pytest.mark.slow
    def test_dashboard_accessible_and_loads_without_errors(self):
        """Integration test: verify dashboard is accessible and doesn't show query errors."""
        # Check that dashboard exists and is provisioned
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            "http://localhost:3000/api/dashboards/uid/kagenti-loki-logs"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0

        dashboard = json.loads(result.stdout)
        assert dashboard["dashboard"]["title"] == "Loki Logs Explorer"
        assert len(dashboard["dashboard"]["panels"]) == 11

        # Verify all variables are properly configured
        variables = dashboard["dashboard"]["templating"]["list"]
        for var in variables:
            if var.get("type") == "query":
                assert var.get("datasource") == "Loki", \
                    f"Variable '{var['name']}' should use Loki datasource"


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
