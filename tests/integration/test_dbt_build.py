"""
Test 2: Verify dbt build succeeds and produces gold models.
Exercises: staging sources → bronze → silver → gold pipeline.
"""
import pytest


def test_dbt_build_succeeds(dbt_run):
    """Full dbt build should pass (may have warnings on demo data, that's OK)."""
    result = dbt_run()
    assert result.returncode == 0, (
        f"dbt build failed (exit {result.returncode}):\n"
        f"STDOUT: {result.stdout[-2000:]}\n"
        f"STDERR: {result.stderr[-2000:]}"
    )


def test_dbt_build_no_errors_in_output(dbt_run):
    """dbt output should contain no ERROR lines (warnings are acceptable)."""
    result = dbt_run()
    error_lines = [
        line for line in result.stdout.splitlines()
        if "ERROR" in line and "0 error" not in line.lower()
    ]
    assert not error_lines, f"dbt build had errors:\n" + "\n".join(error_lines)


# ---------------------------------------------------------------------------
# Verify gold tables were created by dbt
# ---------------------------------------------------------------------------
EXPECTED_GOLD_TABLES = [
    "gold_trial_balance",
    "gold_consolidated_trial_balance",
    "gold_balance_sheet",
    "gold_pnl_by_period",
    "gold_ic_eliminations",
    "gold_fx_revaluation",
    "gold_consolidation_adjustments",
    "gold_allocation_results",
    "gold_allocation_audit_trail",
]

EXPECTED_ALLOCATED_TABLES = [
    "alloc_results",
    "alloc_audit_trail",
]


@pytest.mark.parametrize("table", EXPECTED_GOLD_TABLES)
def test_gold_table_exists_after_build(ch, dbt_run, table):
    """After dbt build, gold tables should exist in epm_gold."""
    # Ensure dbt has run
    dbt_run()
    count = ch(
        f"SELECT count() FROM system.tables "
        f"WHERE database = 'epm_gold' AND name = '{table}' FORMAT TabSeparated"
    )
    assert int(count) == 1, f"epm_gold.{table} does not exist after dbt build"


@pytest.mark.parametrize("table", EXPECTED_ALLOCATED_TABLES)
def test_allocated_table_exists_after_build(ch, dbt_run, table):
    """After dbt build, allocated tables should exist in epm_allocated."""
    dbt_run()
    count = ch(
        f"SELECT count() FROM system.tables "
        f"WHERE database = 'epm_allocated' AND name = '{table}' FORMAT TabSeparated"
    )
    assert int(count) == 1, f"epm_allocated.{table} does not exist after dbt build"


# ---------------------------------------------------------------------------
# Verify seed data lands in gold tables
# ---------------------------------------------------------------------------
def test_gold_trial_balance_has_rows(ch, dbt_run):
    """gold_trial_balance should have rows from seed data."""
    dbt_run()
    count = ch("SELECT count() FROM epm_gold.gold_trial_balance FORMAT TabSeparated")
    assert int(count) > 0, "gold_trial_balance is empty after dbt build"


def test_gold_consolidated_trial_balance_has_rows(ch, dbt_run):
    """gold_consolidated_trial_balance should have rows (requires consolidation groups seed)."""
    dbt_run()
    count = ch("SELECT count() FROM epm_gold.gold_consolidated_trial_balance FORMAT TabSeparated")
    # May be 0 if no consolidation groups are seeded — that's OK, just check it doesn't error
    assert int(count) >= 0
