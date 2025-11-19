"""
Pytest configuration for E2E tests.

This module provides fixtures used across all E2E tests to configure
which components should be tested or skipped based on the deployment environment.
"""

import pytest


@pytest.fixture(scope="session")
def excluded_apps():
    """
    List of applications/components not deployed in this environment.

    These components are excluded from E2E testing because they are not
    part of the local Kind cluster deployment:

    - container-registry: Not deployed in local dev (use external registries)
    - platform-operator: Not deployed in Kind (CRDs managed manually)
    - operators: General operator category
    - infrastructure: ArgoCD app not used in this deployment pattern
    - agents: Agents are managed in a separate Claude Code instance
    - ollama: LLM service not deployed in Kind cluster

    Returns:
        List[str]: Names of excluded apps/components
    """
    return [
        "container-registry",
        "platform-operator",
        "operators",
        "infrastructure",  # ArgoCD Application not used
        "agents",
        "ollama",
    ]
