-- gate: build gold_spread_budget assert_budget_fact_grain_unique
-- gate: expect assert_budget_fact_grain_unique pass
-- konsolidat#300: gold_spread_budget emits one row per layer, so the grain test must group by layer.
-- Two layers (base, challenge) of one budget at one (scenario, entity, year, period, account) grain are
-- two legitimate rows: the test must PASS.
--
-- gold_spread_budget also reads these tables, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1200, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', '');
