"""
Root pytest configuration for all Kagenti platform tests.

Provides shared command-line options and fixtures used across:
- Validation tests (tests/validation/)
- E2E tests (tests/e2e/)
- Integration tests (tests/integration/)
"""

import pytest
from typing import Set


def pytest_addoption(parser):
    """Add custom command-line options shared across all test suites."""

    # Shared option: exclude applications from testing
    parser.addoption(
        "--exclude-app",
        action="store",
        default="",
        help="Comma-separated list of application/component names to exclude from tests"
    )

    # Validation-specific options
    parser.addoption(
        "--only-critical",
        action="store_true",
        default=False,
        help="Only validate critical applications"
    )
    parser.addoption(
        "--app-timeout",
        action="store",
        type=int,
        default=300,
        help="Timeout in seconds for waiting for applications to become healthy"
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
