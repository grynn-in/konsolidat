"""konsolidat#198 (row J1): the deal tables konsol writes and the warehouse
reads are created by two repos, identically, and declared as dbt sources.

konsol's Business Combination / Business Disposal doctypes write their
submitted rows to six epm_staging tables (header + child tables), and the
group's Consolidation Policy and declared accounts add 17 columns to
epm_gold.consolidation_groups. konsol's `_REFERENCE_TABLE_DDL` creates all of
them on every migrate; this repo's clickhouse/init-db.sql creates them on a
fresh volume. Whichever runs first wins, so a difference between the two texts
is a table whose shape depends on the order the stack came up in. The bodies
below are the contract, verbatim (design-konsolidat-198 sections 1, 1a, 2a).

The acquisition and disposal journals (gold_business_combination_journal and
friends) `source()` the six tables, so they must be declared under the
epm_staging source in dbt_project/models/staging/_staging__sources.yml: a dbt
model cannot source an undeclared table, and the gate script clones only
declared sources. The 17 policy/account columns are documented on the
consolidation_groups table of the epm_gold source.

Plain unittest, no third-party imports, so CI runs it with
`python -m unittest -v tests.test_deal_tables_ddl` (.github/workflows/dbt-checks.yml).
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

GROUPS_TABLE = "epm_gold.consolidation_groups"
POLICY_COLUMNS = (
    "nci_measurement String DEFAULT '', accounting_framework String DEFAULT '', "
    "framework_note String DEFAULT '', goodwill_treatment String DEFAULT '', "
    "goodwill_amortisation_years UInt16 DEFAULT 0, "
    "acquisition_costs_treatment String DEFAULT '', measurement_period String DEFAULT '', "
    "bargain_purchase String DEFAULT '', goodwill_account String DEFAULT '', "
    "fair_value_adjustment_account String DEFAULT '', investment_account String DEFAULT '', "
    "nci_account String DEFAULT '', bargain_purchase_gain_account String DEFAULT '', "
    "disposal_gain_loss_account String DEFAULT '', disposal_proceeds_account String DEFAULT '', "
    "goodwill_amortisation_expense_account String DEFAULT '', "
    "acquisition_costs_account String DEFAULT ''"
)
GROUPS_BODY = (
    "(consolidation_group String, data_area_id String, entity_name String, "
    "reporting_currency String, ic_difference_account String DEFAULT '', "
    "ic_difference_tolerance Float64 DEFAULT 0, " + POLICY_COLUMNS + ") "
    "ENGINE = MergeTree ORDER BY (consolidation_group, data_area_id)"
)

# konsol's bodies, verbatim: header tables ORDER BY name, child tables by (parent, idx).
DEAL_TABLES = {
    "epm_staging.business_combinations": (
        "(name String, consolidation_group String, acquired_entity String, "
        "acquisition_date Date, share_acquired_pct Float64, consideration_currency String, "
        "total_consideration Float64, net_assets_acquired Float64, "
        "fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, "
        "nci_at_acquisition Float64, ownership_period String) "
        "ENGINE = MergeTree ORDER BY name"
    ),
    "epm_staging.business_combination_consideration": (
        "(parent String, idx UInt16, component String, amount Float64, currency String, "
        "settlement_date Date, description String) "
        "ENGINE = MergeTree ORDER BY (parent, idx)"
    ),
    "epm_staging.business_combination_acquired_balances": (
        "(parent String, idx UInt16, main_account String, book_amount Float64, "
        "fair_value_adjustment Float64, note String) "
        "ENGINE = MergeTree ORDER BY (parent, idx)"
    ),
    "epm_staging.business_combination_costs": (
        "(parent String, idx UInt16, kind String, amount Float64, currency String, "
        "description String) "
        "ENGINE = MergeTree ORDER BY (parent, idx)"
    ),
    "epm_staging.business_disposals": (
        "(name String, consolidation_group String, disposed_entity String, "
        "disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, "
        "proceeds_currency String, total_proceeds Float64, ownership_period String) "
        "ENGINE = MergeTree ORDER BY name"
    ),
    "epm_staging.business_disposal_proceeds": (
        "(parent String, idx UInt16, component String, amount Float64, currency String, "
        "settlement_date Date, description String) "
        "ENGINE = MergeTree ORDER BY (parent, idx)"
    ),
}


def _columns(body):
    return [c.strip().split(" ")[0] for c in body[1:body.index(")")].split(",")]


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


class DealTablesDDL(unittest.TestCase):

    def test_init_db_creates_consolidation_groups_once_with_the_policy_columns(self):
        statements = _create_statements(_read(INIT_DB), GROUPS_TABLE)
        self.assertEqual(len(statements), 1, statements)
        expected = f"CREATE TABLE IF NOT EXISTS {GROUPS_TABLE} {GROUPS_BODY};"
        self.assertEqual(_normalise(statements[0]), _normalise(expected))

    def test_init_db_creates_each_deal_table_once_with_konsols_shape(self):
        sql = _read(INIT_DB)
        for table, body in DEAL_TABLES.items():
            with self.subTest(table=table):
                statements = _create_statements(sql, table)
                self.assertEqual(len(statements), 1, statements)
                expected = f"CREATE TABLE IF NOT EXISTS {table} {body};"
                self.assertEqual(_normalise(statements[0]), _normalise(expected))

    def test_the_deal_tables_are_declared_epm_staging_sources_with_every_column(self):
        block = _source_block(_read(SOURCES), "epm_staging")
        self.assertTrue(block, "_staging__sources.yml has no `- name: epm_staging` source")
        for table, body in DEAL_TABLES.items():
            name = table.split(".")[1]
            with self.subTest(table=name):
                tb = _table_block(block, name)
                self.assertTrue(tb, f"{name} is not a table of the epm_staging source")
                self.assertEqual(_documented_columns(tb), _columns(body))

    def test_the_policy_columns_are_documented_on_the_consolidation_groups_source(self):
        block = _source_block(_read(SOURCES), "epm_gold")
        self.assertTrue(block, "_staging__sources.yml has no `- name: epm_gold` source")
        tb = _table_block(block, "consolidation_groups")
        self.assertTrue(tb, "consolidation_groups is not a table of the epm_gold source")
        documented = _documented_columns(tb)
        for col in _columns("(" + POLICY_COLUMNS + ")"):
            with self.subTest(column=col):
                self.assertIn(col, documented)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_deal_tables_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_deal_tables_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
