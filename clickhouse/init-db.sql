-- Open EPM: ClickHouse database initialization
-- Creates medallion architecture databases + staging

CREATE DATABASE IF NOT EXISTS epm;
CREATE DATABASE IF NOT EXISTS epm_bronze;
CREATE DATABASE IF NOT EXISTS epm_silver;
CREATE DATABASE IF NOT EXISTS epm_gold;
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
