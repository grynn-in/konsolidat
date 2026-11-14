"""konsol#269 (cost allocation phase 1, task W1): the six epm_staging tables that
konsol writes through for Cost Allocation Run, Cost Allocation Statistic and
their child tables, and their dbt source declarations.

Each table is created once in clickhouse/init-db.sql with the body below, and
each is declared under the epm_staging source in
dbt_project/models/staging/_staging__sources.yml. The body is the contract
that konsol's write-through and the W2/W3 models read against; a change to one
side without the other is a silent shape difference, so this test pins both.

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_cost_allocation_ddl`.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

TESTS_MODULE = "tests.test_cost_allocation_ddl"

# table name -> the body after the table name, verbatim from the W1 spec.
TABLES = {
    "epm_staging.cost_allocation_runs": (
        "(name String, rule_set String, method String, allocation_dimension String, "
        "receiver_account_mode String, allocation_account String, amounts_after_approval String, "
        "data_area_id String, scenario_id String, fiscal_year UInt16, fiscal_period UInt8, "
        "computed_at DateTime) "
        "ENGINE = MergeTree ORDER BY name"
    ),
    "epm_staging.cost_allocation_run_accounts": (
        "(parent String, idx UInt32, main_account String, declared_account String) "
        "ENGINE = MergeTree ORDER BY (parent, idx)"
    ),
    "epm_staging.cost_allocation_run_weights": (
        "(parent String, idx UInt32, step UInt16, sender_member String, receiver_member String, "
        "driver String, statistic String, value_period UInt8, carried_forward UInt8, "
        "driver_value Decimal(38,9)) "
        "ENGINE = MergeTree ORDER BY (parent, idx)"
    ),
    "epm_staging.cost_allocation_coefficients": (
        "(run String, origin_member String, step UInt16, sender_member String, "
        "receiver_member String, driver String, pool_coefficient Decimal(38,12), "
        "coefficient Decimal(38,12)) "
        "ENGINE = MergeTree ORDER BY (run, origin_member, step, receiver_member)"
    ),
    "epm_staging.cost_allocation_statistics": (
        "(name String, driver String, dimension String, data_area_id String, "
        "scenario_id String, fiscal_year UInt16) "
        "ENGINE = MergeTree ORDER BY name"
    ),
    "epm_staging.cost_allocation_statistic_values": (
        "(parent String, idx UInt32, fiscal_period UInt8, member String, value Decimal(38,9)) "
        "ENGINE = MergeTree ORDER BY (parent, idx)"
    ),
}

# The source table names, as written in the sources YAML (without the schema).
SOURCE_TABLES = [name.split(".", 1)[1] for name in TABLES]


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _normalise(sql):
    """One space between tokens, none around parentheses and commas: the
    comparison is about columns, types, engine and sort key, not wrapping."""
    sql = re.sub(r"\s+", " ", sql.strip())
    return re.sub(r"\s*([(),])\s*", r"\1", sql)


def _create_statements(sql, table):
    """Every `CREATE TABLE IF NOT EXISTS <table> ...;` statement in the file,
    comments stripped, as written."""
    sql = re.sub(r"--[^\n]*", "", sql)
    return [m.group(0) for m in re.finditer(
        r"CREATE TABLE IF NOT EXISTS " + re.escape(table) + r"\b[^;]*;", sql)]


def _epm_staging_block(yml):
    """The text of the `- name: epm_staging` source, up to the next source."""
    m = re.search(r"^  - name: epm_staging\n(.*?)(?=^  - name: |\Z)", yml, flags=re.S | re.M)
    return m.group(1) if m else ""


class CostAllocationStagingDDL(unittest.TestCase):

    def test_init_db_creates_each_cost_allocation_table_once_with_the_spec_body(self):
        sql = _read(INIT_DB)
        for table, body in TABLES.items():
            with self.subTest(table=table):
                statements = _create_statements(sql, table)
                self.assertEqual(len(statements), 1, statements)
                expected = f"CREATE TABLE IF NOT EXISTS {table} {body};"
                self.assertEqual(_normalise(statements[0]), _normalise(expected))

    def test_each_cost_allocation_table_is_declared_as_an_epm_staging_source(self):
        block = _epm_staging_block(_read(SOURCES))
        self.assertTrue(block, "no epm_staging source block in the sources YAML")
        for name in SOURCE_TABLES:
            with self.subTest(table=name):
                self.assertRegex(block, r"(?m)^      - name: " + re.escape(name) + r"$")

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn(f"python -m unittest -v {TESTS_MODULE}", wf)
        self.assertEqual(
            wf.count("- 'tests/test_cost_allocation_ddl.py'"), 2,
            "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
