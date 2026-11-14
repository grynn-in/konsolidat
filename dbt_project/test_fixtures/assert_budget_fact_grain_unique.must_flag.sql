-- gate: build gold_spread_budget assert_budget_fact_grain_unique
-- gate: expect assert_budget_fact_grain_unique flag 1
-- konsolidat#300: the same layer twice at one grain is a real duplicate: the test must still FLAG it.
-- Two 'base' rows for ZZ_PLAN_2026 / ZZE1 / 2026 / P1 / ZZ4000 give one duplicated group (1 result).
--
-- gold_spread_budget also reads these tables, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles.
INSERT INTO epm_gold.budget_monthly_input
  (scenario_id, data_area_id, fiscal_year, main_account, fiscal_period, amount, layer)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1, -1200, 'base'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1, -100, 'base');
