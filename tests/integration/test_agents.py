#!/usr/bin/env python3
"""
Agent Integration Tests for Kagenti Platform

Tests agent deployment, runtime, and telemetry:
- Agent deployment (Agent CRD, pods, services)
- Agent conversation API (HTTP endpoints, chat API)
- Agent telemetry (traces in Phoenix, LLM spans)
- Monitoring agents use case (from TODO_monitoring_agents.md)
  - Prometheus query agent
  - Trace analysis agent
  - Correlation agent
  - GitHub remediation agent

Requirements:
    pip install -r requirements.txt

Usage:
    pytest tests/integration/test_agents.py -v
"""

import json
import time
import uuid
from typing import Dict, List, Optional

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


@pytest.fixture(scope="session")
def k8s_custom_client():
    """Return Kubernetes CustomObjectsApi client."""
    try:
        config.load_kube_config()
    except config.ConfigException:
        config.load_incluster_config()
    return client.CustomObjectsApi()


def port_forward(namespace: str, service: str, local_port: int, remote_port: int, duration: int = 60):
    """Create port-forward to service for testing."""
    import subprocess
    proc = subprocess.Popen([
        "kubectl", "port-forward",
        "-n", namespace,
        f"svc/{service}",
        f"{local_port}:{remote_port}"
    ])
    time.sleep(5)
    return proc


def wait_for_agent_ready(
    k8s_client: client.CoreV1Api,
    namespace: str,
    agent_name: str,
    timeout: int = 300
) -> bool:
    """
    Wait for agent pod to be ready.

    Args:
        k8s_client: Kubernetes API client
        namespace: Agent namespace
        agent_name: Agent name (used as label selector)
        timeout: Maximum wait time in seconds

    Returns:
        True if agent becomes ready, False otherwise
    """
    start_time = time.time()

    while (time.time() - start_time) < timeout:
        try:
            pods = k8s_client.list_namespaced_pod(
                namespace=namespace,
                label_selector=f"app={agent_name}"
            )

            for pod in pods.items:
                if pod.status.phase == "Running":
                    if pod.status.container_statuses:
                        all_ready = all(
                            c.ready for c in pod.status.container_statuses
                        )
                        if all_ready:
                            return True

            time.sleep(5)
        except ApiException as e:
            print(f"Error checking agent pods: {e}")
            time.sleep(5)

    return False


# ============================================================================
# Test: Agent Deployment (Existing Agents)
# ============================================================================

@pytest.mark.skip(reason="Agents managed in separate Claude Code instance")
class TestAgentDeployment:
    """Test existing agent deployments in team1 namespace.

    SKIPPED: Agents are not deployed in this environment. They are managed
    in a separate Claude Code instance per user requirements.
    """

    def test_research_agent_healthy(self, k8s_apps_client):
        """Verify research-agent is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="research-agent",
            namespace="team1"
        )

        assert deployment.status.ready_replicas >= 1, \
            "research-agent has no ready replicas"

    def test_code_agent_healthy(self, k8s_apps_client):
        """Verify code-agent is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="code-agent",
            namespace="team1"
        )

        assert deployment.status.ready_replicas >= 1, \
            "code-agent has no ready replicas"

    def test_orchestrator_agent_healthy(self, k8s_apps_client):
        """Verify orchestrator-agent is running."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="orchestrator-agent",
            namespace="team1"
        )

        assert deployment.status.ready_replicas >= 1, \
            "orchestrator-agent has no ready replicas"

    def test_agent_services_exist(self, k8s_client):
        """Verify agent services are created."""
        services = ["research-agent", "code-agent", "orchestrator-agent"]

        for svc_name in services:
            try:
                service = k8s_client.read_namespaced_service(
                    name=svc_name,
                    namespace="team1"
                )

                assert service is not None, f"{svc_name} service not found"
                assert service.spec.type == "ClusterIP", \
                    f"{svc_name} is not ClusterIP type"

            except ApiException as e:
                if e.status == 404:
                    pytest.fail(f"Service {svc_name} not found")
                raise

    def test_agent_deployments_exist(self, k8s_apps_client):
        """Verify agent deployments exist (even if pods not ready)."""
        agents = ["research-agent", "code-agent", "orchestrator-agent"]

        for agent_name in agents:
            try:
                deployment = k8s_apps_client.read_namespaced_deployment(
                    name=agent_name,
                    namespace="team1"
                )

                assert deployment is not None, \
                    f"Deployment {agent_name} not found"

            except ApiException as e:
                if e.status == 404:
                    pytest.fail(f"Deployment {agent_name} not found")
                raise


# ============================================================================
# Test: Agent Conversation API
# ============================================================================

class TestAgentConversationAPI:
    """Test agent HTTP conversation API endpoints."""

    @pytest.mark.skip(reason="Requires agent pods to be running")
    def test_research_agent_chat_endpoint(self, k8s_client):
        """Test research-agent chat API endpoint."""
        proc = None
        try:
            proc = port_forward("team1", "research-agent", 8080, 8080, duration=30)
            time.sleep(8)

            # Send chat request
            response = requests.post(
                "http://localhost:8080/chat",
                json={
                    "message": "What is Kubernetes?",
                    "conversation_id": str(uuid.uuid4())
                },
                timeout=30
            )

            assert response.status_code == 200, \
                f"Research agent chat failed: {response.status_code}"

            data = response.json()
            assert "response" in data or "message" in data, \
                "Research agent response missing expected fields"

        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"Could not connect to research-agent: {e}")
        finally:
            if proc:
                proc.terminate()
                proc.wait(timeout=5)

    @pytest.mark.skip(reason="Requires agent pods to be running")
    def test_agent_health_endpoint(self, k8s_client):
        """Test agent health endpoint responds."""
        proc = None
        try:
            proc = port_forward("team1", "research-agent", 8080, 8080, duration=30)
            time.sleep(8)

            response = requests.get(
                "http://localhost:8080/health",
                timeout=10
            )

            assert response.status_code == 200, \
                f"Agent health check failed: {response.status_code}"

        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"Could not connect to agent health endpoint: {e}")
        finally:
            if proc:
                proc.terminate()
                proc.wait(timeout=5)


# ============================================================================
# Test: Agent Telemetry in Phoenix
# ============================================================================

class TestAgentTelemetry:
    """Test agent telemetry (traces) in Phoenix observability."""

    @pytest.mark.skip(reason="Requires agent to generate traces")
    def test_agent_trace_in_phoenix(self, k8s_client):
        """Test agent conversation generates trace in Phoenix."""
        proc_phoenix = None
        proc_agent = None

        try:
            # Port-forward to Phoenix
            proc_phoenix = port_forward("observability", "phoenix", 6006, 6006, duration=60)
            time.sleep(5)

            # Port-forward to agent
            proc_agent = port_forward("team1", "research-agent", 8080, 8080, duration=60)
            time.sleep(5)

            # Send agent conversation request
            conversation_id = str(uuid.uuid4())
            requests.post(
                "http://localhost:8080/chat",
                json={
                    "message": "Test telemetry",
                    "conversation_id": conversation_id
                },
                timeout=30
            )

            # Wait for trace to be exported
            time.sleep(10)

            # Query Phoenix for traces
            query = {
                "query": """
                    query {
                        traces(first: 10) {
                            edges {
                                node {
                                    traceId
                                    spans {
                                        name
                                        attributes
                                    }
                                }
                            }
                        }
                    }
                """
            }

            response = requests.post(
                "http://localhost:6006/graphql",
                json=query,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            assert response.status_code == 200, \
                f"Phoenix GraphQL query failed: {response.status_code}"

            data = response.json()
            assert "data" in data, "Phoenix GraphQL response missing data"

            # Check if any traces exist (not necessarily from our agent)
            traces = data.get("data", {}).get("traces", {}).get("edges", [])
            print(f"Found {len(traces)} traces in Phoenix")

        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"Could not connect to services: {e}")
        finally:
            if proc_phoenix:
                proc_phoenix.terminate()
                proc_phoenix.wait(timeout=5)
            if proc_agent:
                proc_agent.terminate()
                proc_agent.wait(timeout=5)


# ============================================================================
# Test: Monitoring Agents Use Case (TODO_monitoring_agents.md)
# ============================================================================

class TestMonitoringAgents:
    """
    Test monitoring agents use case from TODO_monitoring_agents.md.

    This validates the architecture for AI-powered monitoring:
    - Prometheus query agent
    - Trace analysis agent
    - Correlation agent
    - GitHub remediation agent
    """

    def test_prometheus_mcp_server_deployment_ready(self):
        """Verify infrastructure is ready for Prometheus MCP server."""
        # This is a placeholder test for future MCP server deployment

        # Check if Prometheus is accessible (required for MCP server)
        # Prometheus is not yet deployed in observability stack
        pytest.skip("Prometheus not yet deployed - required for monitoring agents")

    def test_phoenix_ready_for_trace_mcp_server(self, k8s_apps_client):
        """Verify Phoenix is ready for Trace MCP server integration."""
        deployment = k8s_apps_client.read_namespaced_deployment(
            name="phoenix",
            namespace="observability"
        )

        assert deployment.status.ready_replicas >= 1, \
            "Phoenix not ready for Trace MCP server"

        # Check Phoenix service has GraphQL port
        k8s_client_v1 = client.CoreV1Api()
        service = k8s_client_v1.read_namespaced_service(
            name="phoenix",
            namespace="observability"
        )

        ports = {port.name: port.port for port in service.spec.ports}
        assert "http" in ports, \
            "Phoenix service missing HTTP port for GraphQL API"

    def test_correl8r_deployment_namespace_exists(self, k8s_client_v1=None):
        """Verify namespace for correl8r service exists or can be created."""
        if k8s_client_v1 is None:
            k8s_client_v1 = client.CoreV1Api()

        # correl8r should be deployed in observability or monitoring-agents namespace
        try:
            namespace = k8s_client_v1.read_namespace(name="observability")
            assert namespace is not None, "observability namespace not found"

        except ApiException as e:
            if e.status == 404:
                pytest.fail("observability namespace not found - required for correl8r")
            raise

    @pytest.mark.skip(reason="correl8r not yet deployed")
    def test_correl8r_service_accessible(self, k8s_client):
        """Verify correl8r service is deployed and accessible."""
        # This will be implemented when correl8r is deployed
        service = k8s_client.read_namespaced_service(
            name="correl8r",
            namespace="observability"
        )

        assert service is not None, "correl8r service not found"

    @pytest.mark.skip(reason="GitHub MCP server not yet deployed")
    def test_github_mcp_server_has_credentials(self, k8s_client):
        """Verify GitHub MCP server has API credentials configured."""
        # Check for GitHub token secret
        try:
            secret = k8s_client.read_namespaced_secret(
                name="github-mcp-token",
                namespace="observability"
            )

            assert secret is not None, "GitHub MCP token secret not found"
            assert "GITHUB_TOKEN" in secret.data, \
                "GitHub token secret missing GITHUB_TOKEN"

        except ApiException as e:
            if e.status == 404:
                pytest.skip("GitHub MCP token secret not yet created")
            raise

    @pytest.mark.skip(reason="Monitoring agents not yet deployed")
    def test_monitoring_agent_workflow(self):
        """
        Test end-to-end monitoring agent workflow.

        Workflow:
        1. metrics-monitor agent queries Prometheus
        2. trace-analyzer agent queries Phoenix
        3. correlation-agent correlates metrics + traces via correl8r
        4. github-remediation agent creates PR with fix

        This test validates the complete monitoring agents use case.
        """
        # This is a comprehensive E2E test that will be implemented
        # when all monitoring agents are deployed

        pytest.skip("Monitoring agents not yet deployed")


# ============================================================================
# Test: Agent CRD Lifecycle
# ============================================================================

class TestAgentCRDLifecycle:
    """Test Agent CRD creation, update, deletion lifecycle."""

    @pytest.fixture(scope="function")
    def test_namespace(self, k8s_client):
        """Create isolated namespace for test agent."""
        ns_name = f"test-agents-{uuid.uuid4().hex[:8]}"

        # Create namespace
        namespace = client.V1Namespace(
            metadata=client.V1ObjectMeta(
                name=ns_name,
                labels={"test": "agent-lifecycle"}
            )
        )
        k8s_client.create_namespace(body=namespace)

        yield ns_name

        # Cleanup
        try:
            k8s_client.delete_namespace(name=ns_name)
        except ApiException:
            pass

    @pytest.mark.skip(reason="Requires kagenti-operator to be running")
    def test_create_agent_cr(self, k8s_custom_client, test_namespace):
        """Test creating an Agent custom resource."""
        agent_cr = {
            "apiVersion": "kagenti.ai/v1alpha1",
            "kind": "Agent",
            "metadata": {
                "name": "test-agent",
                "namespace": test_namespace
            },
            "spec": {
                "image": "ghcr.io/kagenti/test-agent:latest",
                "replicas": 1,
                "mcpServers": [],
                "config": {
                    "test_mode": True
                }
            }
        }

        # Create Agent CR
        agent = k8s_custom_client.create_namespaced_custom_object(
            group="kagenti.ai",
            version="v1alpha1",
            namespace=test_namespace,
            plural="agents",
            body=agent_cr
        )

        assert agent is not None, "Agent CR creation failed"
        assert agent["metadata"]["name"] == "test-agent", \
            "Agent CR name mismatch"

        # Wait for agent deployment to be created by operator
        time.sleep(30)

        # Check if deployment was created
        k8s_apps_client = client.AppsV1Api()
        try:
            deployment = k8s_apps_client.read_namespaced_deployment(
                name="test-agent",
                namespace=test_namespace
            )

            assert deployment is not None, \
                "kagenti-operator did not create deployment for Agent CR"

        except ApiException as e:
            if e.status == 404:
                pytest.fail("kagenti-operator did not create deployment")
            raise


# ============================================================================
# Test: Agent Operator Infrastructure
# ============================================================================

class TestAgentOperatorInfrastructure:
    """
    Test kagenti-operator infrastructure for agent management.

    These tests validate that the operator is ready to manage agents,
    even if no agents are deployed yet.
    """

    def test_agent_crd_installed(self):
        """Verify agents.agent.kagenti.dev CRD is installed."""
        try:
            config.load_kube_config()
        except config.ConfigException:
            config.load_incluster_config()

        api_extensions = client.ApiextensionsV1Api()

        try:
            crd = api_extensions.read_custom_resource_definition(
                name="agents.agent.kagenti.dev"
            )

            assert crd is not None, "Agent CRD not found"

            # Check CRD is established
            is_established = False
            for condition in crd.status.conditions:
                if condition.type == "Established" and condition.status == "True":
                    is_established = True
                    break

            assert is_established, "Agent CRD is not established"
            print(f"✓ Agent CRD is registered and established")

        except ApiException as e:
            pytest.fail(f"Agent CRD not installed: {e}")

    def test_agentbuild_crd_installed(self):
        """Verify agentbuilds.agent.kagenti.dev CRD is installed."""
        try:
            config.load_kube_config()
        except config.ConfigException:
            config.load_incluster_config()

        api_extensions = client.ApiextensionsV1Api()

        try:
            crd = api_extensions.read_custom_resource_definition(
                name="agentbuilds.agent.kagenti.dev"
            )

            assert crd is not None, "AgentBuild CRD not found"

            # Check CRD is established
            is_established = False
            for condition in crd.status.conditions:
                if condition.type == "Established" and condition.status == "True":
                    is_established = True
                    break

            assert is_established, "AgentBuild CRD is not established"
            print(f"✓ AgentBuild CRD is registered and established")

        except ApiException as e:
            pytest.fail(f"AgentBuild CRD not installed: {e}")

    def test_agentcard_crd_installed(self):
        """Verify agentcards.agent.kagenti.dev CRD is installed."""
        try:
            config.load_kube_config()
        except config.ConfigException:
            config.load_incluster_config()

        api_extensions = client.ApiextensionsV1Api()

        try:
            crd = api_extensions.read_custom_resource_definition(
                name="agentcards.agent.kagenti.dev"
            )

            assert crd is not None, "AgentCard CRD not found"

            # Check CRD is established
            is_established = False
            for condition in crd.status.conditions:
                if condition.type == "Established" and condition.status == "True":
                    is_established = True
                    break

            assert is_established, "AgentCard CRD is not established"
            print(f"✓ AgentCard CRD is registered and established")

        except ApiException as e:
            pytest.fail(f"AgentCard CRD not installed: {e}")

    def test_can_list_agents(self, k8s_custom_client):
        """Verify we can list Agent custom resources."""
        try:
            agents = k8s_custom_client.list_cluster_custom_object(
                group="agent.kagenti.dev",
                version="v1alpha1",
                plural="agents"
            )

            agent_count = len(agents.get("items", []))
            print(f"✓ Can list agents (found {agent_count} agents)")

        except ApiException as e:
            pytest.fail(f"Cannot list agents: {e}")

    def test_can_list_agentbuilds(self, k8s_custom_client):
        """Verify we can list AgentBuild custom resources."""
        try:
            builds = k8s_custom_client.list_cluster_custom_object(
                group="agent.kagenti.dev",
                version="v1alpha1",
                plural="agentbuilds"
            )

            build_count = len(builds.get("items", []))
            print(f"✓ Can list agentbuilds (found {build_count} builds)")

        except ApiException as e:
            pytest.fail(f"Cannot list agentbuilds: {e}")

    def test_can_list_agentcards(self, k8s_custom_client):
        """Verify we can list AgentCard custom resources."""
        try:
            cards = k8s_custom_client.list_cluster_custom_object(
                group="agent.kagenti.dev",
                version="v1alpha1",
                plural="agentcards"
            )

            card_count = len(cards.get("items", []))
            print(f"✓ Can list agentcards (found {card_count} cards)")

        except ApiException as e:
            pytest.fail(f"Cannot list agentcards: {e}")

    def test_kagenti_operator_webhook_accessible(self):
        """Verify kagenti-operator webhook service is accessible."""
        k8s_v1 = client.CoreV1Api()

        try:
            service = k8s_v1.read_namespaced_service(
                name="kagenti-operator-webhook-service",
                namespace="kagenti-system"
            )

            assert service is not None, "Webhook service not found"
            print(f"✓ Webhook service exists")

            # Check service has endpoints
            endpoints = k8s_v1.read_namespaced_endpoints(
                name="kagenti-operator-webhook-service",
                namespace="kagenti-system"
            )

            has_addresses = False
            if endpoints.subsets:
                for subset in endpoints.subsets:
                    if subset.addresses:
                        has_addresses = True
                        break

            assert has_addresses, "Webhook service has no endpoints"
            print(f"✓ Webhook service has {len(endpoints.subsets[0].addresses)} endpoint(s)")

        except ApiException as e:
            pytest.fail(f"Webhook service not found: {e}")

    def test_kagenti_operator_rbac_configured(self):
        """Verify kagenti-operator has necessary RBAC permissions."""
        rbac_api = client.RbacAuthorizationV1Api()

        # Check ClusterRole exists
        try:
            cluster_role = rbac_api.read_cluster_role(
                name="kagenti-operator-manager-role"
            )

            assert cluster_role is not None, "Operator ClusterRole not found"

            # Verify it has rules for agent CRDs
            has_agent_rules = False
            for rule in cluster_role.rules:
                if rule.api_groups and "agent.kagenti.dev" in rule.api_groups:
                    has_agent_rules = True
                    break

            assert has_agent_rules, "ClusterRole missing agent.kagenti.dev API group rules"
            print(f"✓ Operator has {len(cluster_role.rules)} RBAC rules including agent CRDs")

        except ApiException as e:
            if e.status == 404:
                pytest.skip("Operator ClusterRole not found - may use different naming")
            raise


# ============================================================================
# Test: Agent Health
# ============================================================================

class TestAgentHealth:
    """Overall agent deployment health checks."""

    def test_team1_namespace_exists(self, k8s_client):
        """Verify team1 namespace exists for agent deployments."""
        try:
            namespace = k8s_client.read_namespace(name="team1")
            assert namespace is not None, "team1 namespace not found"

        except ApiException as e:
            if e.status == 404:
                pytest.skip("team1 namespace not created yet")
            raise

    def test_no_crashloop_agent_pods(self, k8s_client):
        """Verify no agent pods in CrashLoopBackOff."""
        try:
            pods = k8s_client.list_namespaced_pod(namespace="team1")

            crashloop_pods = []

            for pod in pods.items:
                if pod.status.container_statuses:
                    for container in pod.status.container_statuses:
                        if container.state.waiting:
                            # ImagePullBackOff is expected (images not published)
                            # But CrashLoopBackOff indicates configuration error
                            if container.state.waiting.reason == "CrashLoopBackOff":
                                crashloop_pods.append(
                                    f"{pod.metadata.name}/{container.name}"
                                )

            assert len(crashloop_pods) == 0, \
                f"Agent pods in CrashLoopBackOff: {', '.join(crashloop_pods)}"

        except ApiException:
            pytest.skip("team1 namespace not found")


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
