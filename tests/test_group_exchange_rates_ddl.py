"""konsol#348 S4 (S4-Q1 c, W1): a governed exchange rate names its Rate Set, and
the two repos that shape epm_staging.group_exchange_rates agree on it.

clickhouse/init-db.sql creates the table on a fresh volume; konsol's
_REFERENCE_TABLE_DDL creates it on a stack that predates this file's version
and upgrades an existing one with `ALTER TABLE ... ADD COLUMN IF NOT EXISTS
rate_set String` (_ADDED_COLUMNS), which appends the column at the END. So the
fresh shape must put rate_set last, or a fresh and an upgraded table differ
and konsol's publish (CREATE TABLE shadow AS live + INSERT by column) reads
them differently. rate_set is not in ORDER BY: konsol publishes the table by
swapping the whole set in (EXCHANGE TABLES), so nothing dedupes on the key.
KONSOL_BODY is konsol's string, verbatim.

gold_consolidated_trial_balance translates only at the rates of the one Rate
Set flagged Is Actuals (epm_staging.rate_sets, S4-Q7 a; W2), so a fixture
that seeds a rate without rate_set seeds a rate in no set, which nothing can
match: every INSERT into the table names the column.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_group_exchange_rates_ddl`.
"""
import glob
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")
FIXTURE_DIRS = (
    os.path.join(PROJECT_ROOT, "dbt_project", "test_fixtures"),
    os.path.join(PROJECT_ROOT, "tests", "integration", "fixtures"),
)

TABLE = "epm_staging.group_exchange_rates"
# konsol's _REFERENCE_TABLE_DDL[TABLE], verbatim.
KONSOL_BODY = (
    "(to_currency String, from_currency String, fiscal_year UInt16, "
    "fiscal_period UInt8, rate_type String, rate Float64, document String, rate_set String) "
    "ENGINE = MergeTree ORDER BY (to_currency, from_currency, fiscal_year, fiscal_period, rate_type)"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"
COLUMNS = [c.strip().split(" ")[0] for c in KONSOL_BODY[1:KONSOL_BODY.index(")")].split(",")]


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
    """Each `INSERT INTO <table> (<columns>)` column list in the file; a
    positional INSERT (no column list) is returned as ''."""
    return [m.group(1) or "" for m in re.finditer(
        r"INSERT\s+INTO\s+" + re.escape(table) + r"\b\s*(?:\(([^)]*)\))?\s*VALUES", sql, flags=re.I)]


class GroupExchangeRatesDDL(unittest.TestCase):

    def test_init_db_creates_the_table_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_rate_set_is_the_last_column_without_default_and_outside_the_key(self):
        """konsol upgrades an existing table with ADD COLUMN (appended last, no
        DEFAULT in _ADDED_COLUMNS), so the fresh shape must match that."""
        self.assertEqual(COLUMNS[-1], "rate_set", COLUMNS)
        column = re.search(r"rate_set [^,)]*", KONSOL_BODY).group(0)
        self.assertNotIn("DEFAULT", column, column)
        order_by = re.search(r"ORDER BY\s*\(([^)]*)\)", _normalise(KONSOL_BODY)).group(1)
        self.assertNotIn("rate_set", order_by.split(","), order_by)

    def test_every_fixture_rate_names_its_rate_set(self):
        """A rate seeded without rate_set is '' in the column and belongs to no
        Rate Set: the consolidation would not read it, and a fixture would pass
        or flag for the wrong reason. A positional INSERT is refused for the
        same reason."""
        missing = []
        for folder in FIXTURE_DIRS:
            for path in sorted(glob.glob(os.path.join(folder, "*.sql"))):
                for columns in _inserts(_read(path), TABLE):
                    if "rate_set" not in [c.strip() for c in columns.split(",")]:
                        missing.append(os.path.relpath(path, PROJECT_ROOT))
        self.assertEqual(missing, [])

    def test_the_source_describes_the_rate_set(self):
        sources = _read(SOURCES)
        block = sources[sources.index("- name: group_exchange_rates"):]
        block = block[:block.index("- name: ", 10)]
        self.assertIn("rate_set", block)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_group_exchange_rates_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_group_exchange_rates_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
