"""konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment
6953756459): epm_staging.current_forecasts is how a forecast scenario's
DECLARED current round reaches the warehouse. konsol writes a submitted
Current Forecast through (S6 KA2), one row per (scenario_id, fiscal_year);
gold_forecast_current_round (WA2) joins it to budget_cycles and every forecast
reader takes that round and no other. A (scenario, year) with approved rounds
and no row here has no forecast rows anywhere, and
assert_forecast_year_has_current_round WARNs naming it.

clickhouse/init-db.sql creates the table on a fresh volume; konsol's
_REFERENCE_TABLE_DDL creates it on a stack that predates this file's version
(reconcile_all fills it). KONSOL_BODY is konsol's string, verbatim. It holds
no copy of the round: as_of_date, horizon_periods and rate_set are read from
budget_cycles by `cycle`, the one source (S6 pair A review m4). Sorted by
(scenario_id, fiscal_year), the key the readers join on.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_current_forecasts_ddl`.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

TABLE = "epm_staging.current_forecasts"
# konsol's _REFERENCE_TABLE_DDL[TABLE], verbatim.
KONSOL_BODY = (
    "(scenario_id String, fiscal_year UInt16, cycle String) "
    "ENGINE = MergeTree ORDER BY (scenario_id, fiscal_year)"
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


class CurrentForecastsDDL(unittest.TestCase):

    def test_init_db_creates_the_table_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_the_round_is_not_copied_and_the_key_is_the_pair(self):
        """Read from init-db.sql, the statement a fresh volume runs: asserting on
        this file's KONSOL_BODY could not fail when the source changed (review
        of konsolidat#365). The round's as_of_date, horizon and Rate Set live in
        budget_cycles only (S6 pair A review m4)."""
        [statement] = _create_statements(_read(INIT_DB), TABLE)
        normalised = _normalise(statement)
        for copy in ("as_of_date", "horizon_periods", "rate_set"):
            self.assertNotIn(copy, statement, copy)
        self.assertIn("ORDER BY(scenario_id,fiscal_year)", normalised)
        self.assertNotIn("scenario_type", statement)
        self.assertNotIn("1970", statement)

    def test_the_source_is_declared_with_its_columns(self):
        sources = _read(SOURCES)
        self.assertIn("- name: current_forecasts", sources)
        block = sources[sources.index("- name: current_forecasts"):]
        block = block[:block.index("\n      - name: ", 10)]   # up to the next TABLE entry
        for column in ("scenario_id", "fiscal_year", "cycle"):
            self.assertIn(f"- name: {column}", block, column)
        self.assertNotIn("- name: as_of_date", block, "budget_cycles holds the as-of")
        self.assertIn("S6-Q1", block, "the source names the decision it implements")

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_current_forecasts_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_current_forecasts_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
