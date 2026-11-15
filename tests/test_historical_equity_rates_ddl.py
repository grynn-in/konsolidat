"""konsol#374 (option b; Deepak Pai, 7 Nov 2026): a Historical Equity Rate is
keyed by the presentation currency it converts into; konsol#348 (S4-Q1 c, 15
Nov 2026): and by the Rate Set it belongs to, so the actuals and the budget
rate of one tranche are two rows. The two repos that shape
epm_staging.historical_equity_rates agree on both.

clickhouse/init-db.sql creates the table on a fresh volume; konsol's
_REFERENCE_TABLE_DDL creates it on a stack that predates this file's version
and upgrades an existing one with ONE ALTER (ADD COLUMN IF NOT EXISTS
to_currency, ADD COLUMN IF NOT EXISTS rate_set, MODIFY ORDER BY). ClickHouse
appends to a sorting key only the columns the same ALTER adds, without a
DEFAULT clause, and only at the END of the key: so the fresh shape must put
to_currency and then rate_set last in ORDER BY and give neither a default, or
the fresh and the upgraded table differ. KONSOL_BODY is konsol's string,
verbatim.

The model matches a rate on the consolidating group's reporting_currency and
reads only the Rate Set flagged Is Actuals (epm_staging.rate_sets), so a
fixture that seeds a rate without to_currency or rate_set seeds a rate that
nothing can match: every INSERT into the table names both columns.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_historical_equity_rates_ddl`.
"""
import glob
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
# konsol#348 S4 (W3): the ASOF join is in the consolidation core the model calls.
MODEL = os.path.join(PROJECT_ROOT, "dbt_project", "macros", "consolidation_core.sql")
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
    "rate_set String, updated_at DateTime DEFAULT now()) "
    "ENGINE = ReplacingMergeTree(updated_at) "
    "ORDER BY (consolidation_group, data_area_id, main_account, rate_date, to_currency, rate_set)"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"
# konsol's upgrade ALTER for a table created before the column, verbatim.
KONSOL_UPGRADE = (
    f"ALTER TABLE {TABLE} "
    "ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String) AFTER historical_rate, "
    "ADD COLUMN IF NOT EXISTS rate_set String AFTER to_currency, "
    "MODIFY ORDER BY (consolidation_group, data_area_id, main_account, rate_date, to_currency, rate_set)"
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

    def test_to_currency_then_rate_set_are_last_in_the_key_and_have_no_default(self):
        """The upgraded table's key is the old key plus the new columns at the
        end, in the order the ALTER adds them (MODIFY ORDER BY may only
        append), and ClickHouse refuses to put a newly added column with a
        DEFAULT into the sorting key; the fresh shape must match the upgraded
        one. rate_set follows to_currency in the column list too (AFTER
        to_currency), so a fresh and an upgraded table read the same."""
        order_by = re.search(r"ORDER BY\s*\(([^)]*)\)", _normalise(EXPECTED_STATEMENT)).group(1)
        self.assertTrue(order_by.endswith(",to_currency,rate_set"), order_by)
        for name in ("to_currency", "rate_set"):
            column = re.search(name + r" [^,]*", KONSOL_BODY).group(0)
            self.assertNotIn("DEFAULT", column, column)
        self.assertIn("to_currency LowCardinality(String), rate_set String, updated_at", KONSOL_BODY)
        upgrade_key = re.search(r"MODIFY ORDER BY\s*\(([^)]*)\)", _normalise(KONSOL_UPGRADE)).group(1)
        self.assertEqual(upgrade_key, order_by)
        self.assertIn("ADD COLUMN IF NOT EXISTS rate_set String AFTER to_currency", KONSOL_UPGRADE)

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

    def test_every_fixture_rate_names_its_to_currency_and_rate_set(self):
        """A rate seeded without to_currency is '' in the key and matches no
        group; one without rate_set belongs to no Rate Set and is never read:
        the fixture would pass or flag for the wrong reason."""
        missing = []
        for folder in FIXTURE_DIRS:
            for path in sorted(glob.glob(os.path.join(folder, "*.sql"))):
                for columns in _inserts(_read(path), TABLE):
                    names = [c.strip() for c in columns.split(",")]
                    for required in ("to_currency", "rate_set"):
                        if required not in names:
                            missing.append(f"{os.path.relpath(path, PROJECT_ROOT)}: {required}")
        self.assertEqual(missing, [])

    def test_the_source_describes_the_key(self):
        sources = _read(SOURCES)
        block = sources[sources.index("- name: historical_equity_rates"):]
        block = block[:block.index("- name: ", 10)]
        self.assertIn("to_currency", block)
        self.assertIn("rate_set", block)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_historical_equity_rates_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_historical_equity_rates_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
