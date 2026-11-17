-- gate: build gold_forecast_accuracy assert_forecast_accuracy_hand_table assert_forecast_accuracy_grain_unique assert_forecast_accuracy_pct_null_on_zero_actual
-- gate: expect gold_forecast_accuracy built
-- gate: expect assert_forecast_accuracy_hand_table pass
-- gate: expect assert_forecast_accuracy_grain_unique pass
-- gate: expect assert_forecast_accuracy_pct_null_on_zero_actual pass
-- konsol#348 S6 WC2 (FC-4-2, S6-Q8 a): forecast accuracy, worked by hand. FY2026 P1-P12 declared
-- (Regular, monthly); P1-P5 Closed, P6 Locked, P7-P12 Open (the effective status konsol publishes).
-- Forecast scenario ZZ_FC_ACC has two approved rounds: ZZ-ACC-R1 as of 2026-03-31 (P3), horizon 9;
-- ZZ-ACC-R2 as of 2026-05-31 (P5), horizon 2. Budget scenario ZZ_PLAN_ACC's Cycle is not a round: no row.
-- Forecast fact: R1 ZZE1 ZZ4000 P3 -99 (the as-of period: not after it), P4 base -40 + challenge -2,
-- P5 -50, P6 -60, P7 -70 (Open); R1 ZZE1 ZZ5000 P5 20 (no actual); R2 ZZE1 ZZ4000 P6 -66, P7 -77 (Open),
-- P8 -88 (beyond R2's horizon, and Open).
-- Actuals (scenario TB, data_source gl): ZZE1 ZZ4000 P4 -45, P5 -50, P6 -55, P7 -71; ZZE1 ZZ6000 P4 10
-- (no round forecasts the account: a forecast of 0 for R1; before R2's as-of: not R2's); ZZE2 ZZ4000 P4
-- -5 (no round forecasts ZZE2: absent). The budget branch's row (data_source budget) is not an actual.
-- Expected, in assert_forecast_accuracy_hand_table: R1 P4 ZZ4000 (lag 1) -42 vs -45, P4 ZZ6000 0 vs 10,
-- P5 ZZ4000 (lag 2) -50 vs -50, P5 ZZ5000 20 vs 0 (error % NULL), P6 ZZ4000 (lag 3) -60 vs -55; R2 P6
-- ZZ4000 (lag 1) -66 vs -55. Red before WC2: the model does not exist.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live tables may have
-- been built at other dims, so they are added by ALTER first.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_ACT', 'ZZ actual', 'actual', 1),
  ('ZZ_FC_ACC', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_ACC', 'ZZ plan', 'budget', 1);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Closed'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Closed'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Closed'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Closed'),
  (2026, 5, 'FY2026-P05', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Closed'),
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Locked'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open'),
  (2026, 8, 'FY2026-P08', 'Aug 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q3', 'Open'),
  (2026, 9, 'FY2026-P09', 'Sep 2026', 'Regular', '2026-09-01', '2026-09-30', 'Q3', 'Open'),
  (2026, 10, 'FY2026-P10', 'Oct 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q4', 'Open'),
  (2026, 11, 'FY2026-P11', 'Nov 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-ACC-R1', 'ZZ_FC_ACC', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-ACC-R2', 'ZZ_FC_ACC', 2026, 'ZZRS', '2026-05-31', 2),
  ('ZZ-ACC-B', 'ZZ_PLAN_ACC', 2026, 'ZZRS', DEFAULT, 0);
ALTER TABLE epm_gold.gold_scenario_trial_balance ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_scenario_trial_balance ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_scenario_trial_balance
  (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   dim_cost_center, dim_department, currency, amount, data_source)
VALUES
  ('ZZ_ACT', 'ZZE1', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', '', '', 'USD', -45, 'gl'),
  ('ZZ_ACT', 'ZZE1', 2026, 5, 'ZZ4000', 'ZZ revenue', 'Revenue', '', '', 'USD', -50, 'gl'),
  ('ZZ_ACT', 'ZZE1', 2026, 6, 'ZZ4000', 'ZZ revenue', 'Revenue', '', '', 'USD', -55, 'gl'),
  ('ZZ_ACT', 'ZZE1', 2026, 7, 'ZZ4000', 'ZZ revenue', 'Revenue', '', '', 'USD', -71, 'gl'),
  ('ZZ_ACT', 'ZZE1', 2026, 4, 'ZZ6000', 'ZZ other cost', 'Expense', '', '', 'USD', 10, 'gl'),
  ('ZZ_ACT', 'ZZE2', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', '', '', 'USD', -5, 'gl'),
  ('ZZ_PLAN_ACC', 'ZZE1', 2026, 4, 'ZZ4000', '', '', '', '', 'USD', -1000, 'budget');
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department,
   layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 3, 'ZZ4000', '', '', 'base', 'USD', -99, 'manual', 'Manual (as-entered)', 1, -99, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'base', 'USD', -40, 'manual', 'Manual (as-entered)', 1, -40, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'challenge', 'USD', -2, 'manual', 'Manual (as-entered)', 1, -2, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 5, 'ZZ4000', '', '', 'base', 'USD', -50, 'manual', 'Manual (as-entered)', 1, -50, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'USD', -60, 'manual', 'Manual (as-entered)', 1, -60, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'USD', -70, 'manual', 'Manual (as-entered)', 1, -70, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 5, 'ZZ5000', '', '', 'base', 'USD', 20, 'manual', 'Manual (as-entered)', 1, 20, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R2', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'USD', -66, 'manual', 'Manual (as-entered)', 1, -66, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R2', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'USD', -77, 'manual', 'Manual (as-entered)', 1, -77, ''),
  ('ZZ_FC_ACC', 'ZZ-ACC-R2', 'ZZE1', 2026, 8, 'ZZ4000', '', '', 'base', 'USD', -88, 'manual', 'Manual (as-entered)', 1, -88, ''),
  ('ZZ_PLAN_ACC', 'ZZ-ACC-B', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'base', 'USD', -1000, 'manual', 'Manual (as-entered)', 1, -1000, '');
