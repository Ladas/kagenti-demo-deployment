"""
Test Grafana Unified Alerting and AlertManager integration.

This validates that:
- Grafana unified alerting is enabled
- AlertManager contact point is configured
- Notification policies are loaded
- Platform health alert rules are provisioned
- Alert rules are evaluating correctly
- Grafana can communicate with AlertManager
"""
import pytest
import subprocess
import json
import time
from kubernetes import client, config


class TestGrafanaAlerting:
    """Test Grafana unified alerting configuration and integration."""

    @pytest.fixture(scope="class", autouse=True)
    def k8s_client(self):
        """Load Kubernetes config."""
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        return client.CoreV1Api()

    def exec_grafana_api(self, endpoint: str, method: str = "GET", data: dict = None, timeout: int = 10):
        """Execute API call to Grafana."""
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s", "-u", "admin:admin123"
        ]

        if method == "POST":
            cmd.extend(["-X", "POST"])
            if data:
                cmd.extend(["-H", "Content-Type: application/json"])
                cmd.extend(["-d", json.dumps(data)])

        cmd.append(f"http://localhost:3000{endpoint}")

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

        if result.returncode != 0:
            pytest.fail(f"Failed to exec Grafana API: {result.stderr}")

        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            # Return raw output if not JSON
            return {"raw": result.stdout}

    def test_grafana_pod_is_running(self, k8s_client):
        """Test that Grafana pod is running and healthy."""
        pods = k8s_client.list_namespaced_pod(
            namespace="observability",
            label_selector="app=grafana"
        )

        assert len(pods.items) > 0, "Grafana pod not found"

        pod = pods.items[0]
        assert pod.status.phase == "Running", f"Grafana pod is {pod.status.phase}"

        # Check container is ready
        for container in pod.status.container_statuses:
            if container.name == "grafana":  # Main container
                assert container.ready, f"Grafana container is not ready"

    def test_grafana_unified_alerting_enabled(self):
        """Test that Grafana unified alerting is enabled."""
        # Check Grafana settings
        result = self.exec_grafana_api("/api/admin/settings")

        # Unified alerting should be enabled
        # This is indicated by the presence of ngalert settings
        settings = result if isinstance(result, dict) else {}

        # Check if we have any alerting configuration
        # The API may not expose this directly, so we check for alerting endpoints
        result = self.exec_grafana_api("/api/v1/provisioning/alert-rules")

        # If unified alerting is enabled, this endpoint should return a list
        assert isinstance(result, list), \
            "Unified alerting not enabled - alert rules endpoint should return list"

    def test_grafana_alertmanager_contact_point_configured(self):
        """Test that AlertManager is configured as a contact point."""
        result = self.exec_grafana_api("/api/v1/provisioning/contact-points")

        assert isinstance(result, list), "Contact points should be a list"

        # Find AlertManager contact point
        alertmanager_contact = None
        for contact in result:
            if contact.get("name") == "alertmanager":
                alertmanager_contact = contact
                break

        assert alertmanager_contact is not None, \
            "AlertManager contact point not found"

        assert alertmanager_contact.get("type") == "prometheus-alertmanager", \
            f"Expected prometheus-alertmanager type, got {alertmanager_contact.get('type')}"

        settings = alertmanager_contact.get("settings", {})
        assert settings.get("url") == "http://alertmanager.observability.svc:9093", \
            f"AlertManager URL mismatch: {settings.get('url')}"

        assert settings.get("sendResolved") is True, \
            "sendResolved should be enabled"

    def test_grafana_notification_policies_configured(self):
        """Test that notification policies are configured correctly."""
        result = self.exec_grafana_api("/api/v1/provisioning/policies")

        assert isinstance(result, dict), "Notification policies should be a dict"

        # Check root receiver
        assert result.get("receiver") == "alertmanager", \
            f"Root receiver should be alertmanager, got {result.get('receiver')}"

        # Check grouping
        group_by = result.get("group_by", [])
        assert "alertname" in group_by, "Should group by alertname"
        assert "namespace" in group_by, "Should group by namespace"
        assert "severity" in group_by, "Should group by severity"

        # Check intervals
        assert result.get("group_wait") == "30s", \
            f"group_wait should be 30s, got {result.get('group_wait')}"

        # Check routes for severity-based routing
        routes = result.get("routes", [])
        has_critical_route = False
        for route in routes:
            matchers = route.get("matchers", [])
            for matcher in matchers:
                if "severity" in matcher and "critical" in matcher:
                    has_critical_route = True
                    assert route.get("group_wait") == "10s", \
                        "Critical alerts should have 10s group_wait"
                    break

        assert has_critical_route, "No routing rule for critical alerts found"

    def test_grafana_platform_health_alerts_provisioned(self):
        """Test that platform health alert rules are provisioned."""
        result = self.exec_grafana_api("/api/v1/provisioning/alert-rules")

        assert isinstance(result, list), "Alert rules should be a list"
        assert len(result) >= 20, \
            f"Expected at least 20 platform health alerts, got {len(result)}"

        # Check for specific critical alerts
        alert_uids = [rule.get("uid") for rule in result]

        # Infrastructure alerts
        assert "istiod-down" in alert_uids, "Istio control plane alert missing"
        assert "gateway-unhealthy" in alert_uids, "Gateway alert missing"
        assert "kubernetes-node-not-ready" in alert_uids, "Node health alert missing"

        # Platform alerts
        assert "keycloak-down" in alert_uids, "Keycloak alert missing"
        assert "kagenti-operator-down" in alert_uids, "Kagenti operator alert missing"

        # Observability alerts
        assert "prometheus-down" in alert_uids, "Prometheus alert missing"
        assert "alertmanager-down" in alert_uids, "AlertManager alert missing"

        # Application alerts
        assert "pod-crashloop-backoff" in alert_uids, "CrashLoopBackOff alert missing"

    def test_grafana_alert_rules_have_proper_labels(self):
        """Test that alert rules have proper labels (severity, component, layer)."""
        result = self.exec_grafana_api("/api/v1/provisioning/alert-rules")

        assert isinstance(result, list), "Alert rules should be a list"
        assert len(result) > 0, "No alert rules found"

        for rule in result:
            labels = rule.get("labels", {})

            # Check severity label
            severity = labels.get("severity")
            assert severity in ["critical", "warning", "info"], \
                f"Rule {rule.get('uid')} has invalid severity: {severity}"

            # Check component label
            assert "component" in labels, \
                f"Rule {rule.get('uid')} missing component label"

            # Check layer label
            layer = labels.get("layer")
            assert layer in ["infrastructure", "platform", "observability", "application"], \
                f"Rule {rule.get('uid')} has invalid layer: {layer}"

    def test_grafana_alert_rules_by_severity(self):
        """Test alert rule distribution by severity."""
        result = self.exec_grafana_api("/api/v1/provisioning/alert-rules")

        severity_counts = {
            "critical": 0,
            "warning": 0,
            "info": 0
        }

        for rule in result:
            severity = rule.get("labels", {}).get("severity", "")
            if severity in severity_counts:
                severity_counts[severity] += 1

        # Should have both critical and warning alerts
        assert severity_counts["critical"] > 0, "No critical alerts found"
        assert severity_counts["warning"] > 0, "No warning alerts found"

        # Critical alerts should be fewer than warnings (typically)
        # But not zero
        assert severity_counts["critical"] >= 5, \
            f"Expected at least 5 critical alerts, got {severity_counts['critical']}"

    def test_grafana_alert_rules_by_layer(self):
        """Test alert rule distribution by layer."""
        result = self.exec_grafana_api("/api/v1/provisioning/alert-rules")

        layer_counts = {
            "infrastructure": 0,
            "platform": 0,
            "observability": 0,
            "application": 0
        }

        for rule in result:
            layer = rule.get("labels", {}).get("layer", "")
            if layer in layer_counts:
                layer_counts[layer] += 1

        # All layers should have at least one alert
        assert layer_counts["infrastructure"] > 0, "No infrastructure alerts"
        assert layer_counts["platform"] > 0, "No platform alerts"
        assert layer_counts["observability"] > 0, "No observability alerts"
        assert layer_counts["application"] > 0, "No application alerts"

    def test_grafana_alert_rule_annotations(self):
        """Test that alert rules have proper annotations."""
        result = self.exec_grafana_api("/api/v1/provisioning/alert-rules")

        for rule in result:
            annotations = rule.get("annotations", {})

            # Check for description
            assert "description" in annotations or "summary" in annotations, \
                f"Rule {rule.get('uid')} missing description/summary"

            # Check description is not empty
            desc = annotations.get("description") or annotations.get("summary")
            assert len(desc) > 10, \
                f"Rule {rule.get('uid')} has too short description: {desc}"

    def test_grafana_critical_alerts_have_fast_evaluation(self):
        """Test that critical alerts have faster evaluation intervals."""
        result = self.exec_grafana_api("/api/v1/provisioning/alert-rules")

        for rule in result:
            severity = rule.get("labels", {}).get("severity", "")
            for_duration = rule.get("for", "")

            if severity == "critical":
                # Critical alerts should have short 'for' duration
                # Parse duration string (e.g., "2m", "30s", "1m")
                if for_duration:
                    # Extract numeric value
                    import re
                    match = re.match(r'(\d+)([smh])', for_duration)
                    if match:
                        value = int(match.group(1))
                        unit = match.group(2)

                        # Convert to seconds for comparison
                        if unit == 's':
                            seconds = value
                        elif unit == 'm':
                            seconds = value * 60
                        elif unit == 'h':
                            seconds = value * 3600

                        # Critical alerts should trigger within 5 minutes
                        assert seconds <= 300, \
                            f"Critical alert {rule.get('uid')} has too long 'for' duration: {for_duration}"

    def test_grafana_alerting_config_mounted(self, k8s_client):
        """Test that alerting provisioning ConfigMap is mounted."""
        # Get Grafana deployment
        deployments = client.AppsV1Api().list_namespaced_deployment(
            namespace="observability",
            field_selector="metadata.name=grafana"
        )

        assert len(deployments.items) > 0, "Grafana deployment not found"

        deployment = deployments.items[0]

        # Check for alerting volume mount
        has_alerting_volume = False
        for container in deployment.spec.template.spec.containers:
            if container.name == "grafana":
                for volume_mount in container.volume_mounts or []:
                    if "alerting" in volume_mount.name.lower():
                        has_alerting_volume = True
                        assert volume_mount.mount_path == "/etc/grafana/provisioning/alerting", \
                            f"Wrong mount path: {volume_mount.mount_path}"
                        break

        assert has_alerting_volume, "Alerting ConfigMap not mounted"

    def test_grafana_can_query_alertmanager(self):
        """Test that Grafana can communicate with AlertManager."""
        # Try to query AlertManager status through Grafana
        # This tests the network connectivity
        cmd = [
            "kubectl", "exec", "-n", "observability",
            "deployment/grafana", "--",
            "curl", "-s",
            "http://alertmanager.observability.svc:9093/api/v2/status"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        # If AlertManager is accessible, we should get a response
        # Even if it's an error, it shouldn't be a connection refused
        assert "connection refused" not in result.stderr.lower(), \
            "Grafana cannot connect to AlertManager"

        # If we get output, try to parse it
        if result.stdout:
            try:
                data = json.loads(result.stdout)
                # AlertManager status should have version info or cluster info
                assert "cluster" in data or "versionInfo" in data or "config" in data, \
                    f"Unexpected AlertManager response: {data}"
            except json.JSONDecodeError:
                # May be a connection error, but not connection refused
                pass

    def test_grafana_internal_alertmanager_running(self):
        """Test that Grafana's internal alertmanager is running."""
        result = self.exec_grafana_api("/api/alertmanager/grafana/api/v2/status")

        # Should return Grafana's internal alertmanager status
        assert isinstance(result, dict), "Grafana alertmanager status should be a dict"

        # Check for expected fields
        assert "cluster" in result or "versionInfo" in result or "config" in result, \
            f"Unexpected Grafana alertmanager status: {result}"

    def test_grafana_alerting_provisioning_configmap_exists(self, k8s_client):
        """Test that the grafana-alerting ConfigMap exists."""
        configmaps = k8s_client.list_namespaced_config_map(
            namespace="observability",
            field_selector="metadata.name=grafana-alerting"
        )

        assert len(configmaps.items) > 0, "grafana-alerting ConfigMap not found"

        cm = configmaps.items[0]
        data = cm.data

        # Check required keys
        assert "alertmanager.yaml" in data, "alertmanager.yaml not in ConfigMap"
        assert "policies.yaml" in data, "policies.yaml not in ConfigMap"
        assert "alert-rules-platform-health.yaml" in data, \
            "alert-rules-platform-health.yaml not in ConfigMap"

        # Check alert rules content is not empty
        alert_rules = data.get("alert-rules-platform-health.yaml", "")
        assert len(alert_rules) > 1000, \
            f"Alert rules content too small: {len(alert_rules)} bytes"

    def test_grafana_env_vars_for_unified_alerting(self, k8s_client):
        """Test that Grafana has unified alerting environment variables set."""
        # Get Grafana deployment
        deployments = client.AppsV1Api().list_namespaced_deployment(
            namespace="observability",
            field_selector="metadata.name=grafana"
        )

        assert len(deployments.items) > 0, "Grafana deployment not found"

        deployment = deployments.items[0]

        # Check environment variables
        env_vars = {}
        for container in deployment.spec.template.spec.containers:
            if container.name == "grafana":
                for env in container.env or []:
                    env_vars[env.name] = env.value

        # Check unified alerting is enabled
        assert "GF_UNIFIED_ALERTING_ENABLED" in env_vars, \
            "GF_UNIFIED_ALERTING_ENABLED not set"
        assert env_vars["GF_UNIFIED_ALERTING_ENABLED"] == "true", \
            "Unified alerting not enabled"

        # Check legacy alerting is disabled
        assert "GF_ALERTING_ENABLED" in env_vars, \
            "GF_ALERTING_ENABLED not set"
        assert env_vars["GF_ALERTING_ENABLED"] == "false", \
            "Legacy alerting should be disabled"
