"""Budget S2 R1: epm_raw.budget_entries is created by clickhouse/init-db.sql
with the exact column list konsol's _REFERENCE_TABLE_DDL carries (konsol I3
pins the same string). No partner column; dim_* columns are added by ALTER.

Plain unittest: `python -m unittest -v tests.test_budget_raw_ddl`.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")

TABLE = "epm_raw.budget_entries"
COLUMNS = (
    "(entry_name String, cycle String, scenario_id String, layer String, "
    "data_area_id String, fiscal_year UInt16, fiscal_period UInt8, "
    "main_account String, debit Decimal(18,4), credit Decimal(18,4), "
    "currency String, amount_basis String)"
)
ENGINE = (
    "ENGINE = MergeTree ORDER BY (scenario_id, data_area_id, fiscal_year, "
    "fiscal_period, layer, main_account)"
)
EXPECTED_STATEMENT = f"CREATE TABLE IF NOT EXISTS {TABLE} {COLUMNS} {ENGINE};"


def _normalise(sql):
    sql = re.sub(r"\s+", " ", sql.strip())
    return re.sub(r"\s*([(),])\s*", r"\1", sql)


class BudgetEntriesRawDDL(unittest.TestCase):

    def _statements(self):
        with open(INIT_DB, encoding="utf-8") as f:
            sql = re.sub(r"--[^\n]*", "", f.read())
        return [m.group(0) for m in re.finditer(
            r"CREATE TABLE IF NOT EXISTS " + re.escape(TABLE) + r"\b[^;]*;", sql)]

    def test_init_db_creates_the_table_once_with_the_pinned_shape(self):
        statements = self._statements()
        self.assertEqual(len(statements), 1, statements)
        self.assertEqual(_normalise(statements[0]), _normalise(EXPECTED_STATEMENT))

    def test_the_table_is_created_after_the_epm_raw_database(self):
        with open(INIT_DB, encoding="utf-8") as f:
            sql = f.read()
        self.assertIn("CREATE DATABASE IF NOT EXISTS epm_raw;", sql)
        self.assertLess(sql.index("CREATE DATABASE IF NOT EXISTS epm_raw;"),
                        sql.index("CREATE TABLE IF NOT EXISTS " + TABLE))

    def test_no_partner_column(self):
        self.assertNotIn("partner", COLUMNS)


if __name__ == "__main__":
    unittest.main()
