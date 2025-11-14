"""
Pytest configuration for validation tests.
"""

import pytest


def pytest_addoption(parser):
    """Add custom command-line options."""
    parser.addoption(
        "--exclude-app",
        action="store",
        default="",
        help="Comma-separated list of application names to exclude from validation"
    )
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
