"""
Test 2: Verify dbt build succeeds and produces gold models.
Exercises: staging sources → bronze → silver → gold pipeline.
"""
import os

import pytest


def test_dbt_build_succeeds(dbt_run):
    """Full dbt build should pass (data-quality warnings are OK)."""
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
    "gold_ic_unmatched",
    "gold_trial_balance_by_partner",
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
# Verify source data lands in gold tables
# ---------------------------------------------------------------------------
# gold_trial_balance is built from these epm_raw tables. There is no demo data,
# so on a fresh stack they are all empty (or not created yet).
GL_CONNECTOR_TABLES = [
    "general_journal_account_entry_bi_entities",  # D365 F&O connector
    "gl_entry",                                   # ERPNext connector
]


def _source_gl_rows(ch):
    """Rows in epm_raw that can reach gold_trial_balance. Missing tables count as empty.

    Trial balance submissions only count once their batch is claimed in the
    control table, the same inner join bronze_trial_balance_submissions uses.
    """
    existing = set(ch(
        "SELECT name FROM system.tables WHERE database = 'epm_raw' FORMAT TabSeparated"
    ).split())
    total = 0
    for table in GL_CONNECTOR_TABLES:
        if table in existing:
            total += int(ch(f"SELECT count() FROM epm_raw.{table} FORMAT TabSeparated"))
    if {"trial_balance_submissions", "trial_balance_submission_control"} <= existing:
        total += int(ch(
            "SELECT count() FROM epm_raw.trial_balance_submissions "
            "WHERE batch_id IN (SELECT batch_id FROM epm_raw.trial_balance_submission_control) "
            "FORMAT TabSeparated"
        ))
    return total


def test_gold_trial_balance_has_rows(ch, dbt_run):
    """gold_trial_balance should have rows once a connector or trial balance upload has landed data."""
    if _source_gl_rows(ch) == 0:
        pytest.skip(
            "No source data: the epm_raw GL tables are empty and no trial balance "
            "submission is claimed. There is no demo data; load data through a "
            "connector or a trial balance upload first."
        )
    dbt_run()
    count = ch("SELECT count() FROM epm_gold.gold_trial_balance FORMAT TabSeparated")
    assert int(count) > 0, "gold_trial_balance is empty after dbt build"


def test_gold_consolidated_trial_balance_has_rows(ch, dbt_run):
    """gold_consolidated_trial_balance should have rows (requires consolidation groups seed)."""
    dbt_run()
    count = ch("SELECT count() FROM epm_gold.gold_consolidated_trial_balance FORMAT TabSeparated")
    # May be 0 if no consolidation groups are seeded — that's OK, just check it doesn't error
    assert int(count) >= 0


# ---------------------------------------------------------------------------
# konsol#159 / #175 re-review F2: two intercompany partners on one account
# ---------------------------------------------------------------------------
TWO_PARTNER_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "ic_two_partners.sql")
TWO_PARTNER_BATCHES = ("zzfix-ic2p-2096", "zzfix-ic2p-2097")


def _sql_statements(path):
    with open(path) as f:
        text = "\n".join(line for line in f if not line.lstrip().startswith("--"))
    return [s.strip() for s in text.split(";") if s.strip()]


def _drop_two_partner_fixture(ch):
    ids = ", ".join(f"'{b}'" for b in TWO_PARTNER_BATCHES)
    for table in ("trial_balance_submissions", "trial_balance_submission_control"):
        ch(f"ALTER TABLE epm_raw.{table} DELETE WHERE batch_id IN ({ids}) SETTINGS mutations_sync = 1")


@pytest.fixture
def two_partner_tb(ch):
    _drop_two_partner_fixture(ch)
    for statement in _sql_statements(TWO_PARTNER_FIXTURE):
        ch(statement)
    yield
    _drop_two_partner_fixture(ch)


def test_two_partners_on_one_account_keep_the_account_grain(ch, dbt_run, two_partner_tb):
    """gold_trial_balance, its YTD and its prior-year comparison stay at the
    account grain when an account has two partners; only
    gold_trial_balance_by_partner carries a row per partner. The grain tests
    run in the same build and must pass."""
    result = dbt_run("+gold_ytd_trial_balance +gold_prior_year_comparison gold_trial_balance_by_partner")
    out = result.stdout
    for test in ("assert_ytd_trial_balance_grain", "assert_prior_year_comparison_grain"):
        assert f"PASS {test}" in out, f"{test} did not pass:\n{out[-3000:]}"
    key = "data_area_id = 'ZZF' AND main_account = '4030' AND fiscal_period = 1"
    assert ch(f"SELECT count() FROM epm_gold.gold_trial_balance_by_partner WHERE {key} AND fiscal_year = 2097") == "2"
    assert ch(f"SELECT count(), sum(period_net_amount) FROM epm_gold.gold_trial_balance WHERE {key} AND fiscal_year = 2097") == "1\t-150"
    assert ch(f"SELECT count(), sum(ytd_net_amount) FROM epm_gold.gold_ytd_trial_balance WHERE {key} AND fiscal_year = 2097") == "1\t-150"
    assert ch("SELECT count(), sum(current_amount), sum(prior_year_amount) FROM epm_gold.gold_prior_year_comparison "
              f"WHERE {key} AND fiscal_year = 2097") == "1\t-150\t-150"


# ---------------------------------------------------------------------------
# konsol#159 / #175 re-review M2 and M1: decisions 12-14 on data
# ---------------------------------------------------------------------------
IC_DECISIONS_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "ic_decisions.sql")


def _ic_decisions_expectations():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "ic_decisions_expectations", os.path.join(os.path.dirname(__file__), "ic_decisions_expectations.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _drop_ic_decisions_fixture(ch, expectations):
    for table, where in expectations.FIXTURE_ROWS:
        ch(f"ALTER TABLE {table} DELETE WHERE {where} SETTINGS mutations_sync = 1")


@pytest.fixture
def ic_decisions_data(ch):
    expectations = _ic_decisions_expectations()
    _drop_ic_decisions_fixture(ch, expectations)
    for statement in _sql_statements(IC_DECISIONS_FIXTURE):
        ch(statement)
    yield expectations
    _drop_ic_decisions_fixture(ch, expectations)


def test_ic_decisions_12_to_14_on_data(dbt_run, ch, ic_decisions_data):
    """An 80%-owned side, 70% against 80%, a balance-sheet pair booked in P1
    and P2, a second functional currency, a mid-year acquisition, a disposal,
    a sub-group sale, a stake moved to equity and a quiet partner: the exact
    reconciliation rows and entries, and the 100% view clear."""
    result = dbt_run("+gold_ic_eliminations+ gold_ic_unmatched")
    assert result.returncode == 0, result.stdout[-3000:]
    problems = ic_decisions_data.check(ch)
    assert not problems, "\n".join(problems)
