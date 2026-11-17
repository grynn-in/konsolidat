-- gate: build gold_forecast_current_round assert_forecast_year_has_current_round
-- gate: expect assert_forecast_year_has_current_round flag 1
-- konsol#348 S6-Q1 (b): a forecast (scenario, fiscal year) with approved rounds and no Current Forecast
-- declaration is named (WARN): its forecast reads are empty until one is declared. Scenario ZZ_FC_2026 is
-- declared 'forecast'; FY2026 has two approved rounds ZZ-FC-R1 and ZZ-FC-R2 in budget_cycles and NO row in
-- epm_staging.current_forecasts: 1 result, listing both rounds. FY2027 of the same scenario is declared
-- (ZZ-FC-R3): not named. Scenario ZZ_PLAN_2026 is a budget with an approved Cycle and no declaration: a
-- budget has no rounds (Approved Budget is its declaration), not named.
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
  ('ZZ-FC-R3', 'ZZ_FC_2026', 2027, 'ZZRS', '2027-03-31', 9),
  ('ZZ-CY-A', 'ZZ_PLAN_2026', 2026, 'ZZRS', DEFAULT, 0);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle, as_of_date)
VALUES
  ('ZZ_FC_2026', 2027, 'ZZ-FC-R3', '2027-03-31');
