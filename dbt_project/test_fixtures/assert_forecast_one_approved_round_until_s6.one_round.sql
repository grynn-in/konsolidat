-- gate: build gold_spread_budget assert_forecast_one_approved_round_until_s6
-- gate: expect assert_forecast_one_approved_round_until_s6 pass
-- konsol#348 S3 review (interim rule until S6, posted 15 Nov 2026): a forecast (scenario, fiscal year)
-- with ONE approved round is not named. Scenario ZZ_FC_2026 is declared 'forecast' and FY2026 reaches
-- gold_spread_budget under one cycle, ZZ-FC-R1, with two lines. Scenario ZZ_PLAN_2026 is a budget and
-- holds two cycles: not this test's rule (assert_budget_one_cycle_per_scenario_year names it), so it is
-- not named here either. Must PASS.
-- REMOVED IN S6 with the test, when the latest-estimate read picks the round.
--
-- gold_spread_budget also reads epm_gold.budget_annual_input; the live table may predate `cycle` (B3w):
-- add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast 2026', 'forecast', 1),
  ('ZZ_PLAN_2026', 'ZZ plan 2026', 'budget', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 120, 'USD', 'Period movement'),
  ('ZZ-BE-A', 'ZZ-CY-A', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-B', 'ZZ-CY-B', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement');
