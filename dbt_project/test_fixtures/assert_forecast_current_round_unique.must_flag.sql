-- gate: build gold_forecast_current_round assert_forecast_current_round_unique
-- gate: expect assert_forecast_current_round_unique flag 1
-- konsol#348 S6-Q1 (b): a forecast (scenario, fiscal year) has one current round. Scenario ZZ_FC_2026 is
-- declared 'forecast'; FY2026 has two approved rounds ZZ-FC-R1 (as of 2026-03-31) and ZZ-FC-R2 (as of
-- 2026-06-30) in budget_cycles, and epm_staging.current_forecasts holds a declaration for EACH of them
-- (two rows for one pair, which konsol's one-live-declaration rule refuses; here it is sync drift or a
-- hand-written row). gold_forecast_current_round carries both rows and the test names the pair: 1 result.
-- FY2027 of the same scenario has one round, declared once: not named.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast', 'forecast', 1);
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-FC-R1', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-FC-R2', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-FC-R3', 'ZZ_FC_2026', 2027, 'ZZRS', '2027-03-31', 9);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R1'),
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2'),
  ('ZZ_FC_2026', 2027, 'ZZ-FC-R3');
