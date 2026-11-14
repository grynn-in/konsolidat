-- gate: build gold_spread_budget assert_budget_fact_grain_unique
-- gate: expect assert_budget_fact_grain_unique pass
-- konsolidat#300: gold_spread_budget emits one row per layer, so the grain test must group by layer.
-- Two layers (base, challenge) of one budget at one (scenario, entity, year, period, account) grain are
-- two legitimate rows: the test must PASS.
--
-- gold_spread_budget also reads these tables, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles.
-- epm_raw.budget_entries is konsol's (I3) and may not exist on the stack yet: created here as in budget_raw_monthly.
CREATE TABLE IF NOT EXISTS epm_raw.budget_entries (
    entry_name String, cycle String, scenario_id String, layer String,
    data_area_id String, fiscal_year UInt16, fiscal_period UInt8,
    main_account String, debit Decimal(18,4), credit Decimal(18,4),
    currency String, amount_basis String
) ENGINE = MergeTree
ORDER BY (scenario_id, data_area_id, fiscal_year, fiscal_period, layer, main_account);
ALTER TABLE epm_raw.budget_entries ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.budget_entries ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1200, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', '');
