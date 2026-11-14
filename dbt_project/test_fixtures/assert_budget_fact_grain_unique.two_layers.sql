-- gate: build gold_spread_budget assert_budget_fact_grain_unique
-- gate: expect assert_budget_fact_grain_unique pass
-- konsolidat#300: gold_spread_budget emits one row per layer, so the grain test must group by layer.
-- Two layers (base, challenge) of one budget at one (scenario, entity, year, period, account) grain are
-- two legitimate rows: the test must PASS.
--
-- gold_spread_budget also reads these tables, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles.
INSERT INTO epm_gold.budget_monthly_input
  (scenario_id, data_area_id, fiscal_year, main_account, fiscal_period, amount, layer)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1, -1200, 'base'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1, -100, 'challenge');
