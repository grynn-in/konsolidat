"""konsol#348 S4-Q7 (a), chosen under the standing rule (15 Nov 2026):
epm_staging.rate_sets is how the warehouse knows which Rate Set is the actuals
set. konsol writes every Rate Set through (rate_set, label, is_actuals); the
consolidation filters both rate tables by the one row with is_actuals = 1, and
assert_exactly_one_actuals_rate_set (error) refuses a build with zero or two.
A dbt var konsol regenerates was rejected as a second copy of the flag that
goes stale.

clickhouse/init-db.sql creates the table on a fresh volume; konsol's
_REFERENCE_TABLE_DDL creates it on a stack that predates this file's version
(reconcile_all fills it). KONSOL_BODY is konsol's string, verbatim.

A fixture that seeds a governed or historical rate must also seed the Rate Set
the rate belongs to, flagged is_actuals: without the row the consolidation
reads no rate at all and the guard refuses, so the fixture would flag or
refuse for the wrong reason. The TB-only first build (scripts/
tb_only_first_build.py) seeds the one set a real site gets from konsol's
patch, ACTUAL, for the same reason.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_rate_sets_ddl`.
"""
import glob
import importlib.util
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")
TB_ONLY_SCRIPT = os.path.join(PROJECT_ROOT, "scripts", "tb_only_first_build.py")
FIXTURES = os.path.join(PROJECT_ROOT, "dbt_project", "test_fixtures")

TABLE = "epm_staging.rate_sets"
RATE_TABLES = ("epm_staging.group_exchange_rates", "epm_staging.historical_equity_rates")
# konsol's _REFERENCE_TABLE_DDL[TABLE], verbatim.
KONSOL_BODY = (
    "(rate_set String, label String, is_actuals UInt8) "
    "ENGINE = MergeTree ORDER BY rate_set"
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


def _inserts_into(sql, table):
    """Whether the SQL (comments stripped: a fixture may say it deliberately
    seeds no rate) inserts into <table>."""
    sql = re.sub(r"--[^\n]*", "", sql)
    return re.search(r"INSERT\s+INTO\s+" + re.escape(table) + r"\b", sql, flags=re.I) is not None


def _rate_set_rows(sql, table=TABLE):
    """[{column: value}] for every row inserted into <table> in this SQL."""
    rows = []
    for m in re.finditer(r"INSERT\s+INTO\s+" + re.escape(table) + r"\s*\(([^)]*)\)\s*VALUES\s*([^;]*);",
                         sql, flags=re.I | re.S):
        cols = [c.strip() for c in m.group(1).split(",")]
        for tup in re.findall(r"\(([^)]*)\)", m.group(2)):
            rows.append(dict(zip(cols, [v.strip().strip("'") for v in tup.split(",")])))
    return rows


class RateSetsDDL(unittest.TestCase):

    def test_init_db_creates_the_table_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_the_source_is_declared_with_the_flag(self):
        sources = _read(SOURCES)
        self.assertIn("- name: rate_sets", sources)
        block = sources[sources.index("- name: rate_sets"):]
        block = block[:block.index("- name: ", 10)]
        self.assertIn("is_actuals", block)

    def test_every_fixture_that_seeds_a_rate_seeds_exactly_one_actuals_set(self):
        """The consolidation reads rates of the flagged set only; a fixture with
        rates but no flagged set reads none (and the guard refuses)."""
        problems = []
        for path in sorted(glob.glob(os.path.join(FIXTURES, "*.sql"))):
            sql = _read(path)
            if not any(_inserts_into(sql, t) for t in RATE_TABLES):
                continue
            flagged = [r["rate_set"] for r in _rate_set_rows(sql) if r.get("is_actuals") == "1"]
            if os.path.basename(path).startswith("assert_exactly_one_actuals_rate_set."):
                continue  # these fixtures seed zero or two on purpose
            if len(flagged) != 1:
                problems.append(f"{os.path.relpath(path, PROJECT_ROOT)}: is_actuals sets {flagged}")
        self.assertEqual(problems, [])

    def test_every_fixture_rate_belongs_to_a_seeded_set(self):
        """A rate whose rate_set names no seeded Rate Set is in no set the
        fixture declared: a typo that would make the rate unread."""
        problems = []
        for path in sorted(glob.glob(os.path.join(FIXTURES, "*.sql"))):
            sql = _read(path)
            sets = {r["rate_set"] for r in _rate_set_rows(sql)}
            for table in RATE_TABLES:
                for row in _rate_set_rows(sql, table):
                    if row.get("rate_set") not in sets:
                        problems.append(f"{os.path.relpath(path, PROJECT_ROOT)}: {table} rate_set {row.get('rate_set')!r} not in {sorted(sets)}")
        self.assertEqual(problems, [])

    def test_tb_only_first_build_seeds_one_actuals_set(self):
        spec = importlib.util.spec_from_file_location("tb_only_first_build", TB_ONLY_SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        rows = []
        for stmt in mod.fixture_sql("zz"):
            rows += _rate_set_rows(stmt + ";", "zz_staging.rate_sets")
        flagged = [r["rate_set"] for r in rows if r.get("is_actuals") == "1"]
        self.assertEqual(flagged, ["ACTUAL"], rows)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_rate_sets_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_rate_sets_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
