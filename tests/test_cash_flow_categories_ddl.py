"""konsol#197 (row T1): epm_staging.cash_flow_categories has no `sign` column,
and the two repos that create the table agree on its shape.

`Cash Flow Category` required a `sign` that nothing read. No dbt model selects
it: gold_cash_flow_indirect and gold_consolidated_cash_flow read `is_cash`,
`cf_category` and `cf_line_item` and negate the signed movement themselves, so
the cash-flow sign falls out of the data instead of a hand-coded seed value.
konsol drops the column from its `_REFERENCE_TABLE_DDL` body and retires it via
`_RETIRED_COLUMNS` (an ALTER ... DROP COLUMN IF EXISTS on the next migrate);
this repo drops it from clickhouse/init-db.sql, which creates the table on a
fresh volume.

Whichever of the two runs first wins, so a difference between the two texts is
a table whose shape depends on the order the stack came up in. KONSOL_BODY is
konsol's string, verbatim.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_cash_flow_categories_ddl`.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

TABLE = "epm_staging.cash_flow_categories"
KONSOL_BODY = (
    "(main_account String, cf_category String, cf_line_item String, "
    "is_cash UInt8, status String) "
    "ENGINE = MergeTree ORDER BY main_account"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"
EXPECTED_COLUMNS = ["main_account", "cf_category", "cf_line_item", "is_cash", "status"]
RETIRED_COLUMN = "sign"


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _normalise(sql):
    """One space between tokens, none around parentheses and commas: the
    comparison is about columns, types, engine and sort key, not about how the
    lines are wrapped."""
    sql = re.sub(r"\s+", " ", sql.strip())
    return re.sub(r"\s*([(),])\s*", r"\1", sql)


def _create_statements(sql, table):
    """Every `CREATE TABLE ... <table> ... ;` statement in the file, comments
    stripped, as written (the statement may span several lines)."""
    sql = re.sub(r"--[^\n]*", "", sql)
    return [m.group(0) for m in re.finditer(
        r"CREATE TABLE IF NOT EXISTS " + re.escape(table) + r"\b[^;]*;", sql)]


def _columns(statement):
    """The column names of a CREATE TABLE, in declaration order: the first
    token of each comma-separated item inside the column list."""
    body = re.search(r"\((.*)\)", _normalise(statement), flags=re.S).group(1)
    return [item.split()[0] for item in body.split(",") if item.split()]


class CashFlowCategoriesDDL(unittest.TestCase):

    def test_init_db_creates_cash_flow_categories_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_the_shipped_body_declares_the_five_columns_and_no_sign(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        columns = _columns(statements[0])
        self.assertEqual(columns, EXPECTED_COLUMNS)
        self.assertNotIn(RETIRED_COLUMN, columns,
                         "konsol#197 retired this column; nothing reads it")

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_cash_flow_categories_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_cash_flow_categories_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
