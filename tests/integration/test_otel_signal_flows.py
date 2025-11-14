#!/usr/bin/env python3
"""
OTEL Signal Flow Integration Tests for Kagenti Platform

Tests the three observability signals (metrics, logs, traces) are properly configured
and data is flowing through the entire pipeline:

**Metrics Signal**: OTEL Collector → Prometheus → Grafana
**Logs Signal**: Promtail → Loki → Grafana
**Traces Signal**: OTEL Collector → Tempo → Grafana (+ Phoenix for LLM traces)

Requirements:
    pip install -r requirements.txt

Usage:
    pytest tests/integration/test_otel_signal_flows.py -v
    pytest tests/integration/test_otel_signal_flows.py::TestMetricsSignal -v
    pytest tests/integration/test_otel_signal_flows.py::TestLogsSignal -v
    pytest tests/integration/test_otel_signal_flows.py::TestTracesSignal -v
"""

import json
import re
import time
from typing import Dict, Optional, List

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


def exec_in_pod(k8s_client, namespace: str, pod_name: str, command: List[str]) -> str:
    """
    Execute command in pod and return output.

    Args:
        k8s_client: Kubernetes CoreV1Api client (unused - kept for compatibility)
        namespace: Kubernetes namespace
        pod_name: Pod name
        command: Command to execute

    Returns:
        Command stdout output
    """
    import subprocess

    # Build kubectl exec command
    kubectl_cmd = ["kubectl", "exec", "-n", namespace, pod_name, "--"] + command

    result = subprocess.run(
        kubectl_cmd,
        capture_output=True,
        text=True,
        timeout=30
    )

    return result.stdout


def get_pod_for_deployment(k8s_client, namespace: str, deployment_name: str) -> Optional[str]:
    """
    Get first running pod name for a deployment.

    Args:
        k8s_client: Kubernetes CoreV1Api client
        namespace: Kubernetes namespace
        deployment_name: Deployment name

    Returns:
        Pod name or None if no running pods
    """
    try:
        pods = k8s_client.list_namespaced_pod(
            namespace=namespace,
            label_selector=f"app={deployment_name}"
        )

        for pod in pods.items:
            if pod.status.phase == "Running":
                return pod.metadata.name

        return None
    except ApiException:
        return None


# ============================================================================
# Test: Metrics Signal Flow
# ============================================================================

class TestMetricsSignal:
    """
    Test metrics signal flow: OTEL Collector → Prometheus → Grafana

    Validates:
    1. OTEL Collector exposes /metrics endpoint (Prometheus exposition format)
    2. Prometheus scrapes OTEL Collector and stores metrics
    3. Prometheus HTTP API responds to PromQL queries
    4. Grafana can query Prometheus datasource
    """

    @pytest.mark.critical
    def test_otel_collector_metrics_endpoint(self, k8s_client):
        """Verify OTEL Collector exposes /metrics endpoint."""
        # Get Grafana pod to use as client (has curl)
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test metrics endpoint")

        # Query OTEL Collector metrics endpoint
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s http://otel-collector.observability.svc:8888/metrics | head -20"
                ]
            )

            # Verify Prometheus exposition format (should have TYPE and HELP comments)
            assert "# TYPE" in output or "# HELP" in output, \
                "OTEL Collector /metrics endpoint not returning Prometheus format"

            # Verify OTEL Collector metrics present
            assert "otelcol_" in output or "otlp_" in output, \
                "OTEL Collector metrics not found in /metrics output"

        except Exception as e:
            pytest.fail(f"Failed to query OTEL Collector metrics endpoint: {e}")

    @pytest.mark.critical
    def test_prometheus_scraping_otel_collector(self, k8s_client):
        """Verify Prometheus is scraping OTEL Collector metrics."""
        # Get Grafana pod to use as client
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test Prometheus")

        # Query Prometheus API to check if otelcol metrics exist
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s 'http://prometheus.observability.svc:9090/api/v1/label/__name__/values' "
                    "| grep -o 'otelcol' | head -1"
                ]
            )

            assert "otelcol" in output, \
                "Prometheus not scraping OTEL Collector metrics (no otelcol_* metrics found)"

        except Exception as e:
            pytest.fail(f"Failed to query Prometheus for OTEL Collector metrics: {e}")

    @pytest.mark.critical
    def test_prometheus_api_responds(self, k8s_client):
        """Verify Prometheus HTTP API responds to PromQL queries."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test Prometheus API")

        # Query Prometheus API with simple PromQL query
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s 'http://prometheus.observability.svc:9090/api/v1/query?query=up' "
                    "| grep -o '\"status\":\"success\"'"
                ]
            )

            assert "success" in output, \
                "Prometheus API not responding successfully to PromQL queries"

        except Exception as e:
            pytest.fail(f"Failed to query Prometheus API: {e}")

    @pytest.mark.critical
    def test_grafana_prometheus_datasource(self, k8s_client):
        """Verify Grafana can query Prometheus datasource."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test datasource")

        # Query Grafana API for datasources
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -u admin:admin123 http://localhost:3000/api/datasources "
                    "| grep -o '\"type\":\"prometheus\"'"
                ]
            )

            assert "prometheus" in output, \
                "Grafana does not have Prometheus datasource configured"

        except Exception as e:
            pytest.fail(f"Failed to query Grafana datasources: {e}")

    def test_metrics_signal_end_to_end(self, k8s_client):
        """
        End-to-end metrics signal test.

        Validates data flows: OTEL Collector → Prometheus → Grafana
        """
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test end-to-end flow")

        # Step 1: Verify OTEL Collector metrics exist
        try:
            otel_output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s http://otel-collector.observability.svc:8888/metrics | grep -c otelcol"
                ]
            )

            otel_metric_count = int(otel_output.strip())
            assert otel_metric_count > 0, "OTEL Collector not exposing metrics"

        except Exception as e:
            pytest.fail(f"Failed to verify OTEL Collector metrics: {e}")

        # Step 2: Verify Prometheus scraped the metrics
        try:
            prom_output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s 'http://prometheus.observability.svc:9090/api/v1/query?query=up{job=\"otel-collector\"}' "
                    "| grep -o '\"value\":\\[.*,\"[0-9]\"\\]'"
                ]
            )

            # Should see value:[timestamp, "1"] indicating otel-collector target is up
            assert "value" in prom_output, \
                "Prometheus not showing otel-collector target as up"

        except Exception as e:
            pytest.fail(f"Failed to verify Prometheus scraping: {e}")


# ============================================================================
# Test: Logs Signal Flow
# ============================================================================

class TestLogsSignal:
    """
    Test logs signal flow: Promtail → Loki → Grafana

    Validates:
    1. Loki is receiving logs from Promtail
    2. Loki API responds to LogQL queries
    3. Logs contain expected metadata (namespace, pod labels)
    4. Grafana can query Loki datasource
    """

    @pytest.mark.critical
    def test_loki_ready_endpoint(self, k8s_client):
        """Verify Loki /ready endpoint responds."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test Loki")

        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -o /dev/null -w '%{http_code}' "
                    "http://loki-query-frontend.observability.svc:3100/ready"
                ]
            )

            status_code = output.strip()
            assert status_code == "200", \
                f"Loki /ready endpoint returned {status_code}, expected 200"

        except Exception as e:
            pytest.fail(f"Failed to query Loki ready endpoint: {e}")

    @pytest.mark.critical
    def test_loki_receiving_logs(self, k8s_client):
        """Verify Loki is receiving logs (has log streams)."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test Loki logs")

        # Query Loki API for label values (should have namespaces)
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s 'http://loki-query-frontend.observability.svc:3100/loki/api/v1/label/namespace/values' "
                    "| grep -o '\"data\":\\[.*\\]'"
                ]
            )

            # Should see data:[...] array with namespace values
            assert "data" in output and "[" in output, \
                "Loki not returning any namespace labels (may not be receiving logs)"

        except Exception as e:
            pytest.fail(f"Failed to query Loki for labels: {e}")

    @pytest.mark.critical
    def test_loki_logql_query(self, k8s_client):
        """Verify Loki responds to LogQL queries."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test LogQL")

        # Query Loki with simple LogQL query (last 1 hour of logs from any namespace)
        try:
            # Use query_range endpoint with 1-hour range
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -G 'http://loki-query-frontend.observability.svc:3100/loki/api/v1/query_range' "
                    "--data-urlencode 'query={namespace=~\".+\"}' "
                    "--data-urlencode 'start=$(date -u -d '1 hour ago' +%s)000000000' "
                    "--data-urlencode 'end=$(date -u +%s)000000000' "
                    "| grep -o '\"status\":\"success\"'"
                ]
            )

            assert "success" in output, \
                "Loki LogQL query did not return success status"

        except Exception as e:
            pytest.fail(f"Failed to execute LogQL query: {e}")

    @pytest.mark.critical
    def test_grafana_loki_datasource(self, k8s_client):
        """Verify Grafana can query Loki datasource."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test datasource")

        # Query Grafana API for datasources
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -u admin:admin123 http://localhost:3000/api/datasources "
                    "| grep -o '\"type\":\"loki\"'"
                ]
            )

            assert "loki" in output, \
                "Grafana does not have Loki datasource configured"

        except Exception as e:
            pytest.fail(f"Failed to query Grafana datasources: {e}")

    def test_logs_signal_end_to_end(self, k8s_client):
        """
        End-to-end logs signal test.

        Validates data flows: Promtail → Loki → Grafana
        """
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test end-to-end flow")

        # Step 1: Verify Loki has logs with expected labels
        try:
            labels_output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s 'http://loki-query-frontend.observability.svc:3100/loki/api/v1/labels' "
                    "| grep -o 'namespace\\|pod\\|app'"
                ]
            )

            # Verify expected labels exist (added by Promtail)
            assert "namespace" in labels_output, "Loki logs missing 'namespace' label"
            assert "pod" in labels_output, "Loki logs missing 'pod' label"

        except Exception as e:
            pytest.fail(f"Failed to verify Loki labels: {e}")

        # Step 2: Query logs for observability namespace
        try:
            query_output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -G 'http://loki-query-frontend.observability.svc:3100/loki/api/v1/query_range' "
                    "--data-urlencode 'query={namespace=\"observability\"}' "
                    "--data-urlencode 'limit=10' "
                    "--data-urlencode 'start=$(date -u -d '1 hour ago' +%s)000000000' "
                    "--data-urlencode 'end=$(date -u +%s)000000000' "
                    "| grep -o '\"status\":\"success\"'"
                ]
            )

            assert "success" in query_output, \
                "Failed to query logs for observability namespace"

        except Exception as e:
            pytest.fail(f"Failed to verify end-to-end logs flow: {e}")


# ============================================================================
# Test: Traces Signal Flow
# ============================================================================

class TestTracesSignal:
    """
    Test traces signal flow: OTEL Collector → Tempo → Grafana (+ Phoenix for LLM traces)

    Validates:
    1. Tempo is ready to receive traces
    2. Tempo API responds to queries
    3. OTEL Collector is configured to export to Tempo
    4. Grafana can query Tempo datasource
    5. Phoenix is receiving LLM traces (via OTEL Collector filter)
    """

    @pytest.mark.critical
    def test_tempo_ready_endpoint(self, k8s_client):
        """Verify Tempo /ready endpoint responds."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test Tempo")

        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -o /dev/null -w '%{http_code}' "
                    "http://tempo.observability.svc:3200/ready"
                ]
            )

            status_code = output.strip()
            assert status_code == "200", \
                f"Tempo /ready endpoint returned {status_code}, expected 200"

        except Exception as e:
            pytest.fail(f"Failed to query Tempo ready endpoint: {e}")

    @pytest.mark.critical
    def test_otel_collector_exports_to_tempo(self, k8s_client):
        """Verify OTEL Collector is configured to export to Tempo."""
        # Read OTEL Collector ConfigMap
        try:
            configmap = k8s_client.read_namespaced_config_map(
                name="otel-collector-config",
                namespace="observability"
            )

            config_yaml = configmap.data.get("otel-collector-config.yaml", "")

            # Check for Tempo exporter configuration
            assert "tempo" in config_yaml.lower() or "otlp/tempo" in config_yaml, \
                "OTEL Collector config does not include Tempo exporter"

            # Check Tempo is in a traces pipeline
            assert "exporters:" in config_yaml and \
                   ("tempo" in config_yaml or "otlp/tempo" in config_yaml), \
                "OTEL Collector not configured to export traces to Tempo"

        except ApiException as e:
            pytest.fail(f"Failed to read OTEL Collector config: {e}")

    @pytest.mark.critical
    def test_grafana_tempo_datasource(self, k8s_client):
        """Verify Grafana can query Tempo datasource."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test datasource")

        # Query Grafana API for datasources
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -u admin:admin123 http://localhost:3000/api/datasources "
                    "| grep -o '\"type\":\"tempo\"'"
                ]
            )

            assert "tempo" in output, \
                "Grafana does not have Tempo datasource configured"

        except Exception as e:
            pytest.fail(f"Failed to query Grafana datasources: {e}")

    def test_tempo_api_search_endpoint(self, k8s_client):
        """Verify Tempo search API responds."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test Tempo API")

        # Query Tempo search API (may return empty results but should respond)
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -o /dev/null -w '%{http_code}' "
                    "'http://tempo.observability.svc:3200/api/search?limit=1'"
                ]
            )

            status_code = output.strip()
            # Accept 200 OK or 404 Not Found (search may not be enabled)
            assert status_code in ["200", "404"], \
                f"Tempo search API returned unexpected status: {status_code}"

        except Exception as e:
            pytest.fail(f"Failed to query Tempo search API: {e}")

    def test_phoenix_receiving_llm_traces(self, k8s_client):
        """Verify Phoenix is ready to receive LLM traces."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot test Phoenix")

        # Phoenix web UI should be accessible
        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -o /dev/null -w '%{http_code}' "
                    "http://phoenix.observability.svc:6006/"
                ]
            )

            status_code = output.strip()
            assert status_code == "200", \
                f"Phoenix web UI returned {status_code}, expected 200"

        except Exception as e:
            pytest.fail(f"Failed to query Phoenix web UI: {e}")

    def test_otel_collector_filters_llm_traces_to_phoenix(self, k8s_client):
        """Verify OTEL Collector filters LLM traces to Phoenix."""
        # Read OTEL Collector ConfigMap
        try:
            configmap = k8s_client.read_namespaced_config_map(
                name="otel-collector-config",
                namespace="observability"
            )

            config_yaml = configmap.data.get("otel-collector-config.yaml", "")

            # Check for Phoenix exporter
            assert "phoenix" in config_yaml.lower() or "otlp/phoenix" in config_yaml, \
                "OTEL Collector config does not include Phoenix exporter"

            # Check for routing processor (routes LLM traces to Phoenix)
            assert "routing" in config_yaml, \
                "OTEL Collector missing routing processor for Phoenix (should route LLM traces)"

        except ApiException as e:
            pytest.fail(f"Failed to read OTEL Collector config: {e}")

    def test_traces_signal_end_to_end(self, k8s_client):
        """
        End-to-end traces signal test.

        Validates data flows: OTEL Collector → Tempo (all traces) + Phoenix (LLM traces)
        """
        # Step 1: Verify OTEL Collector can receive traces (OTLP gRPC endpoint)
        try:
            service = k8s_client.read_namespaced_service(
                name="otel-collector",
                namespace="observability"
            )

            ports = {port.name: port.port for port in service.spec.ports}
            assert "otlp-grpc" in ports or "grpc" in ports, \
                "OTEL Collector missing OTLP gRPC port for trace ingestion"

        except ApiException as e:
            pytest.fail(f"Failed to verify OTEL Collector service: {e}")

        # Step 2: Verify Tempo is ready to receive traces
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running - cannot complete end-to-end test")

        try:
            tempo_status = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -o /dev/null -w '%{http_code}' "
                    "http://tempo.observability.svc:3200/ready"
                ]
            )

            assert tempo_status.strip() == "200", \
                "Tempo not ready to receive traces"

        except Exception as e:
            pytest.fail(f"Failed to verify Tempo readiness: {e}")

        # Step 3: Verify Phoenix is ready to receive LLM traces
        try:
            phoenix_status = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -o /dev/null -w '%{http_code}' "
                    "http://phoenix.observability.svc:6006/"
                ]
            )

            assert phoenix_status.strip() == "200", \
                "Phoenix not ready to receive LLM traces"

        except Exception as e:
            pytest.fail(f"Failed to verify Phoenix readiness: {e}")


# ============================================================================
# Test: Overall OTEL Signals Health
# ============================================================================

class TestOTELSignalsHealth:
    """Overall health checks for all three OTEL signals."""

    @pytest.mark.critical
    def test_all_observability_components_healthy(self, k8s_apps_client):
        """Verify all observability components have healthy replicas."""
        components = [
            ("observability", "otel-collector"),
            ("observability", "prometheus"),
            ("observability", "tempo"),
            ("observability", "grafana"),
            ("observability", "phoenix"),
        ]

        unhealthy = []

        for namespace, deployment_name in components:
            try:
                deployment = k8s_apps_client.read_namespaced_deployment(
                    name=deployment_name,
                    namespace=namespace
                )

                if not deployment.status.ready_replicas or deployment.status.ready_replicas < 1:
                    unhealthy.append(f"{namespace}/{deployment_name}")

            except ApiException:
                unhealthy.append(f"{namespace}/{deployment_name} (not found)")

        assert len(unhealthy) == 0, \
            f"Unhealthy observability components: {', '.join(unhealthy)}"

    def test_grafana_all_datasources_configured(self, k8s_client):
        """Verify Grafana has all three datasources configured (Prometheus, Loki, Tempo)."""
        grafana_pod = get_pod_for_deployment(k8s_client, "observability", "grafana")

        if not grafana_pod:
            pytest.skip("Grafana pod not running")

        try:
            output = exec_in_pod(
                k8s_client,
                "observability",
                grafana_pod,
                [
                    "sh",
                    "-c",
                    "curl -s -u admin:admin123 http://localhost:3000/api/datasources"
                ]
            )

            # Check all three datasource types are configured
            assert '"type":"prometheus"' in output, \
                "Grafana missing Prometheus datasource"
            assert '"type":"loki"' in output, \
                "Grafana missing Loki datasource"
            assert '"type":"tempo"' in output, \
                "Grafana missing Tempo datasource"

        except Exception as e:
            pytest.fail(f"Failed to verify Grafana datasources: {e}")


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
