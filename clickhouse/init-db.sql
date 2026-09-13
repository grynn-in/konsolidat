-- Open EPM: ClickHouse database initialization
-- Creates medallion architecture databases + staging

CREATE DATABASE IF NOT EXISTS epm;
CREATE DATABASE IF NOT EXISTS epm_bronze;
CREATE DATABASE IF NOT EXISTS epm_silver;
CREATE DATABASE IF NOT EXISTS epm_gold;
CREATE DATABASE IF NOT EXISTS epm_allocated;
CREATE DATABASE IF NOT EXISTS epm_staging;

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
-- F2: no ownership column here. It used to carry effective_ownership_pct, which
-- in fact held the DIRECT percentage (konsol wrote `ownership_pct or 100`) and
-- had no date grain, so it could never expire. Ownership is temporal and lives
-- only in epm_staging.ownership_periods.
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_hierarchy (
    consolidation_group String,
    data_area_id String,
    parent_group String DEFAULT '',
    hierarchy_level UInt8 DEFAULT 1,
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

-- F8: trial-balance submission landing + control tables. Two owners, two jobs:
-- this file bootstraps a fresh install; konsol's Trial Balance Submission
-- doctype (_ensure_tables) self-heals at runtime. KEEP THE TWO IN SYNC — the
-- schemas are IF NOT EXISTS, so drift never errors at creation time, only at
-- konsol's INSERT or bronze's SELECT.
CREATE DATABASE IF NOT EXISTS epm_raw;

-- konsol#159: partner_data_area_id is the intercompany partner entity on a row
-- ('' = none). konsol's ensure_raw_tables() adds it to a table created before.
CREATE TABLE IF NOT EXISTS epm_raw.trial_balance_submissions (
    batch_id String, data_area_id String, fiscal_year UInt16,
    fiscal_period UInt8, main_account String,
    debit_amount Float64, credit_amount Float64,
    description String, submission_name String, submitted_at DateTime,
    partner_data_area_id String DEFAULT ''
) ENGINE = MergeTree ORDER BY (batch_id, main_account);

-- ReplacingMergeTree keyed on batch_id: a duplicated claim (an at-least-once
-- retry of konsol's on_submit) collapses to one row instead of fanning out the
-- bronze join — the same idempotency choice as epm_staging.sync_watermark.
CREATE TABLE IF NOT EXISTS epm_raw.trial_balance_submission_control (
    batch_id String, submission_name String, data_area_id String,
    fiscal_year UInt16, fiscal_period UInt8, row_count UInt32,
    claimed_at DateTime
) ENGINE = ReplacingMergeTree(claimed_at) ORDER BY batch_id;

-- F3: governed reference data written through from konsol (Dimension Mapping,
-- Cash Flow Category, Reporting Hierarchy) — these were CSV seeds regenerated
-- into the dbt repo on every save and migrate. One metadata path now: Frappe
-- doctype -> epm_staging -> dbt source. konsol's sync (TRUNCATE+INSERT of
-- Published rows) populates them; reconcile_all repairs after fixture import.
-- entity in the KEY, between erp_source and source_value: D365 gives each
-- legal entity its own dimension value set (cost centre 100 = Sales in USMF,
-- Manufacturing in DEMF), and ClickHouse cannot insert a column into the
-- middle of an existing MergeTree sort key later. entity='' = the ERP-wide
-- default; entity-specific rows take precedence (konsol #111).
CREATE TABLE IF NOT EXISTS epm_staging.dimension_mappings (
    dimension String, erp_source String, entity String, source_value String,
    canonical_value String, canonical_label String, status String
) ENGINE = MergeTree ORDER BY (dimension, erp_source, entity, source_value);

CREATE TABLE IF NOT EXISTS epm_staging.cash_flow_categories (
    main_account String, cf_category String, cf_line_item String,
    is_cash UInt8, sign Int8, status String
) ENGINE = MergeTree ORDER BY main_account;

CREATE TABLE IF NOT EXISTS epm_staging.reporting_hierarchies (
    hierarchy_name String, dimension String, member_code String,
    member_label String, parent_member_code String, is_group UInt8,
    hierarchy_level UInt16, path String, effective_from String,
    effective_to String, is_default UInt8, status String
) ENGINE = MergeTree ORDER BY (hierarchy_name, member_code);

-- F2: the consolidation structure and its link closure.
--
-- epm_gold.consolidation_groups was created by `dbt seed` from
-- seeds/consolidation_groups.csv — the SAME relation konsol TRUNCATE+INSERTs,
-- so a governed build and a bench migrate overwrote each other's ownership
-- figures. The seed is deleted and this is the DDL; konsol's
-- ensure_reference_tables() creates it on volumes that predate F2.
-- konsol#159: a group node also carries its intercompany-difference account
-- and tolerance (gold_ic_reconciliation, gold_ic_eliminations). konsol's
-- ensure_reference_tables() adds both to a table created before.
CREATE TABLE IF NOT EXISTS epm_gold.consolidation_groups (
    consolidation_group String, data_area_id String, entity_name String,
    reporting_currency String, ic_difference_account String DEFAULT '',
    ic_difference_tolerance Float64 DEFAULT 0
) ENGINE = MergeTree ORDER BY (consolidation_group, data_area_id);

-- One row per (ancestor group, entity, link on the chain between them), written
-- by konsol's tree walk. gold_entity_ownership multiplies each link's dated
-- percentage, which is how a 60%-owned subsidiary of an 80%-owned sub-group
-- reaches the top group at 48% instead of not reaching it at all.
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_ancestry (
    consolidation_group String, data_area_id String, link_group String,
    link_data_area_id String, link_depth UInt8, depth UInt8, path String
) ENGINE = MergeTree ORDER BY (consolidation_group, data_area_id, link_depth);

-- konsol#110: the governed entity registry, written through from konsol's Entity
-- doctype. The warehouse used to know entities only from ERP extraction
-- (silver_legal_entities), so a subsidiary with no connector had no accounting
-- currency and gold_consolidated_trial_balance dropped it at the join.
-- konsol's ensure_reference_tables() creates it on volumes that predate this.
CREATE TABLE IF NOT EXISTS epm_staging.entities (
    data_area_id String, entity_name String, parent_entity String,
    is_group UInt8, status String, accounting_currency String,
    country String, erp_source String
) ENGINE = MergeTree ORDER BY data_area_id;

-- konsol#159: the intercompany flag on the group chart, written through from
-- konsol's Intercompany Account doctype (Published rows). counterpart_account
-- is the account the partner books the other side on ('' = the same account).
-- Keep in step with konsol's _REFERENCE_TABLE_DDL.
CREATE TABLE IF NOT EXISTS epm_staging.intercompany_accounts (
    main_account String, counterpart_account String, description String,
    status String
) ENGINE = MergeTree ORDER BY main_account;

-- konsolidat#146: two more relations that a dbt seed and a konsol write-through
-- both owned. Seeds materialise into epm_gold (`seeds: +schema: gold`), so
-- seeds/spread_profiles.csv WAS epm_gold.spread_profiles — the same table the
-- Spread Profile doctype TRUNCATE+INSERTs, and whichever of `dbt seed` and
-- `bench migrate` ran last won. The seeds are deleted; konsol is the source and
-- konsol's ensure_reference_tables() creates these on volumes that predate the
-- change. Keep both in step with _REFERENCE_TABLE_DDL.
CREATE TABLE IF NOT EXISTS epm_gold.spread_profiles (
    profile_id String, profile_name String, fiscal_period Int32, weight Float32
) ENGINE = MergeTree ORDER BY (profile_id, fiscal_period);

CREATE TABLE IF NOT EXISTS epm_gold.scenario_definitions (
    scenario_id String, scenario_name String, scenario_type String, is_active Int32
) ENGINE = MergeTree ORDER BY scenario_id;

-- konsolidat#146: the ISO 4217 reference list, published from Frappe's Currency
-- records by konsol.currency_sync. It was seeds/currencies.csv.
CREATE TABLE IF NOT EXISTS epm_gold.currencies (
    currency_code String, currency_name String, symbol String, minor_unit UInt8
) ENGINE = MergeTree ORDER BY currency_code;

-- konsolidat#146: which fiscal calendar each ERP legal entity posts against,
-- from konsol's Entity Fiscal Calendar doctype. It was
-- seeds/entity_fiscal_calendars.csv.
CREATE TABLE IF NOT EXISTS epm_gold.entity_fiscal_calendars (
    data_area_id String, fiscal_calendar_id String
) ENGINE = MergeTree ORDER BY data_area_id;

-- konsolidat#146: the two halves of budget input, both from konsol.
-- budget_annual_input was seeds/budget_annual_input.csv — a top-down annual
-- figure that gold_spread_budget spreads into months by profile.
-- budget_monthly_input is the bottom-up half, written by Budget Sheet; it has
-- always been a konsol write-through with nothing that creates it, which is why
-- gold_spread_budget has been failing every build.
CREATE TABLE IF NOT EXISTS epm_gold.budget_annual_input (
    scenario_id String, data_area_id String, fiscal_year UInt16,
    main_account String, dim_cost_center String, dim_department String,
    annual_amount Decimal(18,2), spread_profile_id String, submitted_by String
) ENGINE = MergeTree ORDER BY (scenario_id, data_area_id, fiscal_year, main_account);

CREATE TABLE IF NOT EXISTS epm_gold.budget_monthly_input (
    scenario_id String, data_area_id String, fiscal_year UInt16,
    main_account String, dim_cost_center String, dim_department String,
    fiscal_period UInt8, amount Decimal(18,2), layer String
) ENGINE = MergeTree ORDER BY (scenario_id, data_area_id, fiscal_year, layer);

