"""
Test suite for scanning logs and traces for errors and warnings.

This test suite validates that the platform is running cleanly with zero
unexpected errors or warnings in:
- Kubernetes pod logs
- Phoenix LLM traces
- Tempo distributed traces

Target: 0 errors/warnings (with configurable ignore list for acceptable patterns)
"""

import pytest
import re
import subprocess
import json
import time
from typing import List, Dict, Set, Tuple, Any
from kubernetes import client, config
from gql import gql, Client
from gql.transport.requests import RequestsHTTPTransport


# ============================================================================
# CONFIGURATION
# ============================================================================

# Namespaces to scan for pod logs
NAMESPACES_TO_SCAN = [
    "kagenti-system",
    "observability",
    "istio-system",
    "gateway-system",
]

# Patterns to identify errors and warnings in logs
ERROR_PATTERNS = [
    r"\bERROR\b",
    r"\bFATAL\b",
    r"\bCRITICAL\b",
    r"\bFAILED\b",
    r"\bException\b",
    r"\bTraceback\b",
    r"\bpanic\b",
    r"level=error",
    r"severity=error",
    r'"level":"error"',
    r'"severity":"error"',
]

WARNING_PATTERNS = [
    r"\bWARN(?:ING)?\b",
    r"\bCAUTION\b",
    r"level=warn",
    r"severity=warn",
    r'"level":"warn"',
    r'"severity":"warn"',
]

# Known acceptable errors/warnings (regex patterns)
# These are platform-specific issues that are safe to ignore
ACCEPTABLE_ERRORS = [
    # Istio sidecar injection warnings during startup
    r"Readiness probe failed.*not yet received INIT",
    r"Liveness probe failed.*not yet received INIT",

    # Istio proxy startup info logs that contain "error" in config parameters
    r"info\s+FLAG:.*error",
    r"info\s+Envoy command:.*error",

    # Webhook configuration warnings (expected during cluster bootstrap)
    r"failed calling webhook.*connection refused",
    r"error getting webhook.*not found",
    r"failed to verify certificate: x509: certificate is not valid for any names",

    # Temporary network errors during pod initialization
    r"dial tcp.*connection refused.*during startup",
    r"connect: connection refused.*container starting",
    r"connection reset by peer",

    # ArgoCD sync warnings (expected during automated sync)
    r"ComparisonError.*resource is being applied",
    r"out of sync.*sync in progress",

    # Cert-manager certificate issuance warnings (temporary)
    r"failed to verify.*certificate not yet issued",
    r"Issuing certificate.*in progress",

    # Keycloak initialization warnings
    r"KC-SERVICES0027.*theme not found.*using default",

    # Phoenix experimental features warnings
    r"ExperimentalWarning",

    # Tempo startup warnings
    r"failed to find trace.*no results yet",

    # Expected RBAC denials during bootstrap
    r"User.*cannot create.*in the namespace.*forbidden",

    # Graceful shutdown messages
    r"context canceled",
    r"server closed",

    # Kubernetes operator leader election (expected during multi-replica controllers)
    r"error retrieving resource lock.*client rate limiter Wait returned an error",
    r"leaderelection\.go.*error retrieving resource lock",

    # TLS handshake errors (Istio/Envoy during startup and connection attempts)
    r"http: TLS handshake error.*EOF",

    # Agent build errors (Tekton ConfigMaps not deployed in Kind cluster)
    r"Failed to trigger build.*step ConfigMap.*not found",
    r"failed to load pipeline steps",
    r"Reconciler error.*failed calling webhook",

    # Alertmanager webhook errors (korrel8r not deployed in local Kind)
    r"lookup korrel8r\.observability\.svc.*no such host",
    r"dial tcp: lookup.*lame referral",

    # Grafana plugin errors (duplicate registration - known Grafana issue)
    r"plugin xychart is already registered",

    # Loki internal errors (scheduler coordination)
    r"error notifying scheduler about finished query.*EOF",

    # OTel Collector errors (expected - no Docker daemon in Kubernetes pods)
    r"failed to fetch Docker OS type.*Cannot connect to the Docker daemon",
    r"failed to detect resource.*failed getting OS type",

    # Grafana ngalert INFO logs containing "Error" in mode descriptions
    r"logger=ngalert.*level=info.*Error/NoData mode",

    # Grafana Loki datasource INFO logs with queries searching for errors (query contains error/ERROR)
    r"logger=tsdb\.loki.*level=info.*query=.*error",

    # Grafana rule store errors (local store limitation - expected)
    r"GetRuleGroup unsupported in rule local store",

    # Grafana database locked INFO logs (SQLite retry mechanism - expected)
    r"logger=sqlstore\.transactions.*level=info.*Database locked.*sleeping then retrying",

    # Grafana database locked ERROR logs (SQLite concurrent access - expected in dev)
    r"logger=secrets\.kvstore.*level=error.*database is locked",
    r"logger=ngalert\.scheduler.*level=error.*database is locked",
    r"logger=ngalert\.state\.manager.*level=error.*database is locked",

    # Loki single-replica coordination errors (expected in single-replica mode)
    r"level=error.*error asking ring for who should run the compactor.*could only find 0",
    r"level=error.*unable to get stream rates from ingester.*DeadlineExceeded",
    r"level=error.*error getting addresses from ring.*could only find 0",
    r"level=error.*failed to query the ring.*could only find 0",

    # Loki log labels containing "error" (not actual errors - just label values)
    r'level=info.*flushing stream.*level=\\"error\\"',

    # Tempo structured logging (INFO logs with error field names, not actual errors)
    r"level=info.*error=null",
    r"level=info.*error=",

    # OTel Collector gRPC startup connection warnings (tempo-collector not ready yet)
    r"warn\s+zapgrpc.*grpc: addrConn\.createTransport failed.*connection refused",
    r"warn\s+zapgrpc.*grpc: addrConn\.createTransport failed.*i/o timeout",
    r"warn\s+zapgrpc.*grpc: addrConn\.createTransport failed.*operation was canceled",

    # Istio proxy health check timeouts during pod startup
    r"error\s+Request to probe app failed.*context deadline exceeded",

    # Kagenti operator Tekton build INFO/DEBUG logs (reporting build status including failures)
    r"INFO\s+tekton Pipeline Build.*Failed",
    r"DEBUG\s+events\s+Build failed",

    # Kagenti operator reconciliation errors (resource deleted, controller cleanup)
    r"ERROR\s+Reconciler error.*not found",
]

ACCEPTABLE_WARNINGS = [
    # Kubernetes standard warnings
    r"Back-off restarting failed container.*during startup",
    r"Waiting for.*to be ready",

    # Istio warnings
    r"envoy.*downstream protocol error",

    # ArgoCD warnings
    r"reconciliation.*in progress",

    # Tekton warnings
    r"failed to get task run.*not found",

    # Envoy/Istio proxy warnings (deprecated config, expected)
    r"Usage of the deprecated runtime key overload\.global_downstream_max_connections",
    r"no configured limit to the number of allowed active downstream connections",

    # Agent build warnings (Tekton not deployed in Kind)
    r'"type": "Warning".*Pipeline run not found',
    r'"type": "Warning".*Failed to start build',

    # Grafana authentication warnings (expected - anonymous/initial requests)
    r"Failed to authenticate request.*user token not found",

    # OTel Collector startup warnings (expected)
    r"failed to detect resource.*Docker",
    r"connection refused.*tempo-collector",

    # Tempo security warnings (0.0.0.0 binding)
    r"Using the 0\.0\.0\.0 address exposes this server",
    r"UseLocalHostAsDefaultHost",

    # Istio proxy INFO logs containing "warning" in config flags
    r"info\s+FLAG:.*--proxyLogLevel.*warning",
]


# ============================================================================
# FIXTURES
# ============================================================================

@pytest.fixture(scope="module")
def k8s_client():
    """Initialize Kubernetes client."""
    try:
        config.load_kube_config()
    except:
        config.load_incluster_config()
    return client.CoreV1Api()


@pytest.fixture(scope="module")
def phoenix_graphql_client():
    """Initialize Phoenix GraphQL client with port-forward."""
    # Start port-forward to Phoenix
    port_forward = subprocess.Popen(
        [
            "kubectl", "port-forward",
            "-n", "observability",
            "service/phoenix", "6006:6006"
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    try:
        # Wait for port-forward to be ready
        time.sleep(3)

        transport = RequestsHTTPTransport(
            url="http://localhost:6006/graphql",
            timeout=10
        )
        client = Client(transport=transport, fetch_schema_from_transport=False)

        yield client
    finally:
        port_forward.terminate()
        port_forward.wait()


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def is_acceptable_error(log_line: str, acceptable_patterns: List[str]) -> bool:
    """
    Check if an error/warning matches acceptable patterns.

    Args:
        log_line: The log line to check
        acceptable_patterns: List of regex patterns for acceptable errors

    Returns:
        True if the error is acceptable, False otherwise
    """
    for pattern in acceptable_patterns:
        if re.search(pattern, log_line, re.IGNORECASE):
            return True
    return False


def extract_errors_from_logs(
    logs: str,
    error_patterns: List[str],
    acceptable_patterns: List[str]
) -> List[str]:
    """
    Extract unacceptable errors from pod logs.

    Args:
        logs: Pod logs as string
        error_patterns: Patterns to identify errors
        acceptable_patterns: Patterns for acceptable errors

    Returns:
        List of unacceptable error log lines
    """
    errors = []

    for line in logs.split("\n"):
        # Skip empty lines
        if not line.strip():
            continue

        # Check if line contains an error
        for pattern in error_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                # Check if it's an acceptable error
                if not is_acceptable_error(line, acceptable_patterns):
                    errors.append(line.strip())
                break

    return errors


def extract_warnings_from_logs(
    logs: str,
    warning_patterns: List[str],
    acceptable_patterns: List[str]
) -> List[str]:
    """
    Extract unacceptable warnings from pod logs.

    Args:
        logs: Pod logs as string
        warning_patterns: Patterns to identify warnings
        acceptable_patterns: Patterns for acceptable warnings

    Returns:
        List of unacceptable warning log lines
    """
    warnings = []

    for line in logs.split("\n"):
        # Skip empty lines
        if not line.strip():
            continue

        # Check if line contains a warning
        for pattern in warning_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                # Check if it's an acceptable warning
                if not is_acceptable_error(line, acceptable_patterns):
                    warnings.append(line.strip())
                break

    return warnings


def get_pod_logs(
    k8s_client: client.CoreV1Api,
    namespace: str,
    pod_name: str,
    container_name: str = None,
    tail_lines: int = 1000
) -> str:
    """
    Get logs from a pod/container.

    Args:
        k8s_client: Kubernetes client
        namespace: Pod namespace
        pod_name: Pod name
        container_name: Container name (optional)
        tail_lines: Number of lines to retrieve from end

    Returns:
        Pod logs as string
    """
    try:
        return k8s_client.read_namespaced_pod_log(
            name=pod_name,
            namespace=namespace,
            container=container_name,
            tail_lines=tail_lines
        )
    except Exception as e:
        return f"Error retrieving logs: {str(e)}"


# ============================================================================
# POD LOG TESTS
# ============================================================================

@pytest.mark.parametrize("namespace", NAMESPACES_TO_SCAN)
def test_no_errors_in_pod_logs(k8s_client, namespace):
    """
    Test that pod logs contain no unexpected errors.

    Scans all pods in the namespace and checks for error patterns
    that are not in the acceptable list.
    """
    all_errors = {}

    # Get all pods in namespace
    try:
        pods = k8s_client.list_namespaced_pod(namespace=namespace)
    except Exception as e:
        pytest.skip(f"Cannot access namespace {namespace}: {str(e)}")
        return

    # Scan each pod
    for pod in pods.items:
        pod_name = pod.metadata.name

        # Skip completed/failed pods
        if pod.status.phase in ["Succeeded", "Failed"]:
            continue

        # Scan each container
        for container in pod.spec.containers:
            container_name = container.name

            # Get logs
            logs = get_pod_logs(
                k8s_client,
                namespace,
                pod_name,
                container_name
            )

            # Extract errors
            errors = extract_errors_from_logs(
                logs,
                ERROR_PATTERNS,
                ACCEPTABLE_ERRORS
            )

            if errors:
                key = f"{namespace}/{pod_name}/{container_name}"
                all_errors[key] = errors

    # Assert no unacceptable errors found
    if all_errors:
        error_report = "\n\n".join([
            f"{location}:\n  " + "\n  ".join(errors)
            for location, errors in all_errors.items()
        ])
        pytest.fail(
            f"Found {sum(len(e) for e in all_errors.values())} "
            f"unacceptable errors in {len(all_errors)} containers:\n\n{error_report}"
        )


@pytest.mark.parametrize("namespace", NAMESPACES_TO_SCAN)
def test_no_warnings_in_pod_logs(k8s_client, namespace):
    """
    Test that pod logs contain no unexpected warnings.

    Scans all pods in the namespace and checks for warning patterns
    that are not in the acceptable list.
    """
    all_warnings = {}

    # Get all pods in namespace
    try:
        pods = k8s_client.list_namespaced_pod(namespace=namespace)
    except Exception as e:
        pytest.skip(f"Cannot access namespace {namespace}: {str(e)}")
        return

    # Scan each pod
    for pod in pods.items:
        pod_name = pod.metadata.name

        # Skip completed/failed pods
        if pod.status.phase in ["Succeeded", "Failed"]:
            continue

        # Scan each container
        for container in pod.spec.containers:
            container_name = container.name

            # Get logs
            logs = get_pod_logs(
                k8s_client,
                namespace,
                pod_name,
                container_name
            )

            # Extract warnings
            warnings = extract_warnings_from_logs(
                logs,
                WARNING_PATTERNS,
                ACCEPTABLE_WARNINGS
            )

            if warnings:
                key = f"{namespace}/{pod_name}/{container_name}"
                all_warnings[key] = warnings

    # Assert no unacceptable warnings found
    if all_warnings:
        warning_report = "\n\n".join([
            f"{location}:\n  " + "\n  ".join(warnings)
            for location, warnings in all_warnings.items()
        ])
        pytest.fail(
            f"Found {sum(len(w) for w in all_warnings.values())} "
            f"unacceptable warnings in {len(all_warnings)} containers:\n\n{warning_report}"
        )


# ============================================================================
# PHOENIX TRACE TESTS
# ============================================================================

@pytest.mark.xfail(reason="Phoenix may not have traces yet in fresh deployment")
def test_no_errors_in_phoenix_traces(phoenix_graphql_client):
    """
    Test that Phoenix traces contain no error spans.

    Queries Phoenix for recent traces and checks for spans with error status.
    """
    query = gql("""
    query GetRecentTraces {
      traces(first: 100, sort: {col: startTime, dir: desc}) {
        edges {
          node {
            traceId
            spans {
              spanId
              name
              statusCode
              statusMessage
              events {
                name
                message
              }
            }
          }
        }
      }
    }
    """)

    try:
        result = phoenix_graphql_client.execute(query)
    except Exception as e:
        pytest.skip(f"Cannot query Phoenix: {str(e)}")
        return

    error_traces = []

    # Check each trace for error spans
    if result and "traces" in result and "edges" in result["traces"]:
        for edge in result["traces"]["edges"]:
            trace = edge["node"]
            trace_id = trace["traceId"]

            for span in trace["spans"]:
                # Check for error status code (ERROR = 2 in OpenTelemetry)
                if span.get("statusCode") == "ERROR":
                    error_traces.append({
                        "trace_id": trace_id,
                        "span_id": span["spanId"],
                        "span_name": span["name"],
                        "status_message": span.get("statusMessage", "")
                    })

                # Check for error events
                for event in span.get("events", []):
                    if "error" in event.get("name", "").lower():
                        error_traces.append({
                            "trace_id": trace_id,
                            "span_id": span["spanId"],
                            "span_name": span["name"],
                            "event_name": event["name"],
                            "event_message": event.get("message", "")
                        })

    # Assert no errors found
    if error_traces:
        error_report = "\n".join([
            f"Trace {e['trace_id']}, Span {e['span_id']} ({e['span_name']}): "
            f"{e.get('status_message') or e.get('event_message', '')}"
            for e in error_traces
        ])
        pytest.fail(
            f"Found {len(error_traces)} error spans in Phoenix traces:\n{error_report}"
        )


# ============================================================================
# TEMPO TRACE TESTS
# ============================================================================

@pytest.mark.xfail(reason="Tempo may not have traces yet in fresh deployment")
def test_no_errors_in_tempo_traces():
    """
    Test that Tempo traces contain no error spans.

    Queries Tempo for recent traces and checks for spans with error status.
    """
    # Start port-forward to Tempo
    port_forward = subprocess.Popen(
        [
            "kubectl", "port-forward",
            "-n", "observability",
            "service/tempo", "3200:3200"
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    try:
        # Wait for port-forward
        time.sleep(3)

        # Query Tempo search API
        result = subprocess.run(
            [
                "curl", "-s",
                "http://localhost:3200/api/search",
                "--data-urlencode", "limit=100"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            pytest.skip(f"Cannot query Tempo: {result.stderr}")
            return

        search_results = json.loads(result.stdout)
        error_traces = []

        # Check each trace
        for trace_summary in search_results.get("traces", []):
            trace_id = trace_summary.get("traceID")

            # Get full trace
            trace_result = subprocess.run(
                [
                    "curl", "-s",
                    f"http://localhost:3200/api/traces/{trace_id}"
                ],
                capture_output=True,
                text=True,
                timeout=10
            )

            if trace_result.returncode != 0:
                continue

            trace_data = json.loads(trace_result.stdout)

            # Check for error status in spans
            for batch in trace_data.get("batches", []):
                for span in batch.get("spans", []):
                    status = span.get("status", {})
                    if status.get("code") == 2:  # ERROR in OpenTelemetry
                        error_traces.append({
                            "trace_id": trace_id,
                            "span_name": span.get("name"),
                            "status_message": status.get("message", "")
                        })

        # Assert no errors found
        if error_traces:
            error_report = "\n".join([
                f"Trace {e['trace_id']}, Span {e['span_name']}: {e['status_message']}"
                for e in error_traces
            ])
            pytest.fail(
                f"Found {len(error_traces)} error spans in Tempo traces:\n{error_report}"
            )

    finally:
        port_forward.terminate()
        port_forward.wait()


# ============================================================================
# SUMMARY TEST
# ============================================================================

def test_generate_error_warning_summary(k8s_client):
    """
    Generate a comprehensive summary of all errors and warnings.

    This test always passes but generates a detailed report of all
    errors and warnings found across the platform (including acceptable ones).
    """
    summary = {
        "total_errors": 0,
        "total_warnings": 0,
        "acceptable_errors": 0,
        "acceptable_warnings": 0,
        "by_namespace": {}
    }

    # Scan all namespaces
    for namespace in NAMESPACES_TO_SCAN:
        try:
            pods = k8s_client.list_namespaced_pod(namespace=namespace)
        except:
            continue

        namespace_summary = {
            "errors": 0,
            "warnings": 0,
            "pods": {}
        }

        # Scan each pod
        for pod in pods.items:
            if pod.status.phase in ["Succeeded", "Failed"]:
                continue

            pod_name = pod.metadata.name

            for container in pod.spec.containers:
                container_name = container.name
                logs = get_pod_logs(k8s_client, namespace, pod_name, container_name)

                # Extract all errors (including acceptable)
                all_errors = []
                for line in logs.split("\n"):
                    for pattern in ERROR_PATTERNS:
                        if re.search(pattern, line, re.IGNORECASE):
                            all_errors.append(line.strip())
                            break

                # Extract all warnings (including acceptable)
                all_warnings = []
                for line in logs.split("\n"):
                    for pattern in WARNING_PATTERNS:
                        if re.search(pattern, line, re.IGNORECASE):
                            all_warnings.append(line.strip())
                            break

                if all_errors or all_warnings:
                    namespace_summary["pods"][f"{pod_name}/{container_name}"] = {
                        "errors": len(all_errors),
                        "warnings": len(all_warnings)
                    }
                    namespace_summary["errors"] += len(all_errors)
                    namespace_summary["warnings"] += len(all_warnings)

        if namespace_summary["errors"] or namespace_summary["warnings"]:
            summary["by_namespace"][namespace] = namespace_summary
            summary["total_errors"] += namespace_summary["errors"]
            summary["total_warnings"] += namespace_summary["warnings"]

    # Print summary
    print("\n" + "=" * 80)
    print("ERROR AND WARNING SUMMARY")
    print("=" * 80)
    print(f"\nTotal Errors:   {summary['total_errors']}")
    print(f"Total Warnings: {summary['total_warnings']}")
    print("\nBy Namespace:")
    for ns, ns_summary in summary["by_namespace"].items():
        print(f"\n  {ns}:")
        print(f"    Errors:   {ns_summary['errors']}")
        print(f"    Warnings: {ns_summary['warnings']}")
        print(f"    Pods with issues: {len(ns_summary['pods'])}")
    print("\n" + "=" * 80)
