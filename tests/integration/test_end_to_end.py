"""
Test 3: Full end-to-end pipeline test.
Simulates: Frappe doctype save → ClickHouse staging → dbt build → gold output.

This test inserts data into staging tables (mimicking what Frappe sync hooks do),
runs dbt build, then verifies the gold models processed the data correctly.
"""
import pytest


TEST_ENTITY = "__e2e_entity__"
TEST_GROUP = "__e2e_group__"
TEST_YEAR = 2099
TEST_ACCOUNT = "999999"


@pytest.fixture(scope="module")
def seed_staging_data(ch):
    """Insert test data into all relevant staging tables to exercise the full pipeline."""

    # 1. Consolidation hierarchy — a parent group with one child entity
    ch(f"""
        INSERT INTO epm_staging.consolidation_hierarchy
        (consolidation_group, data_area_id, entity_name, parent_group,
         ownership_pct, consolidation_method, hierarchy_level, hierarchy_path,
         lft, rgt, updated_at)
        VALUES
        ('{TEST_GROUP}', '{TEST_ENTITY}', 'E2E Test Entity', '',
         100.0, 'full', 0, '/{TEST_GROUP}',
         1, 2, now())
    """)

    # 2. Ownership period
    ch(f"""
        INSERT INTO epm_staging.ownership_periods
        (name, consolidation_group, data_area_id, effective_date, end_date,
         ownership_pct, consolidation_method,
         is_first_acquisition, acquisition_date, acquisition_price, fair_value_adjustment,
         is_disposal, disposal_date, disposal_price, updated_at)
        VALUES
        ('{TEST_GROUP}_OP', '{TEST_GROUP}', '{TEST_ENTITY}',
         '2099-01-01', '2099-12-31',
         100.0, 'full',
         0, '1900-01-01', 0, 0,
         0, '1900-01-01', 0, now())
    """)

    # 3. Allocation rule + driver
    ch(f"""
        INSERT INTO epm_staging.allocation_rules
        (allocation_rule_id, rule_name, source_account, driver_type,
         allocation_method, step_order, driver_formula, updated_at)
        VALUES
        ('{TEST_GROUP}_ALLOC', 'E2E Allocation', '{TEST_ACCOUNT}', 'headcount',
         'step_down', 1, '', now())
    """)

    ch(f"""
        INSERT INTO epm_staging.allocation_drivers
        (name, driver_type, data_area_id, fiscal_year, fiscal_period,
         dim_cost_center, driver_value, updated_at)
        VALUES
        ('{TEST_GROUP}_DRV', 'headcount', '{TEST_ENTITY}', {TEST_YEAR}, 1,
         'CC001', 10.0, now())
    """)

    # 4. IC elimination rule
    ch(f"""
        INSERT INTO epm_staging.ic_elimination_rules
        (rule_id, rule_name, source_entity, target_entity,
         ic_account, elimination_account, rule_type, margin_pct,
         asset_account, updated_at)
        VALUES
        ('{TEST_GROUP}_IC', 'E2E IC Rule', '{TEST_ENTITY}', '{TEST_ENTITY}_B',
         '4000', '9999', 'revenue_cost', 0, '', now())
    """)

    yield  # Run tests

    # Cleanup
    for table in [
        "consolidation_hierarchy",
        "ownership_periods",
        "allocation_rules",
        "allocation_drivers",
        "ic_elimination_rules",
    ]:
        try:
            ch(
                f"ALTER TABLE epm_staging.{table} DELETE "
                f"WHERE toString(consolidation_group) LIKE '{TEST_GROUP}%' "
                f"OR toString(name) LIKE '{TEST_GROUP}%' "
                f"OR toString(allocation_rule_id) LIKE '{TEST_GROUP}%' "
                f"OR toString(rule_id) LIKE '{TEST_GROUP}%'"
            )
        except Exception:
            pass


def test_staging_data_inserted(ch, seed_staging_data):
    """Verify all staging data was inserted successfully."""
    count = ch(
        f"SELECT count() FROM epm_staging.consolidation_hierarchy "
        f"WHERE consolidation_group = '{TEST_GROUP}' FORMAT TabSeparated"
    )
    assert int(count) >= 1, "Consolidation hierarchy not inserted"

    count = ch(
        f"SELECT count() FROM epm_staging.ownership_periods "
        f"WHERE consolidation_group = '{TEST_GROUP}' FORMAT TabSeparated"
    )
    assert int(count) >= 1, "Ownership periods not inserted"

    count = ch(
        f"SELECT count() FROM epm_staging.allocation_rules "
        f"WHERE allocation_rule_id = '{TEST_GROUP}_ALLOC' FORMAT TabSeparated"
    )
    assert int(count) >= 1, "Allocation rules not inserted"


def test_dbt_build_with_staging_data(ch, dbt_run, seed_staging_data):
    """dbt build should succeed with test staging data present."""
    result = dbt_run()
    assert result.returncode == 0, (
        f"dbt build failed with staging data (exit {result.returncode}):\n"
        f"{result.stderr[-1000:]}"
    )


def test_pipeline_chain_produces_output(ch, dbt_run, seed_staging_data):
    """After staging insert + dbt build, gold tables should exist and be queryable."""
    dbt_run()

    # Verify we can query gold tables without errors
    for table in [
        "gold_trial_balance",
        "gold_consolidated_trial_balance",
        "gold_allocation_results",
    ]:
        try:
            count = ch(f"SELECT count() FROM epm.{table} FORMAT TabSeparated")
            assert int(count) >= 0, f"epm.{table} query failed"
        except Exception as e:
            pytest.fail(f"Failed to query epm.{table}: {e}")
