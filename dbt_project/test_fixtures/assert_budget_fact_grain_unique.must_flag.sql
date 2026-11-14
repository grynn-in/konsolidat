-- gate: build gold_spread_budget assert_budget_fact_grain_unique
-- gate: expect assert_budget_fact_grain_unique flag 1
-- konsolidat#300: the same layer twice at one grain is a real duplicate: the test must still FLAG it.
-- Manual Budget Entry lines are summed into one row per grain (R2), so they can no longer duplicate a grain.
-- The duplicate now comes from two 'base' annual inputs for ZZ_PLAN_2026 / ZZE1 / 2026 / ZZ4000 spread by a
-- one-period profile: two rows at P1, one duplicated group (1 result).
--
-- gold_spread_budget also reads these tables, empty here, so it is created empty:
-- epm_raw.budget_entries (konsol's I3; created here as in budget_raw_monthly).
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', -1200, 'ZZ_ONE', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', -100, 'ZZ_ONE', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_ONE', 'ZZ one period', 1, 1);
