"""konsol#117 pair 1, task C (option A, Deepak Pai, 7 Nov 2026): ownership is a
graph, and the two repos that shape its three epm_staging tables agree on them.

clickhouse/init-db.sql creates the tables on a fresh volume; konsol's
_REFERENCE_TABLE_DDL creates them on a stack that predates this file's version
and upgrades existing ones. The bodies below are konsol's strings, verbatim.

* ownership_periods: the link's OWNER (owner_group, owner_data_area_id), LAST
  in the column list and appended LAST to the sorting key. Two links into one
  node from one date share the old key (consolidation_group, data_area_id,
  effective_date) and ReplacingMergeTree collapses them on merge (task E
  finding). ClickHouse appends to a sorting key only a column the same ALTER
  adds, without a DEFAULT, and only at the end: so the fresh shape must put the
  two columns last with no default, or the fresh and the upgraded table differ.
* consolidation_ancestry: path_id (the link path from the ancestor to the
  entity, unique per path), link_owner_group and link_owner_data_area_id after
  path; ORDER BY unchanged. A fixture or script that inserts positionally
  (`INSERT INTO ... VALUES (...)` with no column list) now sends too few
  values, so every INSERT into the two widened tables must name its columns.
* consolidation_method_declarations: new; the method a group declares for an
  entity its links reach by more than one path (design comment section 1).

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_ownership_graph_ddl`.
"""
import glob
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")
INSERT_FILES = (
    glob.glob(os.path.join(PROJECT_ROOT, "dbt_project", "test_fixtures", "*.sql"))
    + glob.glob(os.path.join(PROJECT_ROOT, "tests", "integration", "fixtures", "*.sql"))
    + glob.glob(os.path.join(PROJECT_ROOT, "tests", "integration", "*.py"))
    + glob.glob(os.path.join(PROJECT_ROOT, "scripts", "*.py"))
)

PERIODS = "epm_staging.ownership_periods"
ANCESTRY = "epm_staging.consolidation_ancestry"
DECLARATIONS = "epm_staging.consolidation_method_declarations"

# konsol's _REFERENCE_TABLE_DDL bodies, verbatim (konsol/tests/test_ownership_graph_ddl.py).
KONSOL_BODIES = {
    PERIODS: (
        "(consolidation_group String, data_area_id String, effective_date Date, "
        "end_date Date DEFAULT '9999-12-31', ownership_pct Decimal(5,2), "
        "consolidation_method String DEFAULT 'full', acquisition_date Date DEFAULT '1900-01-01', "
        "is_first_acquisition UInt8 DEFAULT 0, acquisition_price Decimal(18,2) DEFAULT 0, "
        "fair_value_adjustment Decimal(18,2) DEFAULT 0, disposal_date Date DEFAULT '9999-12-31', "
        "disposal_price Decimal(18,2) DEFAULT 0, is_disposal UInt8 DEFAULT 0, "
        "updated_at DateTime DEFAULT now(), owner_group String, owner_data_area_id String) "
        "ENGINE = ReplacingMergeTree(updated_at) "
        "ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id)"
    ),
    ANCESTRY: (
        "(consolidation_group String, data_area_id String, link_group String, "
        "link_data_area_id String, link_depth UInt8, depth UInt8, path String, "
        "path_id String, link_owner_group String, link_owner_data_area_id String) "
        "ENGINE = MergeTree ORDER BY (consolidation_group, data_area_id, link_depth)"
    ),
    DECLARATIONS: (
        "(consolidation_group String, data_area_id String, consolidation_method String, "
        "effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, "
        "updated_at DateTime DEFAULT now()) "
        "ENGINE = ReplacingMergeTree(updated_at) "
        "ORDER BY (consolidation_group, data_area_id, effective_date)"
    ),
}
# konsol's upgrade ALTERs for tables created before the columns, verbatim.
KONSOL_UPGRADES = {
    PERIODS: (
        f"ALTER TABLE {PERIODS} "
        "ADD COLUMN IF NOT EXISTS owner_group String AFTER updated_at, "
        "ADD COLUMN IF NOT EXISTS owner_data_area_id String AFTER owner_group, "
        "MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id)"
    ),
    ANCESTRY: (
        f"ALTER TABLE {ANCESTRY} "
        "ADD COLUMN IF NOT EXISTS path_id String AFTER path, "
        "ADD COLUMN IF NOT EXISTS link_owner_group String AFTER path_id, "
        "ADD COLUMN IF NOT EXISTS link_owner_data_area_id String AFTER link_owner_group"
    ),
}


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


def _columns(body):
    return [part.split()[0] for part in body[1:body.index(") ENGINE")].split(",")]


def _positional_inserts(text, table):
    """`INSERT INTO <table> VALUES` with no column list; `{p}_staging.x` in a
    Python f-string counts as epm_staging.x."""
    short = table.split(".", 1)[1]
    return re.findall(
        r"INSERT\s+INTO\s+(?:epm|\{p\})_staging\." + re.escape(short) + r"\s+VALUES", text, flags=re.I)


class OwnershipGraphDDL(unittest.TestCase):

    def test_init_db_creates_each_table_once_with_konsols_shape(self):
        sql = _read(INIT_DB)
        for table, body in KONSOL_BODIES.items():
            statements = _create_statements(sql, table)
            self.assertEqual(len(statements), 1, (table, statements))
            self.assertEqual(_normalise(statements[0]),
                             _normalise(f"CREATE TABLE IF NOT EXISTS {table} {body};"), table)

    def test_the_owner_ends_the_periods_columns_and_key_without_a_default(self):
        """MODIFY ORDER BY may only append, and only a column the same ALTER
        adds without a DEFAULT; the fresh shape must match the upgraded one."""
        body = KONSOL_BODIES[PERIODS]
        self.assertEqual(_columns(body)[-2:], ["owner_group", "owner_data_area_id"])
        order_by = re.search(r"ORDER BY\s*\(([^)]*)\)", _normalise(body)).group(1)
        self.assertTrue(order_by.endswith(",owner_group,owner_data_area_id"), order_by)
        for column in ("owner_group", "owner_data_area_id"):
            self.assertNotIn("DEFAULT", re.search(column + r" [^,)]*", body).group(0))
        upgrade_key = re.search(r"MODIFY ORDER BY\s*\(([^)]*)\)", _normalise(KONSOL_UPGRADES[PERIODS])).group(1)
        self.assertEqual(upgrade_key, order_by)
        self.assertNotIn("DEFAULT", KONSOL_UPGRADES[PERIODS])

    def test_the_ancestry_keeps_its_key_and_the_new_columns_follow_path(self):
        body = KONSOL_BODIES[ANCESTRY]
        self.assertTrue(body.endswith("ORDER BY (consolidation_group, data_area_id, link_depth)"))
        names = _columns(body)
        self.assertEqual(names[names.index("path"):],
                         ["path", "path_id", "link_owner_group", "link_owner_data_area_id"])
        for column, after in (("path_id", "path"), ("link_owner_group", "path_id"),
                              ("link_owner_data_area_id", "link_owner_group")):
            self.assertIn(f"ADD COLUMN IF NOT EXISTS {column} String AFTER {after}", KONSOL_UPGRADES[ANCESTRY])

    def test_every_insert_into_a_widened_table_names_its_columns(self):
        """A positional VALUES list written for the old shape sends too few
        values and fails the fixture, or the first build, by surprise."""
        offenders = []
        for path in sorted(INSERT_FILES):
            text = _read(path)
            for table in (PERIODS, ANCESTRY):
                if _positional_inserts(text, table):
                    offenders.append((os.path.relpath(path, PROJECT_ROOT), table))
        self.assertEqual(offenders, [])

    def test_the_sources_declare_the_graph(self):
        sources = _read(SOURCES)
        self.assertIn("- name: consolidation_method_declarations", sources)
        for word in ("path_id", "link_owner_group", "owner_group", "owner_data_area_id"):
            self.assertIn(word, sources, word)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_ownership_graph_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_ownership_graph_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
