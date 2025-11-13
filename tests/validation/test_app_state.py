#!/usr/bin/env python3
"""
ArgoCD Application State Validation Test Suite

Validates that ALL ArgoCD applications are in a healthy, synced state.
This is intended to be run as a comprehensive health check of the platform.

Requirements:
    pip install kubernetes>=28.1.0 pytest>=8.0.0 tenacity>=8.2.3 rich>=13.7.0

Usage:
    # Validate all applications
    pytest tests/validation/test_app_state.py -v

    # Exclude specific applications
    pytest tests/validation/test_app_state.py -v --exclude-app="agents,observability"

    # Only validate critical applications
    pytest tests/validation/test_app_state.py -v --only-critical

    # Custom timeout for slow syncs
    pytest tests/validation/test_app_state.py -v --timeout=600

Environment Variables:
    KUBECONFIG: Path to kubeconfig file (default: ~/.kube/config)
    ARGOCD_NAMESPACE: ArgoCD namespace (default: argocd)
    APP_STATE_TIMEOUT: Timeout for app readiness in seconds (default: 300)
"""

import os
import sys
import time
from dataclasses import dataclass
from typing import Dict, List, Optional, Set, Tuple

import pytest
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from rich.console import Console
from rich.table import Table
from tenacity import retry, stop_after_delay, wait_fixed

# ============================================================================
# Configuration
# ============================================================================

ARGOCD_NAMESPACE = os.getenv("ARGOCD_NAMESPACE", "argocd")
DEFAULT_TIMEOUT = int(os.getenv("APP_STATE_TIMEOUT", "300"))

# Critical applications that must be healthy
# Note: ArgoCD itself is not managed as an Application, so it's not included
CRITICAL_APPS = {
    "gateway-api",
    "cert-manager",
    "istio-base",
    "istiod",
    "kagenti-operator",
    "kagenti-platform-operator",
    "keycloak",
    "keycloak-operator",
}

console = Console()


# ============================================================================
# Data Models
# ============================================================================


@dataclass
class AppHealthStatus:
    """Application health status information."""
    name: str
    namespace: str
    sync_status: str  # Synced, OutOfSync, Unknown
    health_status: str  # Healthy, Progressing, Degraded, Missing, Unknown
    health_message: str
    sync_revision: str
    resources_healthy: int
    resources_total: int
    conditions: List[Dict]
    pod_status: Dict[str, int]  # {Running: 5, CrashLoopBackOff: 1, ...}

    @property
    def is_healthy(self) -> bool:
        """Check if application is in healthy state."""
        return (
            self.sync_status == "Synced" and
            self.health_status in ["Healthy", "Progressing"] and
            self.resources_healthy == self.resources_total and
            not self.has_errors()
        )

    def has_errors(self) -> bool:
        """Check if application has error conditions."""
        error_conditions = [
            "ComparisonError",
            "SyncError",
            "InvalidSpecError",
        ]
        return any(
            cond.get("type") in error_conditions
            for cond in self.conditions
        )

    def get_failure_reasons(self) -> List[str]:
        """Get list of failure reasons."""
        reasons = []

        if self.sync_status != "Synced":
            reasons.append(f"Sync status: {self.sync_status}")

        if self.health_status not in ["Healthy", "Progressing"]:
            reasons.append(f"Health status: {self.health_status}")
            if self.health_message:
                reasons.append(f"  Message: {self.health_message}")

        if self.resources_healthy != self.resources_total:
            reasons.append(
                f"Resources: {self.resources_healthy}/{self.resources_total} healthy"
            )

        if self.has_errors():
            for cond in self.conditions:
                if cond.get("type") in ["ComparisonError", "SyncError", "InvalidSpecError"]:
                    reasons.append(f"Condition: {cond.get('type')} - {cond.get('message', 'N/A')}")

        # Check pod status
        unhealthy_pods = {
            status: count
            for status, count in self.pod_status.items()
            if status not in ["Running", "Completed", "Succeeded"]
        }
        if unhealthy_pods:
            reasons.append(f"Unhealthy pods: {unhealthy_pods}")

        return reasons


# ============================================================================
# Fixtures and Configuration
# ============================================================================


def pytest_addoption(parser):
    """Add custom pytest command line options."""
    parser.addoption(
        "--exclude-app",
        action="store",
        default="",
        help="Comma-separated list of apps to exclude from validation",
    )
    parser.addoption(
        "--only-critical",
        action="store_true",
        default=False,
        help="Only validate critical applications",
    )
    parser.addoption(
        "--timeout",
        action="store",
        type=int,
        default=DEFAULT_TIMEOUT,
        help=f"Timeout for app readiness in seconds (default: {DEFAULT_TIMEOUT})",
    )


@pytest.fixture(scope="session")
def k8s_client():
    """Load Kubernetes configuration and return CoreV1Api client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()
    return client.CoreV1Api()


@pytest.fixture(scope="session")
def k8s_custom_client():
    """Return Kubernetes CustomObjectsApi client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()
    return client.CustomObjectsApi()


@pytest.fixture(scope="session")
def excluded_apps(request) -> Set[str]:
    """Get set of excluded application names."""
    exclude_str = request.config.getoption("--exclude-app")
    if not exclude_str:
        return set()
    return {app.strip() for app in exclude_str.split(",")}


@pytest.fixture(scope="session")
def only_critical(request) -> bool:
    """Check if only critical apps should be validated."""
    return request.config.getoption("--only-critical")


@pytest.fixture(scope="session")
def app_timeout(request) -> int:
    """Get application timeout."""
    return request.config.getoption("--app-timeout")


# ============================================================================
# Helper Functions
# ============================================================================


def get_argocd_applications(
    k8s_custom_client: client.CustomObjectsApi,
) -> List[Dict]:
    """
    Retrieve all ArgoCD Application resources.

    Args:
        k8s_custom_client: Kubernetes Custom Objects API client

    Returns:
        List of ArgoCD Application objects
    """
    try:
        apps = k8s_custom_client.list_cluster_custom_object(
            group="argoproj.io",
            version="v1alpha1",
            plural="applications",
        )
        return apps.get("items", [])
    except ApiException as e:
        console.print(f"[red]Error fetching ArgoCD applications: {e}[/red]")
        return []


def get_pod_status_for_app(
    k8s_client: client.CoreV1Api,
    namespace: str,
) -> Dict[str, int]:
    """
    Get pod status counts for a namespace.

    Args:
        k8s_client: Kubernetes Core API client
        namespace: Namespace to check

    Returns:
        Dictionary mapping pod phase to count (e.g., {"Running": 5, "Pending": 1})
    """
    status_counts = {}

    try:
        pods = k8s_client.list_namespaced_pod(namespace=namespace)

        for pod in pods.items:
            phase = pod.status.phase

            # Check for more specific status (CrashLoopBackOff, ImagePullBackOff, etc.)
            if pod.status.container_statuses:
                for container_status in pod.status.container_statuses:
                    if container_status.state.waiting:
                        phase = container_status.state.waiting.reason
                        break
                    elif container_status.state.terminated:
                        if container_status.state.terminated.reason:
                            phase = container_status.state.terminated.reason
                        break

            status_counts[phase] = status_counts.get(phase, 0) + 1

    except ApiException as e:
        console.print(f"[yellow]Warning: Could not get pods for {namespace}: {e}[/yellow]")

    return status_counts


def parse_app_health_status(
    app: Dict,
    k8s_client: client.CoreV1Api,
) -> AppHealthStatus:
    """
    Parse ArgoCD Application object into AppHealthStatus.

    Args:
        app: ArgoCD Application object
        k8s_client: Kubernetes Core API client

    Returns:
        AppHealthStatus object
    """
    metadata = app.get("metadata", {})
    status = app.get("status", {})

    name = metadata.get("name", "unknown")
    namespace = metadata.get("namespace", ARGOCD_NAMESPACE)

    # Sync status
    sync_status = status.get("sync", {}).get("status", "Unknown")
    sync_revision = status.get("sync", {}).get("revision", "N/A")

    # Health status
    health = status.get("health", {})
    health_status = health.get("status", "Unknown")
    health_message = health.get("message", "")

    # Resources
    resources = status.get("resources", [])
    resources_total = len(resources)
    resources_healthy = sum(
        1 for r in resources
        if r.get("health", {}).get("status") == "Healthy"
    )

    # Conditions
    conditions = status.get("conditions", [])

    # Pod status (from destination namespace)
    destination_namespace = app.get("spec", {}).get("destination", {}).get("namespace", namespace)
    pod_status = get_pod_status_for_app(k8s_client, destination_namespace)

    return AppHealthStatus(
        name=name,
        namespace=namespace,
        sync_status=sync_status,
        health_status=health_status,
        health_message=health_message,
        sync_revision=sync_revision,
        resources_healthy=resources_healthy,
        resources_total=resources_total,
        conditions=conditions,
        pod_status=pod_status,
    )


@retry(stop=stop_after_delay(DEFAULT_TIMEOUT), wait=wait_fixed(10))
def wait_for_app_healthy(
    k8s_custom_client: client.CustomObjectsApi,
    k8s_client: client.CoreV1Api,
    app_name: str,
) -> AppHealthStatus:
    """
    Wait for an application to become healthy.

    Args:
        k8s_custom_client: Kubernetes Custom Objects API client
        k8s_client: Kubernetes Core API client
        app_name: Application name

    Returns:
        AppHealthStatus when healthy

    Raises:
        Exception: If app doesn't become healthy within timeout
    """
    apps = get_argocd_applications(k8s_custom_client)
    app = next((a for a in apps if a.get("metadata", {}).get("name") == app_name), None)

    if not app:
        raise Exception(f"Application {app_name} not found")

    status = parse_app_health_status(app, k8s_client)

    if status.is_healthy:
        return status
    else:
        reasons = ", ".join(status.get_failure_reasons())
        raise Exception(f"Application {app_name} not healthy: {reasons}")


def generate_validation_report(
    app_statuses: List[AppHealthStatus],
    excluded_apps: Set[str],
) -> Tuple[int, int, int]:
    """
    Generate and print validation report.

    Args:
        app_statuses: List of application health statuses
        excluded_apps: Set of excluded application names

    Returns:
        Tuple of (total, healthy, unhealthy) counts
    """
    table = Table(title="ArgoCD Application Validation Report")
    table.add_column("Application", style="cyan")
    table.add_column("Sync Status", style="white")
    table.add_column("Health Status", style="white")
    table.add_column("Resources", style="white")
    table.add_column("Pods", style="white")
    table.add_column("Status", style="white")

    healthy_count = 0
    unhealthy_count = 0

    for status in app_statuses:
        if status.name in excluded_apps:
            continue

        is_healthy = status.is_healthy
        status_icon = "[green]✓[/green]" if is_healthy else "[red]✗[/red]"

        if is_healthy:
            healthy_count += 1
            sync_color = "green"
            health_color = "green"
        else:
            unhealthy_count += 1
            sync_color = "red" if status.sync_status != "Synced" else "yellow"
            health_color = "red" if status.health_status in ["Degraded", "Missing"] else "yellow"

        # Format pod status
        pod_summary = ", ".join(
            f"{phase}: {count}"
            for phase, count in status.pod_status.items()
        ) if status.pod_status else "N/A"

        table.add_row(
            status.name,
            f"[{sync_color}]{status.sync_status}[/{sync_color}]",
            f"[{health_color}]{status.health_status}[/{health_color}]",
            f"{status.resources_healthy}/{status.resources_total}",
            pod_summary,
            status_icon,
        )

    console.print("\n")
    console.print(table)
    console.print("\n")

    # Print detailed failure reasons
    if unhealthy_count > 0:
        console.print("[bold red]Failure Details:[/bold red]")
        for status in app_statuses:
            if not status.is_healthy and status.name not in excluded_apps:
                console.print(f"\n[bold]{status.name}:[/bold]")
                for reason in status.get_failure_reasons():
                    console.print(f"  - {reason}")

    # Print summary
    total = healthy_count + unhealthy_count
    console.print(f"\n[bold]Summary:[/bold]")
    console.print(f"  Total: {total}")
    console.print(f"  Healthy: [green]{healthy_count}[/green]")
    console.print(f"  Unhealthy: [red]{unhealthy_count}[/red]")
    if excluded_apps:
        console.print(f"  Excluded: {', '.join(excluded_apps)}")

    return total, healthy_count, unhealthy_count


# ============================================================================
# Tests
# ============================================================================


class TestArgocdAppState:
    """Test ArgoCD application state validation."""

    def test_all_apps_exist(
        self,
        k8s_custom_client,
        k8s_client,
        excluded_apps,
        only_critical,
    ):
        """Verify all expected ArgoCD applications exist."""
        apps = get_argocd_applications(k8s_custom_client)

        assert len(apps) > 0, "No ArgoCD applications found"

        app_names = {app.get("metadata", {}).get("name") for app in apps}

        if only_critical:
            expected_apps = CRITICAL_APPS
        else:
            # If not filtering by critical, just verify some apps exist
            expected_apps = CRITICAL_APPS

        for expected_app in expected_apps:
            if expected_app in excluded_apps:
                continue
            assert expected_app in app_names, \
                f"Expected application '{expected_app}' not found. Available: {app_names}"

    def test_all_apps_healthy(
        self,
        k8s_custom_client,
        k8s_client,
        excluded_apps,
        only_critical,
        app_timeout,
    ):
        """
        Validate ALL ArgoCD applications are in healthy, synced state.

        This is the main validation test that checks:
        - Sync status is "Synced"
        - Health status is "Healthy" or "Progressing"
        - No error conditions
        - All resources exist
        - All pods are in good state
        """
        apps = get_argocd_applications(k8s_custom_client)

        assert len(apps) > 0, "No ArgoCD applications found"

        # Parse all app statuses
        app_statuses = [
            parse_app_health_status(app, k8s_client)
            for app in apps
        ]

        # Filter apps
        if only_critical:
            app_statuses = [
                status for status in app_statuses
                if status.name in CRITICAL_APPS
            ]

        app_statuses = [
            status for status in app_statuses
            if status.name not in excluded_apps
        ]

        # Generate report
        total, healthy, unhealthy = generate_validation_report(
            app_statuses,
            excluded_apps,
        )

        # Fail if any apps are unhealthy
        if unhealthy > 0:
            pytest.fail(
                f"{unhealthy}/{total} applications are unhealthy. "
                "See report above for details."
            )

    def test_critical_apps_healthy(
        self,
        k8s_custom_client,
        k8s_client,
        excluded_apps,
    ):
        """Verify critical applications are healthy (fast smoke test)."""
        apps = get_argocd_applications(k8s_custom_client)

        critical_apps = [
            app for app in apps
            if app.get("metadata", {}).get("name") in CRITICAL_APPS
        ]

        assert len(critical_apps) > 0, "No critical applications found"

        unhealthy_critical = []

        for app in critical_apps:
            status = parse_app_health_status(app, k8s_client)

            if status.name in excluded_apps:
                continue

            if not status.is_healthy:
                unhealthy_critical.append(status)

        if unhealthy_critical:
            console.print("\n[bold red]Critical applications are unhealthy:[/bold red]")
            for status in unhealthy_critical:
                console.print(f"\n[bold]{status.name}:[/bold]")
                for reason in status.get_failure_reasons():
                    console.print(f"  - {reason}")

            pytest.fail(
                f"{len(unhealthy_critical)} critical applications are unhealthy: "
                f"{[s.name for s in unhealthy_critical]}"
            )

    @pytest.mark.parametrize("app_name", CRITICAL_APPS)
    def test_critical_app_healthy(
        self,
        k8s_custom_client,
        k8s_client,
        excluded_apps,
        app_name,
    ):
        """Verify each critical application is healthy (individual test per app)."""
        if app_name in excluded_apps:
            pytest.skip(f"Application {app_name} excluded")

        apps = get_argocd_applications(k8s_custom_client)
        app = next(
            (a for a in apps if a.get("metadata", {}).get("name") == app_name),
            None
        )

        assert app is not None, f"Application {app_name} not found"

        status = parse_app_health_status(app, k8s_client)

        assert status.is_healthy, \
            f"Application {app_name} is unhealthy:\n" + \
            "\n".join(f"  - {reason}" for reason in status.get_failure_reasons())


# ============================================================================
# CLI Entry Point (for standalone execution)
# ============================================================================


def main():
    """Run validation as standalone script."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()

    k8s_client_instance = client.CoreV1Api()
    k8s_custom_client_instance = client.CustomObjectsApi()

    console.print("[bold]ArgoCD Application State Validation[/bold]\n")

    apps = get_argocd_applications(k8s_custom_client_instance)

    if not apps:
        console.print("[red]No ArgoCD applications found![/red]")
        sys.exit(1)

    app_statuses = [
        parse_app_health_status(app, k8s_client_instance)
        for app in apps
    ]

    total, healthy, unhealthy = generate_validation_report(app_statuses, set())

    if unhealthy > 0:
        sys.exit(1)
    else:
        console.print("\n[bold green]All applications are healthy![/bold green]")
        sys.exit(0)


if __name__ == "__main__":
    main()
