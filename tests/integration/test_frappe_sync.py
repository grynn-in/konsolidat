"""
Test 4: Verify Frappe ClickHouse sync patterns work correctly.
Tests the clickhouse.py module functions in isolation (mocked Frappe context).

This test can run WITHOUT Frappe — it mocks frappe.get_single() and tests
the HTTP request construction and SQL generation.
"""
import importlib
import os
import sys
import types
from unittest.mock import MagicMock, patch

import pytest
import requests

# ---------------------------------------------------------------------------
# Mock Frappe module so we can import clickhouse.py outside Frappe context
# ---------------------------------------------------------------------------
KONSOL_PATH = os.environ.get(
    "KONSOL_APP_PATH",
    os.path.expanduser("~/frappe-bench/apps/konsol"),
)


@pytest.fixture(scope="module")
def clickhouse_module():
    """Import konsol.clickhouse with mocked frappe module."""
    # Create a mock frappe module
    mock_frappe = MagicMock()
    mock_frappe.get_single.return_value = MagicMock(
        clickhouse_host=os.environ.get("CLICKHOUSE_HOST", "localhost"),
        clickhouse_port=os.environ.get("CLICKHOUSE_PORT", "8123"),
        clickhouse_user=os.environ.get("CLICKHOUSE_USER", "default"),
        clickhouse_password=os.environ.get("CLICKHOUSE_PASSWORD", "open_epm_dev"),
    )

    # Inject mock frappe into sys.modules
    sys.modules["frappe"] = mock_frappe
    sys.modules["frappe.utils"] = MagicMock()

    # Import clickhouse module
    ch_path = os.path.join(KONSOL_PATH, "konsol", "clickhouse.py")
    if not os.path.exists(ch_path):
        pytest.skip(f"clickhouse.py not found at {ch_path}")

    spec = importlib.util.spec_from_file_location("konsol.clickhouse", ch_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    yield module

    # Clean up
    if "frappe" in sys.modules and isinstance(sys.modules["frappe"], MagicMock):
        del sys.modules["frappe"]
    if "frappe.utils" in sys.modules:
        del sys.modules["frappe.utils"]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
class TestGetConnection:
    def test_returns_dict_with_required_keys(self, clickhouse_module):
        conn = clickhouse_module.get_connection()
        assert "host" in conn
        assert "port" in conn
        assert "user" in conn
        assert "password" in conn

    def test_reads_from_epm_settings(self, clickhouse_module):
        conn = clickhouse_module.get_connection()
        assert conn["host"] == os.environ.get("CLICKHOUSE_HOST", "localhost")


class TestExecute:
    def test_execute_select(self, clickhouse_module):
        """If CH is up, execute a simple SELECT."""
        try:
            result = clickhouse_module.execute("SELECT 1")
            assert result == "1"
        except (requests.ConnectionError, requests.Timeout):
            pytest.skip("ClickHouse not available")

    def test_execute_returns_string(self, clickhouse_module):
        try:
            result = clickhouse_module.execute("SELECT 'hello'")
            assert isinstance(result, str)
            assert "hello" in result
        except (requests.ConnectionError, requests.Timeout):
            pytest.skip("ClickHouse not available")


class TestSyncTable:
    def test_sync_table_with_real_ch(self, clickhouse_module):
        """If CH is up, test a real TRUNCATE + INSERT cycle."""
        try:
            clickhouse_module.execute("SELECT 1")
        except (requests.ConnectionError, requests.Timeout):
            pytest.skip("ClickHouse not available")

        # Create a temp table, sync data, verify
        clickhouse_module.execute(
            "CREATE TABLE IF NOT EXISTS epm_staging.__test_sync "
            "(id String, val Float64) ENGINE = MergeTree() ORDER BY id"
        )
        try:
            clickhouse_module.sync_table(
                "epm_staging.__test_sync",
                ["id", "val"],
                [["row1", 1.0], ["row2", 2.0], ["row3", 3.0]],
            )
            count = clickhouse_module.execute(
                "SELECT count() FROM epm_staging.__test_sync"
            )
            assert int(count) == 3

            # Sync again — should TRUNCATE first, so count stays 3
            clickhouse_module.sync_table(
                "epm_staging.__test_sync",
                ["id", "val"],
                [["row4", 4.0]],
            )
            count = clickhouse_module.execute(
                "SELECT count() FROM epm_staging.__test_sync"
            )
            assert int(count) == 1
        finally:
            clickhouse_module.execute("DROP TABLE IF EXISTS epm_staging.__test_sync")

    def test_sync_table_handles_nulls(self, clickhouse_module):
        """Verify NULL handling in sync_table."""
        try:
            clickhouse_module.execute("SELECT 1")
        except (requests.ConnectionError, requests.Timeout):
            pytest.skip("ClickHouse not available")

        clickhouse_module.execute(
            "CREATE TABLE IF NOT EXISTS epm_staging.__test_nulls "
            "(id String, val Nullable(Float64)) ENGINE = MergeTree() ORDER BY id"
        )
        try:
            clickhouse_module.sync_table(
                "epm_staging.__test_nulls",
                ["id", "val"],
                [["row1", None], ["row2", 2.0]],
            )
            result = clickhouse_module.execute(
                "SELECT id, val FROM epm_staging.__test_nulls ORDER BY id FORMAT TabSeparated"
            )
            lines = result.strip().split("\n")
            assert len(lines) == 2
            assert "\\N" in lines[0] or "NULL" in lines[0]  # NULL representation
        finally:
            clickhouse_module.execute("DROP TABLE IF EXISTS epm_staging.__test_nulls")

    def test_sync_table_escapes_quotes(self, clickhouse_module):
        """Verify string escaping prevents SQL injection."""
        try:
            clickhouse_module.execute("SELECT 1")
        except (requests.ConnectionError, requests.Timeout):
            pytest.skip("ClickHouse not available")

        clickhouse_module.execute(
            "CREATE TABLE IF NOT EXISTS epm_staging.__test_escape "
            "(id String, val String) ENGINE = MergeTree() ORDER BY id"
        )
        try:
            clickhouse_module.sync_table(
                "epm_staging.__test_escape",
                ["id", "val"],
                [["row1", "it's a test"], ["row2", 'he said "hello"']],
            )
            count = clickhouse_module.execute(
                "SELECT count() FROM epm_staging.__test_escape"
            )
            assert int(count) == 2
        finally:
            clickhouse_module.execute("DROP TABLE IF EXISTS epm_staging.__test_escape")
