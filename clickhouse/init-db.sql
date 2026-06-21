-- Open EPM: ClickHouse database initialization
-- Creates medallion architecture databases + staging

CREATE DATABASE IF NOT EXISTS epm;
CREATE DATABASE IF NOT EXISTS epm_bronze;
CREATE DATABASE IF NOT EXISTS epm_silver;
CREATE DATABASE IF NOT EXISTS epm_gold;
CREATE DATABASE IF NOT EXISTS epm_allocated;
CREATE DATABASE IF NOT EXISTS epm_staging;

-- Staging table for budget write-back from Excel/API
CREATE TABLE IF NOT EXISTS epm_staging.budget_input (
    scenario_id String,
    legal_entity_id String,
    fiscal_year UInt16,
    fiscal_period UInt8,
    main_account String,
    dim_cost_center String DEFAULT '',
    dim_department String DEFAULT '',
    amount Decimal(18,2),
    submitted_by String,
    submitted_at DateTime DEFAULT now(),
    version UInt32 DEFAULT 1
) ENGINE = MergeTree()
ORDER BY (scenario_id, legal_entity_id, fiscal_year, fiscal_period, main_account);

-- Staging table for planning assumptions
CREATE TABLE IF NOT EXISTS epm_staging.planning_assumptions (
    scenario_id String,
    assumption_key String,
    assumption_value String,
    legal_entity_id String DEFAULT '',
    fiscal_year UInt16 DEFAULT 0,
    updated_by String,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (scenario_id, assumption_key, legal_entity_id, fiscal_year);

-- Staging table for scenario metadata
CREATE TABLE IF NOT EXISTS epm_staging.scenario_definitions (
    scenario_id String,
    scenario_name String,
    scenario_type String,
    base_scenario_id String DEFAULT '',
    is_active UInt8 DEFAULT 1,
    created_by String,
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (scenario_id);

-- ============================================================
-- PRD-8: Consolidation hierarchy (multi-level groups)
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_hierarchy (
    consolidation_group String,
    data_area_id String,
    parent_group String DEFAULT '',
    hierarchy_level UInt8 DEFAULT 1,
    effective_ownership_pct Decimal(5,2) DEFAULT 100.00,
    path String DEFAULT '',
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (consolidation_group, data_area_id);

-- ============================================================
-- PRD-10: Historical FX rates for equity accounts (IAS 21)
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.historical_equity_rates (
    consolidation_group String,
    data_area_id String,
    main_account String,
    rate_date Date,
    historical_rate Decimal(18,6),
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (consolidation_group, data_area_id, main_account, rate_date);

-- ============================================================
-- PRD-9 / PRD-11 / PRD-12: Ownership periods (temporal ownership,
--   step acquisitions, disposals)
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.ownership_periods (
    consolidation_group String,
    data_area_id String,
    effective_date Date,
    end_date Date DEFAULT '9999-12-31',
    ownership_pct Decimal(5,2),
    consolidation_method String DEFAULT 'full',
    -- PRD-11: Acquisition fields
    acquisition_date Date DEFAULT '1900-01-01',
    is_first_acquisition UInt8 DEFAULT 0,
    acquisition_price Decimal(18,2) DEFAULT 0,
    fair_value_adjustment Decimal(18,2) DEFAULT 0,
    -- PRD-12: Disposal fields
    disposal_date Date DEFAULT '9999-12-31',
    disposal_price Decimal(18,2) DEFAULT 0,
    is_disposal UInt8 DEFAULT 0,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (consolidation_group, data_area_id, effective_date);

-- ============================================================
-- PRD-16: Extended consolidation adjustments (workflow fields)
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_adjustments (
    consolidation_group String,
    adjustment_type String,
    journal_id String,
    data_area_id String,
    fiscal_year UInt16,
    fiscal_period UInt8,
    main_account String,
    debit_amount Decimal(18,2) DEFAULT 0,
    credit_amount Decimal(18,2) DEFAULT 0,
    description String DEFAULT '',
    posted_by String DEFAULT '',
    -- PRD-16: Workflow fields
    status String DEFAULT 'Approved',
    approved_by String DEFAULT '',
    approved_at DateTime DEFAULT '1970-01-01 00:00:00',
    reversal_journal_id String DEFAULT '',
    auto_reverse_period UInt8 DEFAULT 0,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (consolidation_group, journal_id, fiscal_year, fiscal_period, main_account);

-- ============================================================
-- PRD-17: Allocation rules & drivers (dynamic N-step engine)
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.allocation_rules (
    allocation_rule_id String,
    rule_name String,
    step_order UInt8,
    source_account String,
    source_cost_center String,
    driver_type String,
    target_account String,
    description String DEFAULT '',
    -- PRD-18: Reciprocal method field
    allocation_method String DEFAULT 'step_down',
    -- PRD-19: Composite driver formula
    driver_formula String DEFAULT '',
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (allocation_rule_id);

CREATE TABLE IF NOT EXISTS epm_staging.allocation_drivers (
    driver_type String,
    data_area_id String,
    cost_center String,
    fiscal_year UInt16,
    fiscal_period UInt8,
    driver_value Decimal(18,4) DEFAULT 0,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (driver_type, data_area_id, cost_center, fiscal_year, fiscal_period);

-- ============================================================
-- PRD-20: Allocation tiers (tiered & threshold rules)
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.allocation_tiers (
    allocation_rule_id String,
    tier_order UInt8,
    lower_bound Decimal(18,2) DEFAULT 0,
    upper_bound Decimal(18,2) DEFAULT 999999999.99,
    rate Decimal(8,4) DEFAULT 1.0000,
    cap Decimal(18,2) DEFAULT 999999999.99,
    floor Decimal(18,2) DEFAULT 0,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (allocation_rule_id, tier_order);

-- ============================================================
-- PRD-15: IC elimination rules (extended) & IC balances
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.ic_elimination_rules (
    rule_id String,
    rule_name String,
    debit_account String,
    credit_account String,
    debit_entity_pattern String DEFAULT '*',
    credit_entity_pattern String DEFAULT '*',
    description String DEFAULT '',
    -- PRD-15: Enhanced fields
    rule_type String DEFAULT 'balance',
    margin_pct Decimal(5,2) DEFAULT 0,
    asset_account String DEFAULT '',
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (rule_id);

CREATE TABLE IF NOT EXISTS epm_staging.ic_balances (
    selling_entity String,
    buying_entity String,
    fiscal_year UInt16,
    fiscal_period UInt8,
    ic_sales_amount Decimal(18,2) DEFAULT 0,
    ending_inventory_from_ic Decimal(18,2) DEFAULT 0,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (selling_entity, buying_entity, fiscal_year, fiscal_period);

-- ============================================================
-- PRD-21: Allocation runs (traceability & reversibility)
-- ============================================================
CREATE TABLE IF NOT EXISTS epm_staging.allocation_runs (
    allocation_run_id String,
    fiscal_year UInt16,
    fiscal_period UInt8,
    status String DEFAULT 'Active',
    run_by String DEFAULT '',
    run_at DateTime DEFAULT now(),
    reversal_of String DEFAULT '',
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (allocation_run_id);
