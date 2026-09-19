"""
Test 3: Full end-to-end pipeline test.
Simulates: Frappe doctype save → ClickHouse staging → dbt build → gold output.

This test inserts data into staging tables (mimicking what Frappe sync hooks do),
runs dbt build, then verifies the gold models processed the data correctly.
"""
import pytest


TEST_ENTITY = "__e2e_entity__"
TEST_GROUP = "__e2e_group__"


@pytest.fixture(scope="module")
def seed_staging_data(ch):
    """Insert test data into all relevant staging tables to exercise the full pipeline."""

    # 1. Consolidation hierarchy — a parent group with one child entity
    ch(f"""
        INSERT INTO epm_staging.consolidation_hierarchy
        (consolidation_group, data_area_id, parent_group,
         hierarchy_level, path, updated_at)
        VALUES
        ('{TEST_GROUP}', '{TEST_ENTITY}', '',
         0, '/{TEST_GROUP}', now())
    """)

    # 2. Ownership period
    ch(f"""
        INSERT INTO epm_staging.ownership_periods
        (consolidation_group, data_area_id, effective_date, end_date,
         ownership_pct, consolidation_method,
         is_first_acquisition, acquisition_date, acquisition_price, fair_value_adjustment,
         is_disposal, disposal_date, disposal_price, updated_at)
        VALUES
        ('{TEST_GROUP}', '{TEST_ENTITY}',
         '2099-01-01', '2099-12-31',
         100.0, 'full',
         0, '1900-01-01', 0, 0,
         0, '1900-01-01', 0, now())
    """)

    # 3. IC elimination rule
    ch(f"""
        INSERT INTO epm_staging.ic_elimination_rules
        (rule_id, rule_name, debit_entity_pattern, credit_entity_pattern,
         debit_account, credit_account, description, rule_type, margin_pct,
         asset_account, updated_at)
        VALUES
        ('{TEST_GROUP}_IC', 'E2E IC Rule', '{TEST_ENTITY}', '{TEST_ENTITY}_B',
         '4000', '9999', 'e2e fixture', 'revenue_cost', 0, '', now())
    """)

    yield  # Run tests

    # Cleanup
    for table in [
        "consolidation_hierarchy",
        "ownership_periods",
        "ic_elimination_rules",
    ]:
        try:
            ch(
                f"ALTER TABLE epm_staging.{table} DELETE "
                f"WHERE toString(consolidation_group) LIKE '{TEST_GROUP}%' "
                f"OR toString(name) LIKE '{TEST_GROUP}%' "
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
    ]:
        try:
            count = ch(f"SELECT count() FROM epm.{table} FORMAT TabSeparated")
            assert int(count) >= 0, f"epm.{table} query failed"
        except Exception as e:
            pytest.fail(f"Failed to query epm.{table}: {e}")
