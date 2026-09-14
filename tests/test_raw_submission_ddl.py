"""konsolidat#199: epm_raw.trial_balance_submission_control is created by two
repos, identically, and the CI fixture claims its batch with a declared basis.

konsol's `_RAW_TABLE_DDL["epm_raw.trial_balance_submission_control"]` creates
the table at runtime (the Trial Balance Submission doctype's _ensure_tables),
and this repo's clickhouse/init-db.sql creates it on a fresh volume. Whichever
runs first wins, so a difference between the two texts is a table whose shape
depends on the order the stack came up in. KONSOL_BODY is konsol's string,
verbatim, after its `amount_basis` column: the basis a batch's amounts are
stated in (`Period movement`, `Year-to-date movement`, `Period-end balance`;
'' = undeclared on claims written before the column existed).

scripts/tb_only_first_build.py inserts one claimed batch as the CI fixture.
Its INSERT names every column so a column added to the table (with a default)
cannot silently shift the positional values, and it declares the basis so the
fixture passes assert_tb_submission_has_basis.

Plain unittest, no third-party imports, so CI runs it with
`python -m unittest -v tests.test_raw_submission_ddl` (.github/workflows/dbt-checks.yml).
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
CI_SCRIPT = os.path.join(PROJECT_ROOT, "scripts", "tb_only_first_build.py")

TABLE = "epm_raw.trial_balance_submission_control"
KONSOL_BODY = (
    "(batch_id String, submission_name String, data_area_id String, "
    "fiscal_year UInt16, fiscal_period UInt8, row_count UInt32, "
    "claimed_at DateTime, amount_basis String DEFAULT '') "
    "ENGINE = ReplacingMergeTree(claimed_at) ORDER BY batch_id"
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


class RawSubmissionControlDDL(unittest.TestCase):

    def test_init_db_creates_the_control_table_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_ci_fixture_claims_its_batch_by_name_with_a_declared_basis(self):
        inserts = re.findall(
            r"INSERT INTO \{p\}_raw\.trial_balance_submission_control\s*(\([^)]*\))?\s*VALUES\s*(.*)",
            _read(CI_SCRIPT))
        self.assertEqual(len(inserts), 1, inserts)
        named, values = inserts[0]
        self.assertTrue(named, "the control INSERT is positional; name its columns")
        self.assertEqual([c.strip() for c in named[1:-1].split(",")], COLUMNS)
        self.assertIn("amount_basis", named)
        self.assertIn("'Period movement'", values)


if __name__ == "__main__":
    unittest.main()
