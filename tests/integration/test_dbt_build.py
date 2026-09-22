"""
Test 2: the consolidation arithmetic that no other test can reach.

Both tests here stage data that exists nowhere else in the system: an
intercompany partner, ownership below 100%, a second functional currency, a
mid-year acquisition, a disposal, a sub-group sale and an equity-method stake.
partner_data_area_id is cast(null as Nullable(String)) in all four ERP adapters
and the ZZ first-build fixture stages no partner at all, so the thirteen
assertions over the gold_ic_* models otherwise run on an empty table and report
green. Live data cannot substitute: all 329 ownership rows are 100%, nci_amount
is 0 on all 45,928 rows, and there are no deal journals.

What this file used to assert and no longer does (konsolidat#227 row 3): that
the build succeeds, that its output has no ERROR lines, that nine gold tables
exist afterwards, and two row-count checks. scripts/ci_full_build.py:97-115
asserts the same build with stricter conditions -- it also fails on SKIP>0 and
PASS=0, and reads dbt's own Done. line rather than string-matching "ERROR" --
and tb_only_first_build.py:273-281 asserts non-zero rows in gold_trial_balance
and gold_consolidated_trial_balance in a job that does run in CI.
"""
import os

import pytest


def _sql_statements(path):
    with open(path) as f:
        text = "\n".join(line for line in f if not line.lstrip().startswith("--"))
    return [s.strip() for s in text.split(";") if s.strip()]


# ---------------------------------------------------------------------------
# konsol#159 / #175 re-review F2: two intercompany partners on one account
# ---------------------------------------------------------------------------
TWO_PARTNER_FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "ic_two_partners.sql")
TWO_PARTNER_BATCHES = ("zzfix-ic2p-2096", "zzfix-ic2p-2097")


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
