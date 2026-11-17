-- gate: build gold_forecast_current_round gold_latest_estimate_current assert_latest_estimate_current_ties_to_estimate
-- gate: expect gold_latest_estimate_current built
-- gate: expect assert_latest_estimate_current_ties_to_estimate pass
-- konsol#348 S6 pair A review M2 (S6-Q1 b, S6-Q2 a): the Excel latest-estimate read's view holds the
-- declared round alone. Forecast scenario ZZ_FC_LE, FY2026: rounds ZZ-LE-R1 (as of P3) and ZZ-LE-R2 (as
-- of P6) are both approved and both in gold_latest_estimate (seeded; the table keeps every round); the
-- Current Forecast declares R2. gold_latest_estimate_current, built over it, must hold exactly R2's three
-- rows (-30 actual P3, -60 actual P6, -72 forecast P7: -162) and no R1 row: the ties test passes.
-- Budget scenario ZZ_PLAN_LE has a Cycle and no round: nothing of it is in either relation.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_LE', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_LE', 'ZZ plan', 'budget', 1);
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-LE-R1', 'ZZ_FC_LE', 2026, 'ZZRS', '2026-03-31', 3),
  ('ZZ-LE-R2', 'ZZ_FC_LE', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-LE-B', 'ZZ_PLAN_LE', 2026, 'ZZRS', DEFAULT, 0);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle)
VALUES
  ('ZZ_FC_LE', 2026, 'ZZ-LE-R2');
INSERT INTO epm_gold.gold_latest_estimate
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account, currency,
   period_amount, source)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', -40, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 6, 'ZZ4000', 'USD', -60, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 7, 'ZZ4000', 'USD', -72, 'forecast');
