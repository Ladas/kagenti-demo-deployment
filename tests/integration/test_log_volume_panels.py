"""
TDD tests for Log Volume panels (by Level and by Namespace).

These panels were reported as not working. Following TDD approach:
1. Write tests that verify the panel queries
2. See them fail
3. Fix the queries
4. Tests pass
"""
import pytest
import subprocess
import json
import time
import urllib.parse


class TestLogVolumePanels:
    """Test Log Volume by Level and by Namespace panels."""

    def get_dashboard(self):
        """Helper to fetch dashboard JSON."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123",
            "http://localhost:3000/api/dashboards/uid/kagenti-loki-logs"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Failed to query Grafana: {result.stderr}"

        return json.loads(result.stdout)["dashboard"]

    def query_loki(self, query: str, start: int = None, end: int = None, step: int = 60):
        """Helper to query Loki directly."""
        if start is None:
            end = int(time.time())
            start = end - 3600  # 1 hour ago

        encoded_query = urllib.parse.quote(query)

        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s",
            f"http://loki-query-frontend.observability.svc:3100/loki/api/v1/query_range?query={encoded_query}&start={start}&end={end}&step={step}"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Failed to query Loki: {result.stderr}"

        return json.loads(result.stdout)

    def test_log_volume_by_level_panel_exists(self):
        """Test that Log Volume by Level panel exists."""
        dashboard = self.get_dashboard()
        panels = dashboard["panels"]

        volume_by_level = next(
            (p for p in panels if p.get("title") == "Log Volume by Level"),
            None
        )

        assert volume_by_level is not None, "Log Volume by Level panel not found"
        assert volume_by_level["type"] == "timeseries", \
            f"Expected timeseries, got {volume_by_level['type']}"

    def test_log_volume_by_namespace_panel_exists(self):
        """Test that Log Volume by Namespace panel exists."""
        dashboard = self.get_dashboard()
        panels = dashboard["panels"]

        volume_by_ns = next(
            (p for p in panels if p.get("title") == "Log Volume by Namespace"),
            None
        )

        assert volume_by_ns is not None, "Log Volume by Namespace panel not found"
        assert volume_by_ns["type"] == "timeseries", \
            f"Expected timeseries, got {volume_by_ns['type']}"

    def test_log_volume_by_level_has_valid_queries(self):
        """Test that Log Volume by Level panel has valid LogQL queries."""
        dashboard = self.get_dashboard()
        panels = dashboard["panels"]

        volume_by_level = next(
            p for p in panels if p.get("title") == "Log Volume by Level"
        )

        targets = volume_by_level.get("targets", [])
        assert len(targets) > 0, "Panel has no query targets"

        for target in targets:
            expr = target.get("expr")
            assert expr is not None, f"Target {target.get('refId')} has no expr"

            # Should use rate() or count_over_time() for time series
            assert "rate(" in expr or "count_over_time(" in expr, \
                f"Query should use rate() or count_over_time(): {expr}"

    def test_log_volume_by_namespace_has_valid_query(self):
        """Test that Log Volume by Namespace panel has valid LogQL query."""
        dashboard = self.get_dashboard()
        panels = dashboard["panels"]

        volume_by_ns = next(
            p for p in panels if p.get("title") == "Log Volume by Namespace"
        )

        targets = volume_by_ns.get("targets", [])
        assert len(targets) > 0, "Panel has no query targets"

        expr = targets[0].get("expr")
        assert expr is not None, "Query has no expr"

        # Should aggregate by namespace
        assert "by (namespace)" in expr or "by(namespace)" in expr, \
            f"Query should aggregate by namespace: {expr}"

        # Should use rate() for time series
        assert "rate(" in expr, f"Query should use rate(): {expr}"

    @pytest.mark.slow
    def test_log_volume_by_level_queries_execute(self):
        """Test that Log Volume by Level queries actually execute without errors."""
        dashboard = self.get_dashboard()
        panels = dashboard["panels"]

        volume_by_level = next(
            p for p in panels if p.get("title") == "Log Volume by Level"
        )

        targets = volume_by_level.get("targets", [])

        for target in targets:
            expr = target.get("expr")

            # Replace dashboard variables with actual values for testing
            test_query = expr.replace("$namespace", ".+")
            test_query = test_query.replace("$pod", ".+")
            test_query = test_query.replace("$search", "")
            test_query = test_query.replace("$level", ".+")
            test_query = test_query.replace("$__rate_interval", "5m")
            test_query = test_query.replace("$__range", "1h")

            response = self.query_loki(test_query)

            assert response.get("status") == "success", \
                f"Query failed for {target.get('refId')}: {response}"

    @pytest.mark.slow
    def test_log_volume_by_namespace_query_executes(self):
        """Test that Log Volume by Namespace query executes without errors."""
        dashboard = self.get_dashboard()
        panels = dashboard["panels"]

        volume_by_ns = next(
            p for p in panels if p.get("title") == "Log Volume by Namespace"
        )

        expr = volume_by_ns["targets"][0].get("expr")

        # Replace dashboard variables
        test_query = expr.replace("$namespace", ".+")
        test_query = test_query.replace("$pod", ".+")
        test_query = test_query.replace("$search", "")
        test_query = test_query.replace("$level", ".+")
        test_query = test_query.replace("$__rate_interval", "5m")

        response = self.query_loki(test_query)

        assert response.get("status") == "success", \
            f"Query failed: {response}"

        # Should return data with namespace labels
        results = response.get("data", {}).get("result", [])
        if len(results) > 0:
            # Check that results have namespace metric
            assert "metric" in results[0], "Result missing metric"
            assert "namespace" in results[0]["metric"], \
                "Result metric missing namespace label"

    @pytest.mark.slow
    def test_log_volume_by_level_returns_data_per_level(self):
        """Test that Log Volume by Level actually returns data separated by log level."""
        # Query to get error logs
        query = 'sum by (level) (count_over_time({namespace=~".+", level=~".+"} [5m]))'

        response = self.query_loki(query)

        assert response.get("status") == "success", f"Query failed: {response}"

        results = response.get("data", {}).get("result", [])

        # We should get results if there are any logs
        # Each result should have a level in the metric
        if len(results) > 0:
            for result in results:
                metric = result.get("metric", {})
                # Should have level label (might be empty if level not in logs)
                assert "level" in metric or len(metric) == 0, \
                    f"Result should have level label or be empty: {metric}"

    @pytest.mark.slow
    def test_log_volume_by_namespace_returns_data_per_namespace(self):
        """Test that Log Volume by Namespace returns data per namespace."""
        query = 'sum by (namespace) (rate({namespace=~".+"} [5m]))'

        response = self.query_loki(query)

        assert response.get("status") == "success", f"Query failed: {response}"

        results = response.get("data", {}).get("result", [])

        # Should have results for different namespaces
        assert len(results) > 0, "No results returned for namespace volume query"

        # Each result should have namespace label
        for result in results:
            metric = result.get("metric", {})
            assert "namespace" in metric, \
                f"Result missing namespace label: {metric}"

            namespace = metric["namespace"]
            assert namespace != "", f"Namespace label is empty"

    def test_log_volume_queries_do_not_use_empty_compatible_regex(self):
        """Test that log volume panels don't use .* (empty-compatible regex)."""
        dashboard = self.get_dashboard()
        panels = dashboard["panels"]

        # Check Log Volume by Level
        volume_by_level = next(
            p for p in panels if p.get("title") == "Log Volume by Level"
        )

        for target in volume_by_level.get("targets", []):
            expr = target.get("expr", "")
            # Variables should use .+ not .*
            # When expanded, should not have empty-compatible patterns
            assert '=~".*"' not in expr and "=~'.*'" not in expr, \
                f"Log Volume by Level query uses empty-compatible regex: {expr}"

        # Check Log Volume by Namespace
        volume_by_ns = next(
            p for p in panels if p.get("title") == "Log Volume by Namespace"
        )

        for target in volume_by_ns.get("targets", []):
            expr = target.get("expr", "")
            assert '=~".*"' not in expr and "=~'.*'" not in expr, \
                f"Log Volume by Namespace query uses empty-compatible regex: {expr}"


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
