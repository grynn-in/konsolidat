-- gate: expect assert_latest_estimate_actuals_present flag 1
-- konsol#348 S6 WA8 (FC-2-1): a missing actual is reported, never filled. FY2026 P1-P3 declared; forecast
-- round ZZ-LE-R as of 2026-02-28 (P2), horizon 1, forecasts ZZE1 and ZZE2 (P3 rows in the fact).
-- gold_latest_estimate (seeded, test mode) holds actuals for ZZE1 at P1 and P2 and for ZZE2 at P1 only:
-- ZZE2 P2 is named. 1 result.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live tables may have
-- been built at other dims, so they are added by ALTER first.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_LE', 'ZZ forecast', 'forecast', 1);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open');
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-LE-R', 'ZZ_FC_LE', 2026, 'ZZRS', '2026-02-28', 1);
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department,
   layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R', 'ZZE1', 2026, 3, 'ZZ4000', '', '', 'base', 'USD', -30, 'manual', 'Manual (as-entered)', 1, -30, ''),
  ('ZZ_FC_LE', 'ZZ-LE-R', 'ZZE2', 2026, 3, 'ZZ4000', '', '', 'base', 'USD', -3, 'manual', 'Manual (as-entered)', 1, -3, '');
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_latest_estimate
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account,
   dim_cost_center, dim_department, currency, period_amount, source)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R', '2026-02-28', 'ZZE1', 2026, 1, 'ZZ4000', '', '', 'USD', -10, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R', '2026-02-28', 'ZZE1', 2026, 2, 'ZZ4000', '', '', 'USD', -20, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R', '2026-02-28', 'ZZE1', 2026, 3, 'ZZ4000', '', '', 'USD', -30, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R', '2026-02-28', 'ZZE2', 2026, 1, 'ZZ4000', '', '', 'USD', -1, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R', '2026-02-28', 'ZZE2', 2026, 3, 'ZZ4000', '', '', 'USD', -3, 'forecast');
