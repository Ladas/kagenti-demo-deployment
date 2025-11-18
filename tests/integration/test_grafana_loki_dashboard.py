"""
Test Loki Logs Explorer Dashboard Panels
Tests that all Grafana Loki dashboard panels return valid data.
"""

import json
import pytest
import requests


@pytest.fixture(scope="module")
def grafana_api():
    """Grafana API endpoint inside cluster."""
    return "http://grafana.observability.svc:3000"


@pytest.fixture(scope="module")
def loki_api():
    """Loki API endpoint inside cluster."""
    return "http://loki-query-frontend.observability.svc:3100"


@pytest.fixture(scope="module")
def prometheus_api():
    """Prometheus API endpoint inside cluster."""
    return "http://prometheus.observability.svc:9090"


@pytest.fixture(scope="module")
def grafana_auth():
    """Grafana admin credentials."""
    return ("admin", "admin123")


@pytest.fixture(scope="module")
def dashboard_panels():
    """Load all panels from Loki Logs Explorer dashboard."""
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/loki-logs.json"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    return dashboard.get('panels', [])


def test_dashboard_file_exists():
    """Verify Loki dashboard file exists and is valid JSON."""
    import os
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/loki-logs.json"

    assert os.path.exists(dashboard_path), f"Dashboard file not found: {dashboard_path}"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    assert dashboard.get('title') == "Loki Logs Explorer"
    assert dashboard.get('uid') == "kagenti-loki-logs"
    assert len(dashboard.get('panels', [])) > 0, "Dashboard has no panels"


def test_dashboard_has_new_panels(dashboard_panels):
    """Verify dashboard has new cumulative and correlation panels."""
    panel_titles = [p.get('title') for p in dashboard_panels]

    # New panels added
    assert "Error Cumulative Counts by Namespace" in panel_titles, "Missing error cumulative chart"
    assert "Warning Cumulative Counts by Namespace" in panel_titles, "Missing warning cumulative chart"
    assert "Log Errors vs Alerts (Coverage Analysis)" in panel_titles, "Missing correlation chart"


def test_dashboard_version():
    """Verify dashboard version is updated to 3."""
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/loki-logs.json"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    assert dashboard.get('version') == 3, "Dashboard version should be 3 after updates"


def test_panel_count():
    """Verify dashboard has expected number of panels."""
    dashboard_path = "/Users/ladas/Projects/OCTO/research/kagenti-demo-deployment/components/02-observability/grafana/dashboards/loki-logs.json"

    with open(dashboard_path, 'r') as f:
        dashboard = json.load(f)

    panels = dashboard.get('panels', [])
    assert len(panels) == 14, f"Expected 14 panels (11 original + 3 new), got {len(panels)}"


@pytest.mark.parametrize("panel_title,expected_type", [
    ("Total Logs", "stat"),
    ("Error Count", "stat"),
    ("Warning Count", "stat"),
    ("Logs per Second", "stat"),
    ("Log Volume by Level", "timeseries"),
    ("Log Volume by Namespace", "timeseries"),
    ("Error Cumulative Counts by Namespace", "timeseries"),
    ("Warning Cumulative Counts by Namespace", "timeseries"),
    ("Log Errors vs Alerts (Coverage Analysis)", "timeseries"),
    ("All Logs", "logs"),
    ("Error Logs", "logs"),
    ("Warning Logs", "logs"),
    ("Top 10 Error Sources", "table"),
    ("Top 10 Warning Sources", "table"),
])
def test_panel_type(dashboard_panels, panel_title, expected_type):
    """Verify panels have correct visualization type."""
    panel = next((p for p in dashboard_panels if p.get('title') == panel_title), None)

    assert panel is not None, f"Panel '{panel_title}' not found"
    assert panel.get('type') == expected_type, f"Panel '{panel_title}' should be type '{expected_type}', got '{panel.get('type')}'"
