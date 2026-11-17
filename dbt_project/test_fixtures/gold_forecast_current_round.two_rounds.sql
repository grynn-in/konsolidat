-- gate: build gold_forecast_current_round assert_forecast_current_round_unique assert_forecast_year_has_current_round
-- gate: expect gold_forecast_current_round built
-- gate: expect assert_forecast_current_round_unique pass
-- gate: expect assert_forecast_year_has_current_round pass
-- konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026: two approved rounds of one forecast
-- (scenario, fiscal year) live side by side, and the Current Forecast declaration picks ONE.
-- Scenario ZZ_FC_2026 is declared 'forecast'; FY2026 has rounds ZZ-FC-R1 (as of 2026-03-31, horizon 9)
-- and ZZ-FC-R2 (as of 2026-06-30, horizon 6) in budget_cycles; current_forecasts declares R2. The model
-- builds with one row for the pair (R2, as_of 2026-06-30, horizon 6, rate set ZZRS); the unique test
-- passes; the declared pair is not warned. A declaration naming a Cycle that is NOT in budget_cycles
-- (ZZ_FC_2026 FY2027 -> ZZ-FC-GONE, a cancelled round whose declaration outlived it) yields no row and
-- is therefore the WARN's business when that year has approved rounds; here FY2027 has none, so the
-- WARN stays silent. That the row is R2's figures is proved on the readers:
-- assert_scenario_tb_forecast_is_current_round (WA4, 110 not 210).
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast', 'forecast', 1);
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-FC-R1', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-FC-R2', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-06-30', 6);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2'),
  ('ZZ_FC_2026', 2027, 'ZZ-FC-GONE');
