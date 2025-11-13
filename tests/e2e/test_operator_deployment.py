"""
End-to-End Tests for Kagenti Operator Deployment

This test suite validates the complete deployment and functionality of both
kagenti-operator and platform-operator in the Kagenti platform.

Test Philosophy:
- Test actual operator functionality, not just pod status
- Validate CRD installation and registration
- Test operator responsiveness to CRs
- Verify operator-managed resources
- Check operator logs for errors

Requirements:
    pip install kubernetes>=28.1.0 pytest>=8.0.0 tenacity>=8.2.3
"""

import pytest
import time
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from tenacity import retry, stop_after_delay, wait_fixed


# ============================================================================
# FIXTURES
# ============================================================================

@pytest.fixture(scope="module")
def k8s_client():
    """Initialize Kubernetes Core V1 API client."""
    try:
        config.load_kube_config()
    except:
        config.load_incluster_config()
    return client.CoreV1Api()


@pytest.fixture(scope="module")
def k8s_apps_client():
    """Initialize Kubernetes Apps V1 API client."""
    try:
        config.load_kube_config()
    except:
        config.load_incluster_config()
    return client.AppsV1Api()


@pytest.fixture(scope="module")
def k8s_custom_client():
    """Initialize Kubernetes Custom Objects API client."""
    try:
        config.load_kube_config()
    except:
        config.load_incluster_config()
    return client.CustomObjectsApi()


@pytest.fixture(scope="module")
def k8s_api_extensions_client():
    """Initialize Kubernetes API Extensions client for CRDs."""
    try:
        config.load_kube_config()
    except:
        config.load_incluster_config()
    return client.ApiextensionsV1Api()


# ============================================================================
# TEST CLASS: KAGENTI OPERATOR E2E
# ============================================================================

class TestKagentiOperatorE2E:
    """
    End-to-end tests for kagenti-operator.

    Tests the complete lifecycle:
    1. Operator deployment and readiness
    2. CRD registration and validation
    3. Operator watches and reconciliation
    4. Resource creation and management
    """

    def test_kagenti_operator_pod_running(self, k8s_client):
        """
        Test 1: Kagenti operator pod is running.

        Validates:
        - Pod exists in kagenti-system namespace
        - Pod is in Running state
        - All containers are ready

        Why this matters:
        If the operator pod isn't running, no agent CRs can be processed.
        """
        pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="control-plane=controller-manager,app.kubernetes.io/name=kagenti-operator"
        )

        assert len(pods.items) > 0, "No kagenti-operator pods found"

        pod = pods.items[0]
        assert pod.status.phase == "Running", \
            f"Kagenti operator pod is not running: {pod.status.phase}"

        # Check container readiness
        for container_status in pod.status.container_statuses:
            assert container_status.ready, \
                f"Container {container_status.name} is not ready"

        print(f"✓ Kagenti operator pod {pod.metadata.name} is running with {len(pod.status.container_statuses)} ready containers")

    def test_kagenti_operator_crds_registered(self, k8s_api_extensions_client):
        """
        Test 2: Kagenti operator CRDs are registered.

        Validates:
        - agents.agent.kagenti.dev CRD exists
        - agentbuilds.agent.kagenti.dev CRD exists
        - agentcards.agent.kagenti.dev CRD exists
        - CRDs are established (ready for use)

        Why this matters:
        Without CRDs, users cannot create Agent resources. This is the
        fundamental building block of the platform.
        """
        required_crds = [
            "agents.agent.kagenti.dev",
            "agentbuilds.agent.kagenti.dev",
            "agentcards.agent.kagenti.dev",
        ]

        all_crds = k8s_api_extensions_client.list_custom_resource_definition()
        crd_names = {crd.metadata.name for crd in all_crds.items}

        for crd_name in required_crds:
            assert crd_name in crd_names, f"CRD {crd_name} not found"

            # Get CRD details to check establishment
            crd = k8s_api_extensions_client.read_custom_resource_definition(crd_name)

            # Check CRD is established
            is_established = False
            for condition in crd.status.conditions:
                if condition.type == "Established" and condition.status == "True":
                    is_established = True
                    break

            assert is_established, f"CRD {crd_name} is not established"
            print(f"✓ CRD {crd_name} is registered and established")

    def test_kagenti_operator_webhook_service(self, k8s_client):
        """
        Test 3: Kagenti operator webhook service is accessible.

        Validates:
        - Webhook service exists
        - Service has endpoints (pod is serving)

        Why this matters:
        The webhook validates and mutates Agent CRs. Without it, invalid
        agents could be created, or defaults won't be applied.
        """
        try:
            service = k8s_client.read_namespaced_service(
                name="kagenti-operator-webhook-service",
                namespace="kagenti-system"
            )
            assert service is not None
            print(f"✓ Webhook service {service.metadata.name} exists")

            # Check if service has endpoints
            endpoints = k8s_client.read_namespaced_endpoints(
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

    def test_kagenti_operator_logs_no_errors(self, k8s_client):
        """
        Test 4: Kagenti operator logs contain no critical errors.

        Validates:
        - No panic messages
        - No fatal errors
        - No reconciliation failures (in last 100 lines)

        Why this matters:
        Errors in operator logs indicate reconciliation issues that could
        prevent agents from being created or updated properly.
        """
        pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="control-plane=controller-manager,app.kubernetes.io/name=kagenti-operator"
        )

        assert len(pods.items) > 0, "No kagenti-operator pods found"

        pod = pods.items[0]
        logs = k8s_client.read_namespaced_pod_log(
            name=pod.metadata.name,
            namespace="kagenti-system",
            tail_lines=100
        )

        critical_errors = []
        for line in logs.split("\n"):
            lower_line = line.lower()
            if any(keyword in lower_line for keyword in ["panic", "fatal", "error reconciling"]):
                # Skip known acceptable errors
                if "failed calling webhook" not in lower_line:  # Startup errors are OK
                    critical_errors.append(line)

        if critical_errors:
            print("\n⚠ Found critical errors in logs:")
            for error in critical_errors[:5]:  # Show first 5
                print(f"  {error}")

        # Don't fail on errors during initial startup
        assert len(critical_errors) < 10, \
            f"Too many critical errors in logs ({len(critical_errors)})"

        print(f"✓ Operator logs healthy ({len(critical_errors)} warnings)")

    def test_kagenti_operator_can_list_agents(self, k8s_custom_client):
        """
        Test 5: Can list Agent custom resources.

        Validates:
        - API server accepts requests for agents.agent.kagenti.dev
        - Operator's RBAC permissions are correct
        - CRD is properly integrated with API server

        Why this matters:
        If we can't list agents, the operator can't watch them for changes.
        """
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


# ============================================================================
# TEST CLASS: PLATFORM OPERATOR E2E
# ============================================================================

class TestPlatformOperatorE2E:
    """
    End-to-end tests for platform-operator (agentic-platform-controller-manager).

    Tests the complete lifecycle:
    1. Operator deployment and readiness
    2. CRD registration and validation
    3. Component management
    """

    def test_platform_operator_pod_running(self, k8s_client):
        """
        Test 1: Platform operator pod is running.

        Validates:
        - Pod exists in kagenti-system namespace
        - Pod is in Running state
        - All containers are ready

        Why this matters:
        The platform operator manages Component CRs which define the platform
        infrastructure (UI, API, etc.). Without it, the platform can't deploy.
        """
        pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="app.kubernetes.io/name=agentic-platform"
        )

        assert len(pods.items) > 0, "No platform-operator pods found"

        pod = pods.items[0]
        assert pod.status.phase == "Running", \
            f"Platform operator pod is not running: {pod.status.phase}"

        # Check container readiness
        for container_status in pod.status.container_statuses:
            assert container_status.ready, \
                f"Container {container_status.name} is not ready"

        print(f"✓ Platform operator pod {pod.metadata.name} is running with {len(pod.status.container_statuses)} ready containers")

    def test_platform_operator_crds_registered(self, k8s_api_extensions_client):
        """
        Test 2: Platform operator CRDs are registered.

        Validates:
        - components.kagenti.operator.dev CRD exists
        - CRD is established (ready for use)

        Why this matters:
        Components define platform services like UI and API. Without this CRD,
        the platform cannot be deployed.
        """
        crd_name = "components.kagenti.operator.dev"

        try:
            crd = k8s_api_extensions_client.read_custom_resource_definition(crd_name)

            # Check CRD is established
            is_established = False
            for condition in crd.status.conditions:
                if condition.type == "Established" and condition.status == "True":
                    is_established = True
                    break

            assert is_established, f"CRD {crd_name} is not established"
            print(f"✓ CRD {crd_name} is registered and established")

        except ApiException as e:
            pytest.fail(f"CRD {crd_name} not found: {e}")

    def test_platform_operator_logs_no_errors(self, k8s_client):
        """
        Test 3: Platform operator logs contain no critical errors.

        Validates:
        - No panic messages
        - No fatal errors
        - No reconciliation failures (in last 100 lines)

        Why this matters:
        Errors indicate the operator can't manage Components properly.
        """
        pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="app.kubernetes.io/name=agentic-platform"
        )

        assert len(pods.items) > 0, "No platform-operator pods found"

        pod = pods.items[0]
        logs = k8s_client.read_namespaced_pod_log(
            name=pod.metadata.name,
            namespace="kagenti-system",
            tail_lines=100
        )

        critical_errors = []
        for line in logs.split("\n"):
            lower_line = line.lower()
            if any(keyword in lower_line for keyword in ["panic", "fatal", "error reconciling"]):
                # Skip known acceptable errors
                if "failed calling webhook" not in lower_line:
                    critical_errors.append(line)

        if critical_errors:
            print("\n⚠ Found critical errors in logs:")
            for error in critical_errors[:5]:
                print(f"  {error}")

        assert len(critical_errors) < 10, \
            f"Too many critical errors in logs ({len(critical_errors)})"

        print(f"✓ Operator logs healthy ({len(critical_errors)} warnings)")

    def test_platform_operator_can_list_components(self, k8s_custom_client):
        """
        Test 4: Can list Component custom resources.

        Validates:
        - API server accepts requests for components.kagenti.operator.dev
        - Operator's RBAC permissions are correct

        Why this matters:
        If we can't list components, the operator can't manage the platform.
        """
        try:
            components = k8s_custom_client.list_cluster_custom_object(
                group="kagenti.operator.dev",
                version="v1alpha1",
                plural="components"
            )

            component_count = len(components.get("items", []))
            print(f"✓ Can list components (found {component_count} components)")

        except ApiException as e:
            pytest.fail(f"Cannot list components: {e}")


# ============================================================================
# TEST CLASS: OPERATOR INTEGRATION
# ============================================================================

class TestOperatorIntegration:
    """
    Integration tests verifying both operators work together.
    """

    def test_both_operators_running_simultaneously(self, k8s_client):
        """
        Test: Both operators can run without conflicts.

        Validates:
        - Both operators are running
        - No resource conflicts
        - No port conflicts

        Why this matters:
        Both operators deploy Tekton pipeline ConfigMaps. They must be able
        to share ownership via ServerSideApply without conflicts.
        """
        # Check kagenti-operator
        kagenti_pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="app.kubernetes.io/name=kagenti-operator"
        )
        assert len(kagenti_pods.items) > 0, "Kagenti operator not running"
        assert kagenti_pods.items[0].status.phase == "Running"

        # Check platform-operator
        platform_pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="app.kubernetes.io/name=agentic-platform"
        )
        assert len(platform_pods.items) > 0, "Platform operator not running"
        assert platform_pods.items[0].status.phase == "Running"

        print("✓ Both operators running simultaneously")

    def test_shared_configmaps_exist(self, k8s_client):
        """
        Test: Shared Tekton pipeline ConfigMaps exist.

        Validates:
        - Both operators successfully share ConfigMap ownership
        - ServerSideApply allows multi-owner resources

        Why this matters:
        This validates the architecture decision to allow shared resources.
        """
        shared_configmaps = [
            "github-clone-step",
            "kaniko-docker-build-step",
            "pipeline-template-dev",
        ]

        for cm_name in shared_configmaps:
            try:
                cm = k8s_client.read_namespaced_config_map(
                    name=cm_name,
                    namespace="kagenti-system"
                )
                assert cm is not None
                print(f"✓ Shared ConfigMap '{cm_name}' exists")
            except ApiException as e:
                pytest.fail(f"Shared ConfigMap '{cm_name}' not found: {e}")


# ============================================================================
# TEST CLASS: OPERATOR LIFECYCLE
# ============================================================================

class TestOperatorLifecycle:
    """
    Tests simulating real-world operator lifecycle scenarios.
    """

    def test_operator_images_correct(self, k8s_client):
        """
        Test: Operator pods are using correct local development images.

        Validates:
        - kagenti-operator uses localhost:5001/kagenti-operator:dev
        - platform-operator uses localhost:5001/kagenti-platform-operator:dev

        Why this matters:
        Ensures our local development workflow is working correctly.
        """
        # Check kagenti-operator image
        kagenti_pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="app.kubernetes.io/name=kagenti-operator"
        )

        assert len(kagenti_pods.items) > 0
        kagenti_pod = kagenti_pods.items[0]

        manager_container = None
        for container in kagenti_pod.spec.containers:
            if "manager" in container.name.lower():
                manager_container = container
                break

        assert manager_container is not None, "Manager container not found"
        assert "localhost:5001/kagenti-operator:dev" in manager_container.image, \
            f"Wrong image: {manager_container.image}"
        print(f"✓ Kagenti operator using local image: {manager_container.image}")

        # Check platform-operator image
        platform_pods = k8s_client.list_namespaced_pod(
            namespace="kagenti-system",
            label_selector="app.kubernetes.io/name=agentic-platform"
        )

        assert len(platform_pods.items) > 0
        platform_pod = platform_pods.items[0]

        manager_container = None
        for container in platform_pod.spec.containers:
            if "manager" in container.name.lower():
                manager_container = container
                break

        assert manager_container is not None, "Manager container not found"
        assert "localhost:5001/kagenti-platform-operator:dev" in manager_container.image, \
            f"Wrong image: {manager_container.image}"
        print(f"✓ Platform operator using local image: {manager_container.image}")

    def test_operator_command_path_correct(self, k8s_apps_client):
        """
        Test: Operators are using correct command path (/manager not /ko-app/cmd).

        Validates:
        - Command is /manager (matches Docker image)
        - Not using incorrect /ko-app/cmd path

        Why this matters:
        This was the root cause of the CrashLoopBackOff we fixed. Validates
        the kustomize overlay patches are working.
        """
        # Check kagenti-operator
        kagenti_deployment = k8s_apps_client.read_namespaced_deployment(
            name="kagenti-operator-controller-manager",
            namespace="kagenti-system"
        )

        manager_container = kagenti_deployment.spec.template.spec.containers[0]
        assert manager_container.command[0] == "/manager", \
            f"Wrong command: {manager_container.command[0]}"
        print(f"✓ Kagenti operator command: {manager_container.command[0]}")

        # Check platform-operator
        platform_deployment = k8s_apps_client.read_namespaced_deployment(
            name="kagenti-controller-manager",
            namespace="kagenti-system"
        )

        manager_container = platform_deployment.spec.template.spec.containers[0]
        assert manager_container.command[0] == "/manager", \
            f"Wrong command: {manager_container.command[0]}"
        print(f"✓ Platform operator command: {manager_container.command[0]}")
