"""konsolidat#220 (row H1): epm_staging.reporting_hierarchies is created by two
repos, identically, and its dated member columns are declared on the dbt source.

konsol's Reporting Hierarchy doctype writes one row per member TRANCHE: a code
whose label, parent or life changes gets a second row, each with its own
`member_effective_from` / `member_effective_to` window (open = 2999-12-31).
`effective_from` / `effective_to` (String) stay the hierarchy HEADER's dates.
konsol's `_REFERENCE_TABLE_DDL` creates the table on every migrate and this
repo's clickhouse/init-db.sql creates it on a fresh volume. Whichever runs
first wins, so a difference between the two texts is a table whose shape
depends on the order the stack came up in. KONSOL_BODY is konsol's string,
verbatim.

The gold hierarchy models `source()` the table and resolve the tree per
period from the two Date columns, so both are documented on the
reporting_hierarchies table of the epm_staging source
(dbt_project/models/staging/_staging__sources.yml).

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_reporting_hierarchies_ddl`.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

TABLE = "epm_staging.reporting_hierarchies"
KONSOL_BODY = (
    "(hierarchy_name String, dimension String, member_code String, "
    "member_label String, parent_member_code String, is_group UInt8, "
    "hierarchy_level UInt16, path String, effective_from String, "
    "effective_to String, is_default UInt8, status String, "
    "member_effective_from Date DEFAULT '1900-01-01', "
    "member_effective_to Date DEFAULT '2999-12-31') "
    "ENGINE = MergeTree ORDER BY (hierarchy_name, member_code)"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {KONSOL_BODY};"
TRANCHE_COLUMNS = ["member_effective_from", "member_effective_to"]


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


def _table_block(source_block, table_name):
    """The text of one `      - name: <table>` entry inside a source block, up
    to the next table entry."""
    m = re.search(r"^      - name: %s\s*\n(.*?)(?=^      - name: |\Z)" % re.escape(table_name),
                  source_block, flags=re.S | re.M)
    return m.group(1) if m else ""


def _documented_columns(table_block):
    return re.findall(r"^          - name: (\w+)\s*$", table_block, flags=re.M)


class ReportingHierarchiesDDL(unittest.TestCase):

    def test_init_db_creates_reporting_hierarchies_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_the_tranche_columns_are_documented_on_the_source(self):
        block = _source_block(_read(SOURCES), "epm_staging")
        self.assertTrue(block, "_staging__sources.yml has no `- name: epm_staging` source")
        tb = _table_block(block, "reporting_hierarchies")
        self.assertTrue(tb, "reporting_hierarchies is not a table of the epm_staging source")
        documented = _documented_columns(tb)
        for col in TRANCHE_COLUMNS:
            with self.subTest(column=col):
                self.assertIn(col, documented)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_reporting_hierarchies_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_reporting_hierarchies_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
