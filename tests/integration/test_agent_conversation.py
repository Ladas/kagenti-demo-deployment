"""
Agent Conversation Tests

Tests actual conversations with deployed agents to verify they can respond to queries.
"""

import pytest
import requests
import json
import ast
from kubernetes import client, config
from kubernetes.stream import stream

# Load kubeconfig
try:
    config.load_kube_config()
except config.ConfigException:
    config.load_incluster_config()


class TestAgentConversation:
    """Test actual conversations with agents."""

    @pytest.fixture(scope="class")
    def agent_base_url(self):
        """Get agent base URL for testing."""
        # For Kind cluster, we need to port-forward or use cluster DNS
        # Using cluster DNS from within a pod
        return "http://research-agent.team1.svc.cluster.local:8080"

    def test_research_agent_simple_question(self):
        """
        Test research agent can answer a simple factual question.

        This test verifies end-to-end agent functionality:
        - Agent receives request
        - Processes query using LLM
        - Returns coherent response
        """
        # Skip if we can't access the agent (not in-cluster)
        pytest.skip("Agent conversation tests require in-cluster access or port-forward")

        # For local testing, you would need to:
        # kubectl port-forward -n team1 svc/research-agent 8080:8080
        # Then use localhost:8080

        agent_url = "http://localhost:8080"

        # Try HTTP POST to /invoke endpoint (A2A protocol)
        # Note: This is a placeholder - actual A2A protocol may differ
        payload = {
            "query": "What is the capital of France? Answer in one word.",
            "stream": False
        }

        try:
            response = requests.post(
                f"{agent_url}/invoke",
                json=payload,
                timeout=30
            )

            assert response.status_code == 200, f"Agent returned {response.status_code}"

            data = response.json()
            answer = data.get("response", "").lower()

            # Verify we got a response
            assert len(answer) > 0, "Agent returned empty response"

            # Verify answer contains "paris"
            assert "paris" in answer, f"Expected 'paris' in answer, got: {answer}"

            print(f"✓ Research agent answered correctly: {answer}")

        except requests.exceptions.ConnectionError:
            pytest.skip("Cannot connect to agent - port-forward not active")
        except requests.exceptions.Timeout:
            pytest.fail("Agent request timed out")

    def test_agent_health_check(self):
        """Test agent health endpoint is accessible."""
        # This can run in CI as it only checks pod health
        k8s_v1 = client.CoreV1Api()

        agents = ["research-agent", "code-agent", "orchestrator-agent"]

        for agent_name in agents:
            # Check pod is running
            pods = k8s_v1.list_namespaced_pod(
                namespace="team1",
                label_selector=f"app={agent_name}"
            )

            assert len(pods.items) > 0, f"No pods found for {agent_name}"

            pod = pods.items[0]
            assert pod.status.phase == "Running", f"{agent_name} pod not running"

            # Check containers are ready
            ready_containers = sum(
                1 for cs in pod.status.container_statuses
                if cs.ready
            )
            expected_containers = len(pod.status.container_statuses)

            assert ready_containers == expected_containers, \
                f"{agent_name}: {ready_containers}/{expected_containers} containers ready"

            print(f"✓ {agent_name} is healthy ({ready_containers}/{expected_containers} containers)")

    def test_agent_card_accessible(self):
        """Test agent card endpoint returns valid JSON."""
        k8s_v1 = client.CoreV1Api()

        agent_name = "research-agent"

        # Get a pod
        pods = k8s_v1.list_namespaced_pod(
            namespace="team1",
            label_selector=f"app={agent_name}"
        )

        assert len(pods.items) > 0, f"No pods found for {agent_name}"
        pod_name = pods.items[0].metadata.name

        # Execute curl inside the pod to get agent card
        try:
            exec_command = [
                "/bin/sh",
                "-c",
                "curl -s localhost:8080/.well-known/agent-card.json"
            ]

            resp = stream(
                k8s_v1.connect_get_namespaced_pod_exec,
                pod_name,
                "team1",
                container="agent",  # Specify the agent container
                command=exec_command,
                stderr=True,
                stdin=False,
                stdout=True,
                tty=False,
            )

            # Parse the response - stream() returns a string with Python dict format (single quotes)
            # Use ast.literal_eval to safely parse it
            agent_card = ast.literal_eval(resp)

            # Verify agent card structure
            assert "name" in agent_card, "Agent card missing 'name' field"
            assert "protocolVersion" in agent_card, "Agent card missing 'protocolVersion'"
            assert "url" in agent_card, "Agent card missing 'url'"
            assert "skills" in agent_card, "Agent card missing 'skills'"

            # Verify protocol version
            assert agent_card["protocolVersion"] == "0.3.0", \
                f"Unexpected protocol version: {agent_card['protocolVersion']}"

            print(f"✓ Agent card valid: {agent_card['name']} (v{agent_card['protocolVersion']})")
            print(f"  Skills: {[s['name'] for s in agent_card['skills']]}")

        except Exception as e:
            pytest.fail(f"Failed to fetch agent card: {e}")


@pytest.mark.manual
class TestAgentConversationManual:
    """
    Manual agent conversation tests.

    These tests require manual setup (port-forwarding) and are not run in CI.

    To run manually:
    1. Port-forward research agent: kubectl port-forward -n team1 svc/research-agent 8080:8080
    2. Run tests: pytest tests/integration/test_agent_conversation.py::TestAgentConversationManual -v
    """

    def test_simple_factual_question(self):
        """Test agent can answer simple factual questions."""
        pytest.skip("Manual test - requires port-forward. See class docstring.")

        # Example implementation:
        # agent_url = "http://localhost:8080"
        # # Send query via A2A protocol
        # # Verify response contains correct answer
        pass

    def test_multi_turn_conversation(self):
        """Test agent can maintain conversation context."""
        pytest.skip("Manual test - requires port-forward. See class docstring.")
        pass
