"""Budget S2 R6 (Q13-a): epm_gold.budget_annual_input is created by
clickhouse/init-db.sql with the exact column list konsol's
_REFERENCE_TABLE_DDL carries (konsol A7 pins the same string): `layer` after
main_account, `currency` after layer. dim_* columns are added by ALTER.

An existing warehouse gets the two columns from konsol, not from this repo:
konsol's _POSITIONED_COLUMNS issues `ALTER TABLE ... ADD COLUMN IF NOT EXISTS
layer String AFTER main_account, ADD COLUMN IF NOT EXISTS currency String AFTER
layer` on migrate. init-db.sql has no upgrade path for an existing table.

Plain unittest: `python -m unittest -v tests.test_budget_annual_input_ddl`.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")

TABLE = "epm_gold.budget_annual_input"
COLUMNS = (
    "(scenario_id String, data_area_id String, fiscal_year UInt16, "
    "main_account String, layer String, currency String, "
    "annual_amount Decimal(18,2), spread_profile_id String, submitted_by String)"
)
ENGINE = (
    "ENGINE = MergeTree ORDER BY (scenario_id, data_area_id, fiscal_year, "
    "main_account)"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {COLUMNS} {ENGINE};"


def _normalise(sql):
    sql = re.sub(r"\s+", " ", sql.strip())
    return re.sub(r"\s*([(),])\s*", r"\1", sql)


class BudgetAnnualInputDDL(unittest.TestCase):

    def _statements(self):
        with open(INIT_DB, encoding="utf-8") as f:
            sql = re.sub(r"--[^\n]*", "", f.read())
        return [m.group(0) for m in re.finditer(
            r"CREATE TABLE IF NOT EXISTS " + re.escape(TABLE) + r"\b[^;]*;", sql)]

    def test_init_db_creates_the_table_once_with_the_pinned_shape(self):
        statements = self._statements()
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_layer_and_currency_follow_main_account(self):
        self.assertIn("main_account String, layer String, currency String,", COLUMNS)


if __name__ == "__main__":
    unittest.main()
