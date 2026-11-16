"""konsol#348 S4 (W2, S4-Q1 c / S4-Q7 a): every reader of a governed or
historical rate says which Rate Set it reads.

epm_staging.group_exchange_rates and epm_staging.historical_equity_rates carry
rate_set. The actuals consolidation (gold_consolidated_trial_balance through
consolidation_core, the deal journals, the equity-method journal) and every
singular test that resolves a rate read the one set flagged is_actuals in
epm_staging.rate_sets, through actuals_rate_set_predicate() in
macros/governed_rates.sql; the consolidated budget passes its Cycle's set as
consolidation_core's rate_set_predicate. A reader that applies no predicate
reads every set: with a budget's rates in the table it sees two rates per key
(a duplicate the guard refuses) or, past the guard, an arbitrary one. So:

- a file that references either rate table must either apply a rate-set
  predicate or declare, in its header, that it reads `every Rate Set` (the
  grain, sanity and equity-only tests judge each row on its own, in any set);
- consolidation_core has no default predicate: `1 = 1` read every set;
- the model passes the actuals predicate, governed_rate_gaps filters its rate
  rows, the guard counts the flagged sets, and fx_precheck depends on the table.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_rate_set_filter`.
"""
import glob
import importlib.util
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DBT = os.path.join(PROJECT_ROOT, "dbt_project")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")
GOVERNED_RATES = os.path.join(DBT, "macros", "governed_rates.sql")
CORE = os.path.join(DBT, "macros", "consolidation_core.sql")
CTB = os.path.join(DBT, "models", "gold", "gold_consolidated_trial_balance.sql")
SET_COUNT_TEST = os.path.join(DBT, "tests", "assert_exactly_one_actuals_rate_set.sql")
FIXTURES = os.path.join(DBT, "test_fixtures")
GATE = os.path.join(PROJECT_ROOT, "scripts", "fixture_gate.py")
TB = "epm_gold.gold_trial_balance"
RATE_SETS = "epm_staging.rate_sets"
TB_COUNT = re.compile(r"\(\s*select count\(\) from \{\{ ref\('gold_trial_balance'\) \}\}\s*\) > 0")

RATE_SOURCE = re.compile(r"source\(\s*'epm_staging'\s*,\s*'(group_exchange_rates|historical_equity_rates)'\s*\)")
PREDICATE = re.compile(r"actuals_rate_set_predicate\(|rate_set_predicate")
EVERY_SET = "every Rate Set"


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _rate_readers():
    out = []
    for folder in ("models", "macros", "tests"):
        for path in sorted(glob.glob(os.path.join(DBT, folder, "**", "*.sql"), recursive=True)):
            if RATE_SOURCE.search(_read(path)):
                out.append(path)
    return out


class RateSetFilter(unittest.TestCase):

    def test_every_rate_reader_names_its_set_or_declares_every_set(self):
        readers = _rate_readers()
        self.assertGreater(len(readers), 10, readers)
        silent = [os.path.relpath(p, PROJECT_ROOT) for p in readers
                  if not PREDICATE.search(_read(p)) and EVERY_SET not in _read(p)]
        self.assertEqual(silent, [], "apply actuals_rate_set_predicate() / rate_set_predicate, "
                                     "or say in the header that the reader judges `every Rate Set`")

    def test_the_predicate_reads_the_flagged_set(self):
        macros = _read(GOVERNED_RATES)
        m = re.search(r"\{%\s*macro actuals_rate_set_predicate\((.*?)\)\s*-?%\}(.*?)\{%-?\s*endmacro\s*%\}",
                      macros, flags=re.S)
        self.assertIsNotNone(m, "macros/governed_rates.sql defines actuals_rate_set_predicate")
        body = m.group(2)
        self.assertIn("source('epm_staging', 'rate_sets')", body)
        self.assertIn("is_actuals = 1", body)

    def test_the_core_has_no_default_predicate(self):
        sig = re.search(r"\{%\s*macro consolidation_core\((.*?)\)\s*%\}", _read(CORE), flags=re.S).group(1)
        self.assertIn("rate_set_predicate", sig)
        self.assertNotIn("1 = 1", sig, "a default predicate reads every set")
        self.assertNotRegex(sig, r"rate_set_predicate\s*=", "rate_set_predicate is required")

    def test_the_model_passes_the_actuals_predicate(self):
        model = _read(CTB)
        self.assertRegex(model, r"rate_set_predicate\s*=\s*actuals_rate_set_predicate\(\)")
        self.assertNotIn("'1 = 1'", model)

    def test_the_gaps_guard_and_precheck_take_the_set(self):
        macros = _read(GOVERNED_RATES)
        gaps = macros[macros.index("{% macro governed_rate_gaps("):]
        gaps = gaps[:gaps.index("{% endmacro %}")]
        self.assertIn("rate_set_predicate", gaps)
        self.assertRegex(gaps, r"from \{\{ source\('epm_staging', 'group_exchange_rates'\) \}\} as g\s*\n\s*where \{\{ rate_set_predicate \}\}",
                         "gov_rows filters the rate rows by the set before anything is counted")
        guard = macros[macros.index("{% macro governed_rate_guard("):]
        guard = guard[:guard.index("{% endmacro %}")]
        self.assertIn("is_actuals = 1", guard)
        self.assertIn("flagged Is Actuals", guard)
        precheck = macros[macros.index("{% macro fx_precheck("):]
        self.assertIn("source('epm_staging', 'rate_sets')", precheck)
        self.assertIn("FX_RATE_SETS_MISSING", precheck)
        self.assertIn("FX_ACTUALS_SETS", precheck)

    def test_deploy_reads_the_new_markers(self):
        deploy = _read(os.path.join(PROJECT_ROOT, "deploy.sh"))
        self.assertIn("FX_RATE_SETS_MISSING", deploy)
        self.assertIn("FX_ACTUALS_SETS", deploy)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_rate_set_filter", wf)
        self.assertEqual(wf.count("- 'tests/test_rate_set_filter.py'"), 2,
                         "list this test under both the push and pull_request path filters")


def _inserts_into(sql, table):
    sql = re.sub(r"--[^\n]*", "", sql)
    return re.search(r"INSERT\s+INTO\s+" + re.escape(table) + r"\b", sql, flags=re.I) is not None


def _macro(macros, name):
    body = macros[macros.index("{% macro " + name + "("):]
    return body[:body.index("{% endmacro %}")]


class SetCountRuleNeedsATrialBalance(unittest.TestCase):
    """konsol#348 S4 review (konsolidat#365): on a fresh stack reconcile_all is
    an RQ job, so the first dbt build can run before epm_staging.rate_sets is
    filled. With no trial balance there is nothing a silent merge of two sets
    could affect, so the set-count rule applies only when gold_trial_balance
    has rows: the guard, fx_precheck's FX_ACTUALS_SETS line and the ERROR test
    all read the count. With a TB, zero or two sets still refuse."""

    def test_the_error_test_passes_on_an_empty_trial_balance(self):
        sql = _read(SET_COUNT_TEST)
        self.assertIn("{{ ref('gold_trial_balance') }}", sql)
        having = sql[sql.index("having"):]
        self.assertIn("countIf(is_actuals = 1) != 1", having)
        self.assertRegex(having, TB_COUNT, "the HAVING gates the count on the TB having rows")

    def test_the_guard_refuses_by_count_only_with_a_trial_balance(self):
        guard = _macro(_read(GOVERNED_RATES), "governed_rate_guard")
        self.assertIn("{{ ref('gold_trial_balance') }}", guard)
        self.assertRegex(guard, r"count\(\) > 0 as has_tb")
        self.assertRegex(guard, r"where n > 0 or \(n_sets != 1 and has_tb\)")

    def test_the_precheck_reports_the_set_count_only_with_a_trial_balance(self):
        precheck = _macro(_read(GOVERNED_RATES), "fx_precheck")
        sets_line = precheck[precheck.index("FX_ACTUALS_SETS "):precheck.index("union all")]
        self.assertRegex(sets_line, TB_COUNT)
        # nothing built at all (no TB relation) is still FX_NOTHING_BUILT, before any count
        self.assertLess(precheck.index("'FX_NOTHING_BUILT'"), precheck.index("FX_ACTUALS_SETS "))

    def test_the_empty_stack_fixture_builds_and_passes_with_no_tb_and_no_set(self):
        path = os.path.join(FIXTURES, "assert_exactly_one_actuals_rate_set.empty_stack.sql")
        self.assertTrue(os.path.exists(path), "the fresh-stack fixture exists")
        sql = _read(path)
        spec = importlib.util.spec_from_file_location("fixture_gate", GATE)
        gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gate)
        s = gate.spec(path)
        self.assertEqual(s["mode"], "build")
        self.assertIn("gold_consolidated_trial_balance", s["selector"])
        self.assertIn("assert_exactly_one_actuals_rate_set", s["selector"])
        self.assertIn(("gold_consolidated_trial_balance", "built", None), s["expect"])
        self.assertIn(("assert_exactly_one_actuals_rate_set", "pass", None), s["expect"])
        self.assertIsNone(s["refuse"])
        for table in (TB, RATE_SETS):
            self.assertIn(table, sql, f"{table} is named, so the gate creates it empty")
            self.assertFalse(_inserts_into(sql, table), f"{table} stays empty")
        self.assertTrue(_inserts_into(sql, "epm_gold.gold_entity_ownership"), "the stack has its structure")

    def test_the_fixtures_that_flag_or_refuse_hold_a_trial_balance(self):
        """Without rows in gold_trial_balance the count rule is off, so a
        flagging fixture that seeded only Rate Sets would now pass for the
        wrong reason; the passing fixture holds one too, so it proves the pass."""
        for name in ("assert_exactly_one_actuals_rate_set.sql",
                     "assert_exactly_one_actuals_rate_set.none.must_flag.sql",
                     "assert_exactly_one_actuals_rate_set.two.must_flag.sql",
                     "assert_exactly_one_actuals_rate_set.guard_refuses.must_flag.sql"):
            self.assertTrue(_inserts_into(_read(os.path.join(FIXTURES, name)), TB), name)


if __name__ == "__main__":
    unittest.main()
