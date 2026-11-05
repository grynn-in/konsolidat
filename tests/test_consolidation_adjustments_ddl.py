"""konsol#353 option C (Deepak Pai, 5 Nov 2026): Consolidation Journal amounts
are stored to 4 decimal places, so a group reporting in a 3-decimal currency
(BHD, KWD, OMR) keeps every line exactly.

konsol owns epm_staging.consolidation_adjustments: its `_REFERENCE_TABLE_DDL`
creates the table on every migrate and widens an existing one with
`ALTER TABLE ... MODIFY COLUMN`. This repo's clickhouse/init-db.sql creates it
on a fresh volume. Whichever runs first wins, so the two bodies must be the
same text. The body below is konsol's, verbatim (konsol/clickhouse.py).

Before konsol#353 the amounts were `Decimal(18,2)`: a BHD line of 0.004 was
cut to 0.00 on insert (ClickHouse truncates extra places without an error).
The fixtures assert_topside_journal_balanced.three_decimal*.sql show it end to
end; this test pins the type.

Plain unittest, no third-party imports, so CI runs it with
`python -m unittest -v tests.test_consolidation_adjustments_ddl`.
"""
import os
import unittest

from tests.test_deal_tables_ddl import _create_statements, _normalise, _read

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT_DB = os.path.join(PROJECT_ROOT, "clickhouse", "init-db.sql")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

TABLE = "epm_staging.consolidation_adjustments"
# konsol's body, verbatim (konsol/clickhouse.py _REFERENCE_TABLE_DDL).
BODY = (
    "(consolidation_group String, adjustment_type String, journal_id String, "
    "data_area_id String, fiscal_year UInt16, fiscal_period UInt8, "
    "main_account String, debit_amount Decimal(20,4) DEFAULT 0, "
    "credit_amount Decimal(20,4) DEFAULT 0, description String DEFAULT '', "
    "posted_by String DEFAULT '', status String DEFAULT 'Approved', "
    "approved_by String DEFAULT '', approved_at DateTime DEFAULT '1970-01-01 00:00:00', "
    "reversal_journal_id String DEFAULT '', created_at DateTime DEFAULT now(), "
    "reverse_fiscal_year UInt16 DEFAULT 0, reverse_fiscal_period UInt8 DEFAULT 0) "
    "ENGINE = MergeTree() ORDER BY (consolidation_group, journal_id, fiscal_year, "
    "fiscal_period, main_account)"
)


class ConsolidationAdjustmentsDDL(unittest.TestCase):

    def test_init_db_creates_the_journal_table_once_with_konsols_shape(self):
        statements = _create_statements(_read(INIT_DB), TABLE)
        self.assertEqual(len(statements), 1, statements)
        expected = f"CREATE TABLE IF NOT EXISTS {TABLE} {BODY};"
        self.assertEqual(_normalise(statements[0]), _normalise(expected))

    def test_journal_amounts_keep_four_decimal_places(self):
        statement = _normalise(_create_statements(_read(INIT_DB), TABLE)[0])
        for column in ("debit_amount", "credit_amount"):
            with self.subTest(column=column):
                self.assertIn(_normalise(f"{column} Decimal(20,4) DEFAULT 0"), statement)

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_consolidation_adjustments_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_consolidation_adjustments_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
