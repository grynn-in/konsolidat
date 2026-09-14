"""konsolidat#199 (row D7b): epm_staging.fiscal_periods is created by two repos,
identically, declared as a dbt source, and seeded by the CI fixture.

konsol's `_REFERENCE_TABLE_DDL["epm_staging.fiscal_periods"]` creates the
fiscal calendar (one row per fiscal year and period; `period_type` is
'Regular' or 'Closing') on every migrate, and this repo's clickhouse/init-db.sql
creates it on a fresh volume. Whichever runs first wins, so a difference
between the two texts is a table whose shape depends on the order the stack
came up in. KONSOL_BODY is konsol's string, verbatim.

silver_tb_movements posts the year-end close of a period-end-balance file in
the fiscal year's Closing period, so the table must be a declared source
(dbt_project/models/staging/_staging__sources.yml): a dbt model cannot
`source()` an undeclared table, and the gate script clones only declared
sources. scripts/tb_only_first_build.py seeds a calendar for its ZZ batch
(FY2026 P1 Regular, FY2026 P13 Closing) naming every column, so a column added
with a default cannot silently shift the positional values.

Plain unittest, no third-party imports, so CI runs it with
`python -m unittest -v tests.test_fiscal_periods_ddl` (.github/workflows/dbt-checks.yml).
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
CI_SCRIPT = os.path.join(PROJECT_ROOT, "scripts", "tb_only_first_build.py")

TABLE = "epm_staging.fiscal_periods"
KONSOL_BODY = (
    "(fiscal_year UInt16, fiscal_period UInt8, period_code String, "
    "period_label String, period_type String, start_date Date, end_date Date, "
    "quarter String, status String) "
    "ENGINE = MergeTree ORDER BY (fiscal_year, fiscal_period)"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"
COLUMNS = [c.strip().split(" ")[0] for c in KONSOL_BODY[1:KONSOL_BODY.index(")")].split(",")]


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _normalise(sql):
    """One space between tokens, none around parentheses and commas: the
    comparison is about columns, types, defaults, engine and sort key, not
    about how the lines are wrapped."""
    sql = re.sub(r"\s+", " ", sql.strip())
    return re.sub(r"\s*([(),])\s*", r"\1", sql)


def _create_statements(sql, table):
    """Every `CREATE TABLE ... <table> ... ;` statement in the file, comments
    stripped, as written (the statement may span several lines)."""
    sql = re.sub(r"--[^\n]*", "", sql)
    return [m.group(0) for m in re.finditer(
        r"CREATE TABLE IF NOT EXISTS " + re.escape(table) + r"\b[^;]*;", sql)]


def _source_block(yml, source_name):
    """The text of one `  - name: <source>` entry of the sources list, up to
    the next entry at the same indentation (plain text, no yaml import)."""
    m = re.search(r"^  - name: %s\n(.*?)(?=^  - name: |\Z)" % re.escape(source_name),
                  yml, flags=re.S | re.M)
    return m.group(1) if m else ""


class FiscalPeriodsDDL(unittest.TestCase):

    def test_init_db_creates_the_fiscal_calendar_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_the_fiscal_calendar_is_a_declared_epm_staging_source(self):
        block = _source_block(_read(SOURCES), "epm_staging")
        self.assertTrue(block, "_staging__sources.yml has no `- name: epm_staging` source")
        self.assertRegex(block, re.compile(r"^      - name: fiscal_periods\s*$", re.M),
                         "fiscal_periods is not a table of the epm_staging source")

    def test_ci_fixture_seeds_a_calendar_by_name_with_a_closing_period(self):
        inserts = re.findall(
            r"INSERT INTO \{p\}_staging\.fiscal_periods\s*(\([^)]*\))?\s*VALUES\s*(.*)",
            _read(CI_SCRIPT))
        self.assertEqual(len(inserts), 1, inserts)
        named, values = inserts[0]
        self.assertTrue(named, "the fiscal_periods INSERT is positional; name its columns")
        self.assertEqual([c.strip() for c in named[1:-1].split(",")], COLUMNS)
        self.assertIn("'Regular'", values)
        self.assertIn("'Closing'", values)


if __name__ == "__main__":
    unittest.main()
