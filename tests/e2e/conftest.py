"""
Pytest configuration for E2E platform tests.

Provides command-line options and fixtures for test exclusion and filtering.
"""

import pytest
from typing import Set


def pytest_addoption(parser):
    """Add custom command-line options."""
    parser.addoption(
        "--exclude-app",
        action="store",
        default="",
        help="Comma-separated list of application/component names to exclude from E2E tests"
    )


@pytest.fixture(scope="session")
def excluded_apps(request) -> Set[str]:
    """Get set of excluded application/component names.

    Returns:
        Set of application names to exclude from testing (e.g., {'agents', 'observability', 'kiali', 'ollama'})
    """
    exclude_str = request.config.getoption("--exclude-app")
    if not exclude_str:
        return set()
    return {app.strip() for app in exclude_str.split(",")}
