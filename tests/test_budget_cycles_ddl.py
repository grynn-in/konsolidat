"""konsol#348 S4-Q2 (a), chosen under the standing rule (15 Nov 2026):
epm_staging.budget_cycles is how a Budget Cycle's attributes, its declared
Rate Set above all (BUD-3), reach the warehouse. konsol writes a submitted
Cycle through (K6); the consolidated budget model (W4) joins the fact on
`cycle` and translates at the Cycle's set. scenario_type is not here: the
warehouse reads it from scenario_definitions by scenario_id.

clickhouse/init-db.sql creates the table on a fresh volume; konsol's
_REFERENCE_TABLE_DDL creates it on a stack that predates this file's version
(reconcile_all fills it). KONSOL_BODY is konsol's string, verbatim: as_of_date
is a Date32 with an explicit 1900-01-01 default, never a Date's silent
1970-01-01; horizon_periods unset is 0.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_budget_cycles_ddl`.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

TABLE = "epm_staging.budget_cycles"
# konsol's _REFERENCE_TABLE_DDL[TABLE], verbatim.
KONSOL_BODY = (
    "(name String, scenario_id String, fiscal_year UInt16, "
    "rate_set String, as_of_date Date32 DEFAULT '1900-01-01', horizon_periods UInt16) "
    "ENGINE = MergeTree ORDER BY name"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _normalise(sql):
    sql = re.sub(r"\s+", " ", sql.strip())
    return re.sub(r"\s*([(),])\s*", r"\1", sql)


def _create_statements(sql, table):
    sql = re.sub(r"--[^\n]*", "", sql)
    return [m.group(0) for m in re.finditer(
        r"CREATE TABLE IF NOT EXISTS " + re.escape(table) + r"\b[^;]*;", sql)]


class BudgetCyclesDDL(unittest.TestCase):

    def test_init_db_creates_the_table_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_as_of_date_is_a_date32_with_a_declared_default(self):
        self.assertIn("as_of_date Date32 DEFAULT '1900-01-01'", KONSOL_BODY)
        self.assertNotIn("scenario_type", KONSOL_BODY)

    def test_the_source_is_declared_with_the_rate_set(self):
        sources = _read(SOURCES)
        self.assertIn("- name: budget_cycles", sources)
        block = sources[sources.index("- name: budget_cycles"):]
        block = block[:block.index("- name: ", 10)]
        self.assertIn("rate_set", block)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_budget_cycles_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_budget_cycles_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
