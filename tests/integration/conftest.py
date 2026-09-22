"""
Integration test fixtures for Konsolidat.
Tests the full chain: ClickHouse staging → dbt build → gold model output.

Run with: pytest tests/integration/ -v
Requires: running ClickHouse instance (docker compose up clickhouse)
"""
import os
import subprocess

import pytest
import requests


def _ch_url():
    host = os.environ.get("CLICKHOUSE_HOST", "localhost")
    port = os.environ.get("CLICKHOUSE_PORT", "8123")
    return f"http://{host}:{port}/"


def _ch_auth():
    user = os.environ.get("CLICKHOUSE_USER", "default")
    password = os.environ.get("CLICKHOUSE_PASSWORD", "open_epm_dev")
    return (user, password)


def _ch_query(sql):
    """Execute a ClickHouse query and return the response text."""
    resp = requests.post(_ch_url(), data=sql, auth=_ch_auth(), timeout=30)
    resp.raise_for_status()
    return resp.text.strip()


@pytest.fixture(scope="session")
def ch():
    """ClickHouse query helper. Skips all tests if CH is unreachable."""
    try:
        result = _ch_query("SELECT 1")
        assert result == "1"
    except (requests.ConnectionError, requests.Timeout):
        pytest.skip("ClickHouse not available")
    return _ch_query


@pytest.fixture(scope="session")
def dbt_project_dir():
    """Path to the dbt project directory."""
    path = os.environ.get(
        "DBT_PROJECT_DIR",
        os.path.join(os.path.dirname(__file__), "..", "..", "dbt_project"),
    )
    return os.path.abspath(path)


@pytest.fixture(scope="session")
def dbt_run(dbt_project_dir):
    """Run dbt build and return the result. Only runs once per test session."""

    def _run(select=None, indirect_selection=None):
        """Run dbt build.

        indirect_selection="cautious" runs only the data tests whose every ref
        is inside the selection. konsolidat#227: without it, a scoped build runs
        assertions that COMPARE two models when only one of them was rebuilt --
        measured, assert_bs_only_bs_accounts and assert_pnl_only_pnl_accounts
        failed with 35 and 6 rows against a gold_balance_sheet and
        gold_pnl_by_period that the selection never refreshed, while the same
        data passes a full build with ERROR=0. Not the default here, because the
        two-partner test needs the grain assertions to run indirectly.
        """
        cmd = [
            "dbt", "build",
            "--project-dir", dbt_project_dir,
            "--profiles-dir", dbt_project_dir,
        ]
        if select:
            cmd.extend(["--select", select])
        if indirect_selection:
            cmd.extend(["--indirect-selection", indirect_selection])
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=300, cwd=dbt_project_dir,
        )
        return result

    return _run
