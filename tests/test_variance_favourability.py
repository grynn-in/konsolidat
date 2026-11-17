"""konsolidat#214, konsol#348 S6 (WB1; S6-Q4 a, BUD-7-a): variance
favourability is three states, a row attribute, never a summable flag.

``gold_variance_analysis.variance_favorable`` was a Bool: false meant
"unfavourable" AND "no direction" (no budget, a balance-sheet account, an
undeclared normal balance), and konsol registered it as a ``sum`` Measure,
which added flags together. S6-Q4 (a) replaces it with
``variance_favourability`` String, one of three literals:

- ``favourable``: the signed actual is below the signed budget;
- ``unfavourable``: above it;
- ``not_applicable``: a balance-sheet account, an undeclared normal
  balance, or a zero variance (the statement shows "On budget" for that
  last case; the warehouse column does not distinguish it, as the yml
  declares).

No budget line is a budget of zero ("Unbudgeted is unfavourable", Deepak
Pai, 22 Sep 2026), never "no direction": the model and the test compare
against ``coalesce(budget_amount, 0)``, as ``variance_abs`` does.

Static pins, no ClickHouse:

- the model declares the three literals and never the old column;
- no singular test or fixture names the old column (the fixtures seed the
  model's table by column name, so a stale one would seed a column that no
  longer exists);
- ``assert_variance_favourability_follows_normal_balance`` exists at error
  severity, derives the expectation from the chart and the amounts (not the
  model's own flag), and has its PASS and must_flag fixtures;
- the yml describes the column and names the test;
- CI runs this module.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_variance_favourability`
"""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = os.path.join(ROOT, "dbt_project", "models", "gold", "gold_variance_analysis.sql")
YML = os.path.join(ROOT, "dbt_project", "models", "gold", "_gold__models.yml")
TESTS = os.path.join(ROOT, "dbt_project", "tests")
FIXTURES = os.path.join(ROOT, "dbt_project", "test_fixtures")
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "dbt-checks.yml")

TEST = "assert_variance_favourability_follows_normal_balance"
OLD_TEST = "assert_variance_favorable_follows_normal_balance"
COLUMN = "variance_favourability"
OLD_COLUMN = "variance_favorable"
LITERALS = ("favourable", "unfavourable", "not_applicable")


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _files(folder):
    return sorted(name for name in os.listdir(folder) if name.endswith(".sql"))


class ModelDeclaresThreeStates(unittest.TestCase):
    def test_model_has_the_string_column_with_the_three_literals(self):
        sql = _read(MODEL)
        self.assertIn(f"as {COLUMN}", sql)
        for literal in LITERALS:
            self.assertIn(f"'{literal}'", sql, literal)

    def test_no_budget_is_budget_zero_never_no_direction(self):
        """22 Sep 2026: budget 0, actual 10 is unfavourable 10."""
        for path in (MODEL, os.path.join(TESTS, TEST + ".sql")):
            sql = _read(path)
            self.assertNotRegex(sql, r"budget_amount\s+is\s+null\s*,\s*'not_applicable'", path)
            self.assertRegex(sql, r"actual_amount\s*<\s*coalesce\(\s*\w+\.budget_amount\s*,\s*0\s*\)", path)
        self.assertIn("budget zero", _read(YML))

    def test_model_no_longer_has_the_boolean(self):
        self.assertNotIn(OLD_COLUMN, _read(MODEL))

    def test_yml_describes_the_column_and_names_the_test(self):
        yml = _read(YML)
        self.assertIn(f"- name: {COLUMN}", yml)
        self.assertNotIn(OLD_COLUMN, yml)
        self.assertIn(TEST, yml)
        for literal in LITERALS:
            self.assertIn(literal, yml, literal)


class TheTestAndItsFixtures(unittest.TestCase):
    def test_singular_test_exists_at_error_severity_and_reads_the_chart(self):
        path = os.path.join(TESTS, TEST + ".sql")
        self.assertTrue(os.path.exists(path), path)
        sql = _read(path)
        self.assertRegex(sql, r"config\(\s*severity\s*=\s*'error'\s*\)")
        self.assertIn("silver_main_accounts", sql, "the expectation comes from the chart")
        # PR #374 review m4: P&L or not is the chart's too, never the model's
        # own is_pnl (a model that mislabels a balance-sheet account as P&L
        # would otherwise be judged by its own mistake).
        self.assertRegex(sql, r"coalesce\(\s*am\.is_pnl\s*,\s*0\s*\)\s*=\s*0")
        self.assertNotRegex(sql, r"v\.is_pnl\s*=")
        for literal in LITERALS:
            self.assertIn(f"'{literal}'", sql, literal)

    def test_old_test_is_gone(self):
        self.assertFalse(os.path.exists(os.path.join(TESTS, OLD_TEST + ".sql")))

    def test_pass_and_must_flag_fixtures_exist_and_gate_the_new_test(self):
        for name in (TEST + ".sql", TEST + ".must_flag.sql", "variance_favourability_signed.sql"):
            path = os.path.join(FIXTURES, name)
            self.assertTrue(os.path.exists(path), path)
        must_flag = _read(os.path.join(FIXTURES, TEST + ".must_flag.sql"))
        self.assertRegex(must_flag, rf"-- gate: expect {TEST} flag [1-9]\d*")
        signed = _read(os.path.join(FIXTURES, "variance_favourability_signed.sql"))
        self.assertIn(f"-- gate: expect {TEST} pass", signed)

    def test_no_test_or_fixture_names_the_boolean(self):
        stale = []
        for folder in (TESTS, FIXTURES):
            for root, _dirs, files in os.walk(folder):
                for name in files:
                    if name.endswith(".sql") and OLD_COLUMN in _read(os.path.join(root, name)):
                        stale.append(os.path.relpath(os.path.join(root, name), ROOT))
        self.assertEqual(stale, [])

    def test_no_fixture_of_the_old_test_remains(self):
        self.assertEqual([n for n in _files(FIXTURES) if n.startswith(OLD_TEST)], [])
        self.assertEqual([n for n in _files(FIXTURES) if n.startswith("variance_favorable_")], [])


class TheDocsNameTheNewColumn(unittest.TestCase):
    def test_no_doc_names_the_boolean(self):
        """PR #374 review m5: a PRD that still names the Bool sends a reader
        to a column the warehouse no longer has."""
        stale = []
        for root, _dirs, files in os.walk(os.path.join(ROOT, "docs")):
            for name in files:
                if name.endswith(".md") and OLD_COLUMN in _read(os.path.join(root, name)):
                    stale.append(os.path.relpath(os.path.join(root, name), ROOT))
        self.assertEqual(stale, [])


class RegisteredInCI(unittest.TestCase):
    def test_workflow_runs_this_module(self):
        self.assertRegex(_read(WORKFLOW), r"python -m unittest -v tests\.test_variance_favourability\b")


if __name__ == "__main__":
    unittest.main()
