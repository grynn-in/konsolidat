"""konsol#182: epm_staging.main_accounts is created by two repos, identically,
and every one of its columns is read.

konsol's `_REFERENCE_TABLE_DDL["epm_staging.main_accounts"]` creates the
table on every migrate (`ensure_reference_tables` runs
f"CREATE TABLE IF NOT EXISTS {table} {body}"), and this repo's
clickhouse/init-db.sql creates it on a fresh volume. Whichever runs first
wins, so a difference between the two texts is a table whose shape depends on
the order the stack came up in. KONSOL_BODY is konsol's string, verbatim; the
same pin lives in konsol's tests/test_main_account.py. konsolidat#199 (konsol
row K7) appends `is_retained_earnings UInt8 DEFAULT 0`, the account the
year-end close of period-end-balance files posts to.

Plain unittest, no third-party imports, so CI runs it with
`python -m unittest -v tests.test_governed_chart_ddl` (.github/workflows/dbt-checks.yml).
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
MODEL = os.path.join(PROJECT_ROOT, "dbt_project", "models", "silver", "silver_main_accounts.sql")
MACRO = os.path.join(PROJECT_ROOT, "dbt_project", "macros", "governed_chart.sql")

TABLE = "epm_staging.main_accounts"
KONSOL_BODY = (
    "(main_account String, account_name String, chart_of_accounts String, "
    "parent_account String, is_group UInt8, account_type String, "
    "statement_section String, sub_section String, normal_balance String, "
    "time_balance String, fx_method String, is_posting UInt8, "
    "is_suspended UInt8, allow_ic UInt8, cf_category String, "
    "cf_line_item String, is_cash UInt8, main_account_category String, "
    "status String, is_retained_earnings UInt8 DEFAULT 0) "
    "ENGINE = MergeTree ORDER BY main_account"
)
EXPECTED_LINE = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"
COLUMNS = [c.strip().split(" ")[0] for c in KONSOL_BODY[1:KONSOL_BODY.index(")")].split(",")]


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _code_tokens(sql):
    """Identifiers in SQL/Jinja text, comments removed. Whole tokens, so
    `main_account` is not found inside `main_account_category`."""
    sql = re.sub(r"\{#.*?#\}", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", sql))


class GovernedChartDDL(unittest.TestCase):

    def test_init_db_creates_the_governed_chart_once_with_konsols_text(self):
        statements = [line for line in _read(INIT_DB).splitlines()
                      if TABLE + " " in line + " " and not line.lstrip().startswith("--")]
        self.assertEqual(statements, [EXPECTED_LINE])

    def test_the_governed_chart_columns_are_the_ones_silver_reads(self):
        # Every column appears in silver's governed branch as a whole token:
        # is_group and status as its filters, the rest selected. A column added
        # to the DDL that silver never reads is a mistake or needs a decision.
        sql = _read(MODEL)
        governed = sql[sql.index("governed as ("):sql.index("{%- else %}")]
        tokens = _code_tokens(governed)
        self.assertEqual([c for c in COLUMNS if c not in tokens], [])

    def test_the_guard_compares_every_declared_column(self):
        # governed_chart_problems refuses Published duplicates that differ in
        # any of these; a column missing from the list could differ silently
        # and silver would keep one version arbitrarily.
        found = re.search(r"_declared\s*=\s*\[(.*?)\]", _read(MACRO), flags=re.S)
        self.assertIsNotNone(found, "governed_chart.sql no longer sets _declared")
        declared = re.findall(r"'([A-Za-z_][A-Za-z0-9_]*)'", found.group(1))
        expected = [c for c in COLUMNS if c not in ("main_account", "status")]
        self.assertEqual(sorted(declared), sorted(expected))


if __name__ == "__main__":
    unittest.main()
