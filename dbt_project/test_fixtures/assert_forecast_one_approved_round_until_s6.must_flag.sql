-- gate: build gold_spread_budget assert_forecast_one_approved_round_until_s6
-- gate: expect assert_forecast_one_approved_round_until_s6 flag 1
-- konsol#348 S3 review (interim rule until S6, posted 15 Nov 2026): a forecast (scenario, fiscal year)
-- holds at most one approved round, because gold_scenario_trial_balance, the cost-allocation pool, the
-- forecast_input Dataset and hierarchy_query still sum rounds across the cycle. Scenario ZZ_FC_2026 is
-- declared scenario_type 'forecast' and FY2026 reaches gold_spread_budget under two cycles, ZZ-FC-R1 and
-- ZZ-FC-R2: 1 result. ZZ_FC_2027 holds one cycle with two lines and is not named.
-- REMOVED IN S6 with the test, when the latest-estimate read picks the round.
--
-- gold_spread_budget also reads epm_gold.budget_annual_input; the live table may predate `cycle` (B3w):
-- add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast 2026', 'forecast', 1),
  ('ZZ_FC_2027', 'ZZ forecast 2027', 'forecast', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 110, 'USD', 'Period movement'),
  ('ZZ-BE-R3', 'ZZ-FC-R3', 'ZZ_FC_2027', 'base', 'ZZE1', 2027, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-R3', 'ZZ-FC-R3', 'ZZ_FC_2027', 'base', 'ZZE1', 2027, 2, 'ZZ4000', 0, 120, 'USD', 'Period movement');
