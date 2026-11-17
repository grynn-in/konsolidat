-- gate: build gold_spread_budget gold_forecast_current_round gold_forecast_current assert_forecast_current_ties_to_fact
-- gate: expect gold_forecast_current built
-- gate: expect assert_forecast_current_ties_to_fact pass
-- konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026: the Excel forecast read's view holds the
-- declared round alone. Forecast scenario ZZ_FC_2026, FY2026 P1, ZZ4000, entity ZZE1 (USD): round
-- ZZ-FC-R1 credits 100 and round ZZ-FC-R2 credits 110, both approved; the Current Forecast declares R2.
-- gold_forecast_current must hold exactly R2's one row (-110) and no R1 row: the ties test passes.
-- Budget scenario ZZ_PLAN_2026 (one Cycle) is not a forecast and is not in the view.
--
-- gold_spread_budget also reads epm_gold.budget_annual_input and epm_gold.spread_profiles (empty here);
-- the live annual table may predate `cycle` (B3w): add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_2026', 'ZZ plan', 'budget', 1);
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-FC-R1', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-FC-R2', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-CY-A', 'ZZ_PLAN_2026', 2026, 'ZZRS', DEFAULT, 0);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 110, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-A', 'ZZ-CY-A', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', '');
