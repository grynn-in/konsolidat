-- gate: expect assert_latest_estimate_forecast_beyond_horizon flag 1
-- konsolidat#376: "beyond the horizon" is beyond the ROUND's horizon, the longest horizon_periods among
-- the approved Cycles sharing its (scenario_id, as_of_date), the horizon gold_latest_estimate cuts at and
-- gold_forecast_accuracy measures to. The horizon hand fixture's rounds and forecast rows
-- (assert_forecast_accuracy_horizon_hand_table.sql): round A as of 2026-09-30 (FY2026 P9) has Cycle
-- ZZ-HZN-A26 (FY2026, horizon 12) and ZZ-HZN-A27 (FY2027, horizon 3); round B as of 2026-12-31 (FY2026
-- P12) has ZZ-HZN-B27 (FY2027, horizon 2). Named: B27's FY2027 P3 row (-33, lag 3 > 2): 1 result.
-- Not named: A27's FY2027 P1-P4 (lags 4-7, inside the round's 12; red before the fix, when the FY2027
-- Cycle's own 3 named all four and the test asked the user to extend a horizon the round already
-- covers), A26's P9 (at the as-of: the actual replaces it) and P10-P12.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_HZN', 'ZZ forecast', 'forecast', 1);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Closed'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Closed'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Closed'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Closed'),
  (2026, 5, 'FY2026-P05', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Closed'),
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Closed'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Closed'),
  (2026, 8, 'FY2026-P08', 'Aug 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q3', 'Closed'),
  (2026, 9, 'FY2026-P09', 'Sep 2026', 'Regular', '2026-09-01', '2026-09-30', 'Q3', 'Closed'),
  (2026, 10, 'FY2026-P10', 'Oct 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q4', 'Closed'),
  (2026, 11, 'FY2026-P11', 'Nov 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q4', 'Closed'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Closed'),
  (2027, 1, 'FY2027-P01', 'Jan 2027', 'Regular', '2027-01-01', '2027-01-31', 'Q1', 'Closed'),
  (2027, 2, 'FY2027-P02', 'Feb 2027', 'Regular', '2027-02-01', '2027-02-28', 'Q1', 'Closed'),
  (2027, 3, 'FY2027-P03', 'Mar 2027', 'Regular', '2027-03-01', '2027-03-31', 'Q1', 'Closed'),
  (2027, 4, 'FY2027-P04', 'Apr 2027', 'Regular', '2027-04-01', '2027-04-30', 'Q2', 'Open'),
  (2027, 5, 'FY2027-P05', 'May 2027', 'Regular', '2027-05-01', '2027-05-31', 'Q2', 'Open'),
  (2027, 6, 'FY2027-P06', 'Jun 2027', 'Regular', '2027-06-01', '2027-06-30', 'Q2', 'Open'),
  (2027, 7, 'FY2027-P07', 'Jul 2027', 'Regular', '2027-07-01', '2027-07-31', 'Q3', 'Open'),
  (2027, 8, 'FY2027-P08', 'Aug 2027', 'Regular', '2027-08-01', '2027-08-31', 'Q3', 'Open'),
  (2027, 9, 'FY2027-P09', 'Sep 2027', 'Regular', '2027-09-01', '2027-09-30', 'Q3', 'Open'),
  (2027, 10, 'FY2027-P10', 'Oct 2027', 'Regular', '2027-10-01', '2027-10-31', 'Q4', 'Open'),
  (2027, 11, 'FY2027-P11', 'Nov 2027', 'Regular', '2027-11-01', '2027-11-30', 'Q4', 'Open'),
  (2027, 12, 'FY2027-P12', 'Dec 2027', 'Regular', '2027-12-01', '2027-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-HZN-A26', 'ZZ_FC_HZN', 2026, 'ZZRS', '2026-09-30', 12),
  ('ZZ-HZN-A27', 'ZZ_FC_HZN', 2027, 'ZZRS', '2026-09-30', 3),
  ('ZZ-HZN-B27', 'ZZ_FC_HZN', 2027, 'ZZRS', '2026-12-31', 2);
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department,
   layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 9, 'ZZ4000', '', '', 'base', 'USD', -90, 'manual', 'Manual (as-entered)', 1, -90, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 10, 'ZZ4000', '', '', 'base', 'USD', -100, 'manual', 'Manual (as-entered)', 1, -100, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 11, 'ZZ4000', '', '', 'base', 'USD', -110, 'manual', 'Manual (as-entered)', 1, -110, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 12, 'ZZ4000', '', '', 'base', 'USD', -120, 'manual', 'Manual (as-entered)', 1, -120, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 1, 'ZZ4000', '', '', 'base', 'USD', -10, 'manual', 'Manual (as-entered)', 1, -10, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 2, 'ZZ4000', '', '', 'base', 'USD', -20, 'manual', 'Manual (as-entered)', 1, -20, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 3, 'ZZ4000', '', '', 'base', 'USD', -30, 'manual', 'Manual (as-entered)', 1, -30, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 4, 'ZZ4000', '', '', 'base', 'USD', -40, 'manual', 'Manual (as-entered)', 1, -40, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', 'ZZH1', 2027, 1, 'ZZ4000', '', '', 'base', 'USD', -12, 'manual', 'Manual (as-entered)', 1, -12, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', 'ZZH1', 2027, 2, 'ZZ4000', '', '', 'base', 'USD', -18, 'manual', 'Manual (as-entered)', 1, -18, ''),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', 'ZZH1', 2027, 3, 'ZZ4000', '', '', 'base', 'USD', -33, 'manual', 'Manual (as-entered)', 1, -33, '');
