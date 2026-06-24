"""
Test 1: Verify ClickHouse staging tables exist and accept data.
Exercises the same INSERT pattern that Frappe sync hooks use.
"""
import pytest


# ---------------------------------------------------------------------------
# Staging table existence
# ---------------------------------------------------------------------------
EXPECTED_STAGING_TABLES = [
    "scenario_definitions",
    "consolidation_hierarchy",
    "historical_equity_rates",
    "ownership_periods",
    "consolidation_adjustments",
    "allocation_rules",
    "allocation_drivers",
    "allocation_tiers",
    "ic_elimination_rules",
    "ic_balances",
    "allocation_runs",
]


def test_staging_database_exists(ch):
    result = ch("SELECT name FROM system.databases WHERE name = 'epm_staging' FORMAT TabSeparated")
    assert result == "epm_staging", "epm_staging database does not exist"


@pytest.mark.parametrize("table", EXPECTED_STAGING_TABLES)
def test_staging_table_exists(ch, table):
    result = ch(
        f"SELECT count() FROM system.tables "
        f"WHERE database = 'epm_staging' AND name = '{table}' FORMAT TabSeparated"
    )
    assert result == "1", f"epm_staging.{table} does not exist"


# ---------------------------------------------------------------------------
# Gold database/tables existence
# ---------------------------------------------------------------------------
EXPECTED_GOLD_DATABASES = ["epm", "epm_staging"]


@pytest.mark.parametrize("db", EXPECTED_GOLD_DATABASES)
def test_database_exists(ch, db):
    result = ch(f"SELECT name FROM system.databases WHERE name = '{db}' FORMAT TabSeparated")
    assert result == db


# ---------------------------------------------------------------------------
# Insert + read-back (simulates Frappe sync_table pattern)
# ---------------------------------------------------------------------------
class TestStagingInsert:
    """Insert test rows into staging tables and verify they arrive."""

    TEST_PREFIX = "__test_integ__"

    def test_insert_consolidation_hierarchy(self, ch):
        ch(f"""
            INSERT INTO epm_staging.consolidation_hierarchy
            (consolidation_group, data_area_id, entity_name, parent_group,
             ownership_pct, consolidation_method, hierarchy_level, hierarchy_path,
             lft, rgt, updated_at)
            VALUES
            ('{self.TEST_PREFIX}Group', '{self.TEST_PREFIX}E001', 'Test Entity', '',
             100.0, 'full', 0, '/{self.TEST_PREFIX}Group',
             1, 2, now())
        """)
        count = ch(
            f"SELECT count() FROM epm_staging.consolidation_hierarchy "
            f"WHERE consolidation_group = '{self.TEST_PREFIX}Group' FORMAT TabSeparated"
        )
        assert int(count) >= 1

    def test_insert_ownership_periods(self, ch):
        ch(f"""
            INSERT INTO epm_staging.ownership_periods
            (name, consolidation_group, data_area_id, effective_date, end_date,
             ownership_pct, consolidation_method,
             is_first_acquisition, acquisition_date, acquisition_price, fair_value_adjustment,
             is_disposal, disposal_date, disposal_price, updated_at)
            VALUES
            ('{self.TEST_PREFIX}OP1', '{self.TEST_PREFIX}Group', '{self.TEST_PREFIX}E001',
             '2025-01-01', '2025-12-31',
             100.0, 'full',
             0, '1900-01-01', 0, 0,
             0, '1900-01-01', 0, now())
        """)
        count = ch(
            f"SELECT count() FROM epm_staging.ownership_periods "
            f"WHERE name = '{self.TEST_PREFIX}OP1' FORMAT TabSeparated"
        )
        assert int(count) >= 1

    def test_insert_allocation_rules(self, ch):
        ch(f"""
            INSERT INTO epm_staging.allocation_rules
            (allocation_rule_id, rule_name, source_account, driver_type,
             allocation_method, step_order, driver_formula, updated_at)
            VALUES
            ('{self.TEST_PREFIX}R1', 'Test Rule', '7000', 'headcount',
             'step_down', 1, '', now())
        """)
        count = ch(
            f"SELECT count() FROM epm_staging.allocation_rules "
            f"WHERE allocation_rule_id = '{self.TEST_PREFIX}R1' FORMAT TabSeparated"
        )
        assert int(count) >= 1

    def test_insert_ic_elimination_rules(self, ch):
        ch(f"""
            INSERT INTO epm_staging.ic_elimination_rules
            (rule_id, rule_name, source_entity, target_entity,
             ic_account, elimination_account, rule_type, margin_pct,
             asset_account, updated_at)
            VALUES
            ('{self.TEST_PREFIX}IC1', 'Test IC Rule', '{self.TEST_PREFIX}E001', '{self.TEST_PREFIX}E002',
             '4000', '9999', 'revenue_cost', 0,
             '', now())
        """)
        count = ch(
            f"SELECT count() FROM epm_staging.ic_elimination_rules "
            f"WHERE rule_id = '{self.TEST_PREFIX}IC1' FORMAT TabSeparated"
        )
        assert int(count) >= 1

    def test_cleanup_test_data(self, ch):
        """Clean up test data inserted by this test class."""
        for table in EXPECTED_STAGING_TABLES:
            try:
                ch(
                    f"ALTER TABLE epm_staging.{table} DELETE "
                    f"WHERE toString(consolidation_group) LIKE '{self.TEST_PREFIX}%' "
                    f"OR toString(name) LIKE '{self.TEST_PREFIX}%' "
                    f"OR toString(allocation_rule_id) LIKE '{self.TEST_PREFIX}%' "
                    f"OR toString(rule_id) LIKE '{self.TEST_PREFIX}%'"
                )
            except Exception:
                pass  # Some tables may not have these columns
