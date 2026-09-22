"""
Test 1: the staging tables konsol writes accept the rows konsol writes.

Two tables only -- epm_staging.ownership_periods and
epm_staging.ic_elimination_rules -- because their column lists are asserted
nowhere else. Neither is in konsol's _REFERENCE_TABLE_DDL
(test_write_through_contract.py:190-224), neither is in the six DDL contract
tests, and konsol's own coverage is a mocked execute or a string grep. A real
INSERT is the only thing that catches a column drift in them, as it did in
81b468c (source_entity -> debit_entity_pattern).

What this file used to assert and no longer does (konsolidat#227 row 2): that
the databases and the seven staging tables exist, which clickhouse/init-db.sql
creates, konsol's bootstrap contract asserts and the tb-only-first-build job
proves on every run; and that a bare `epm` database exists, which nothing in
the system ever writes to.
"""
import pytest


class TestStagingInsert:
    """Insert into the staging tables konsol writes, and read the rows back."""

    TEST_PREFIX = "__test_integ__"

    # the column each kept insert can be found and removed by
    CLEANUP = {
        "ownership_periods": "consolidation_group",
        "ic_elimination_rules": "rule_id",
    }

    @pytest.fixture(autouse=True)
    def _drop_test_rows(self, ch):
        """Teardown belongs here, not in a test.

        It used to live in test_cleanup_test_data, which had no assert and
        swallowed every exception -- it could not fail, and it only ran because
        pytest happened to collect it last. The rows these tests insert carry a
        100% ownership period and an elimination rule for entities that exist in
        no chart; left behind, they reach the consolidation models and the close
        assertions later in the same run.
        """
        yield
        for table, column in self.CLEANUP.items():
            ch(
                f"ALTER TABLE epm_staging.{table} DELETE "
                f"WHERE toString({column}) LIKE '{self.TEST_PREFIX}%' "
                f"SETTINGS mutations_sync = 1"
            )

    def test_insert_ownership_periods(self, ch):
        ch(f"""
            INSERT INTO epm_staging.ownership_periods
            (consolidation_group, data_area_id, effective_date, end_date,
             ownership_pct, consolidation_method,
             is_first_acquisition, acquisition_date, acquisition_price, fair_value_adjustment,
             is_disposal, disposal_date, disposal_price, updated_at)
            VALUES
            ('{self.TEST_PREFIX}Group', '{self.TEST_PREFIX}E001',
             '2025-01-01', '2025-12-31',
             100.0, 'full',
             0, '1900-01-01', 0, 0,
             0, '1900-01-01', 0, now())
        """)
        count = ch(
            f"SELECT count() FROM epm_staging.ownership_periods "
            f"WHERE consolidation_group = '{self.TEST_PREFIX}Group' FORMAT TabSeparated"
        )
        assert int(count) >= 1

    def test_insert_ic_elimination_rules(self, ch):
        ch(f"""
            INSERT INTO epm_staging.ic_elimination_rules
            (rule_id, rule_name, debit_entity_pattern, credit_entity_pattern,
             debit_account, credit_account, description, rule_type, margin_pct,
             asset_account, updated_at)
            VALUES
            ('{self.TEST_PREFIX}IC1', 'Test IC Rule', '{self.TEST_PREFIX}E001', '{self.TEST_PREFIX}E002',
             '4000', '9999', 'integration fixture', 'revenue_cost', 0,
             '', now())
        """)
        count = ch(
            f"SELECT count() FROM epm_staging.ic_elimination_rules "
            f"WHERE rule_id = '{self.TEST_PREFIX}IC1' FORMAT TabSeparated"
        )
        assert int(count) >= 1
