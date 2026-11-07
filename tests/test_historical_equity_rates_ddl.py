"""konsol#374 (option b; Deepak Pai, 7 Nov 2026): a Historical Equity Rate is
keyed by the presentation currency it converts into, and the two repos that
shape epm_staging.historical_equity_rates agree on it.

clickhouse/init-db.sql creates the table on a fresh volume; konsol's
_REFERENCE_TABLE_DDL creates it on a stack that predates this file's version
and upgrades an existing one with ONE ALTER (ADD COLUMN to_currency, MODIFY
ORDER BY). ClickHouse appends to a sorting key only the column the same ALTER
adds, without a DEFAULT clause, and only at the END of the key: so the fresh
shape must put to_currency last in ORDER BY and give it no default, or the
fresh and the upgraded table differ. KONSOL_BODY is konsol's string, verbatim.

The model matches a rate on the consolidating group's reporting_currency, so
a fixture that seeds a rate without to_currency seeds a rate that nothing can
match: every INSERT into the table names the column.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_historical_equity_rates_ddl`.
"""
import glob
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
MODEL = os.path.join(PROJECT_ROOT, "dbt_project", "models", "gold", "gold_consolidated_trial_balance.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")
FIXTURE_DIRS = (
    os.path.join(PROJECT_ROOT, "dbt_project", "test_fixtures"),
    os.path.join(PROJECT_ROOT, "tests", "integration", "fixtures"),
)
TESTS_DIR = os.path.join(PROJECT_ROOT, "dbt_project", "tests")

TABLE = "epm_staging.historical_equity_rates"
# konsol's _REFERENCE_TABLE_DDL[TABLE], verbatim.
KONSOL_BODY = (
    "(consolidation_group String, data_area_id String, main_account String, "
    "rate_date Date, historical_rate Decimal(18,6), to_currency LowCardinality(String), "
    "updated_at DateTime DEFAULT now()) "
    "ENGINE = ReplacingMergeTree(updated_at) "
    "ORDER BY (consolidation_group, data_area_id, main_account, rate_date, to_currency)"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"
# konsol's upgrade ALTER for a table created before the column, verbatim.
KONSOL_UPGRADE = (
    f"ALTER TABLE {TABLE} "
    "ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String) AFTER historical_rate, "
    "MODIFY ORDER BY (consolidation_group, data_area_id, main_account, rate_date, to_currency)"
)


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


def _inserts(sql, table):
    """Each `INSERT INTO <table> (<columns>)` column list in the file."""
    return [m.group(1) for m in re.finditer(
        r"INSERT\s+INTO\s+" + re.escape(table) + r"\s*\(([^)]*)\)", sql, flags=re.I)]


class HistoricalEquityRatesDDL(unittest.TestCase):

    def test_init_db_creates_the_table_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_to_currency_is_last_in_the_key_and_has_no_default(self):
        """The upgraded table's key is the old key plus the new column at the end
        (MODIFY ORDER BY may only append), and ClickHouse refuses to put a newly
        added column with a DEFAULT into the sorting key; the fresh shape must
        match the upgraded one."""
        order_by = re.search(r"ORDER BY \(([^)]*)\)", _normalise(EXPECTED_STATEMENT)).group(1)
        self.assertTrue(order_by.endswith(",to_currency"), order_by)
        column = re.search(r"to_currency [^,]*", KONSOL_BODY).group(0)
        self.assertNotIn("DEFAULT", column, column)
        upgrade_key = re.search(r"MODIFY ORDER BY \(([^)]*)\)", _normalise(KONSOL_UPGRADE)).group(1)
        self.assertEqual(upgrade_key, order_by)

    def test_the_model_matches_a_rate_on_the_reporting_currency(self):
        model = _read(MODEL)
        join = model[model.index("asof left join ("):]
        join = join[:join.index("where eo.consolidation_method")]
        self.assertIn("to_currency", join)
        self.assertIn("eo.reporting_currency = hr.to_currency", join)

    def test_the_singular_tests_resolve_coverage_on_the_currency(self):
        for name in ("assert_declared_historical_has_a_rate", "assert_equity_historical_rate_is_asof"):
            sql = _read(os.path.join(TESTS_DIR, name + ".sql"))
            self.assertIn("reporting_currency = r.to_currency", sql, name)

    def test_every_fixture_rate_names_its_to_currency(self):
        """A rate seeded without to_currency is '' in the key and matches no
        group: the fixture would pass or flag for the wrong reason."""
        missing = []
        for folder in FIXTURE_DIRS:
            for path in sorted(glob.glob(os.path.join(folder, "*.sql"))):
                for columns in _inserts(_read(path), TABLE):
                    if "to_currency" not in columns:
                        missing.append(os.path.relpath(path, PROJECT_ROOT))
        self.assertEqual(missing, [])

    def test_the_source_describes_the_key(self):
        self.assertIn("to_currency", _read(SOURCES))

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_historical_equity_rates_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_historical_equity_rates_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
