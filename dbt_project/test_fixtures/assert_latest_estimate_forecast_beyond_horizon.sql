-- konsol#348 S6 pair A review M1: every forecast row of a round is inside its horizon, or at or before
-- its as-of (replaced by the actual, the declared rule): the test passes. FY2026 P1-P12 declared;
-- forecast scenario ZZ_FC_LE: ZZ-LE-R1 as of 2026-03-31 (P3), horizon 3 (P4-P6), rows P3 -99 (replaced),
-- P4 -40, P6 -60 (the horizon's last period), and P9 0 (beyond the horizon, but a zero row drops
-- nothing: not named); ZZ-LE-R2 as of 2026-06-30 (P6), horizon 6 (P7-P12), rows P7 base -71 and challenge
-- -1, P12 -120. Budget scenario ZZ_PLAN_LE's Cycle has a P12 row and no round: not named.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live tables may have
-- been built at other dims, so they are added by ALTER first.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_LE', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_LE', 'ZZ plan', 'budget', 1);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Open'),
  (2026, 5, 'FY2026-P05', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Open'),
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open'),
  (2026, 8, 'FY2026-P08', 'Aug 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q3', 'Open'),
  (2026, 9, 'FY2026-P09', 'Sep 2026', 'Regular', '2026-09-01', '2026-09-30', 'Q3', 'Open'),
  (2026, 10, 'FY2026-P10', 'Oct 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q4', 'Open'),
  (2026, 11, 'FY2026-P11', 'Nov 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-LE-R1', 'ZZ_FC_LE', 2026, 'ZZRS', '2026-03-31', 3),
  ('ZZ-LE-R2', 'ZZ_FC_LE', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-LE-B', 'ZZ_PLAN_LE', 2026, 'ZZRS', DEFAULT, 0);
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department,
   layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R1', 'ZZE1', 2026, 3, 'ZZ4000', '', '', 'base', 'USD', -99, 'manual', 'Manual (as-entered)', 1, -99, ''),
  ('ZZ_FC_LE', 'ZZ-LE-R1', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'base', 'USD', -40, 'manual', 'Manual (as-entered)', 1, -40, ''),
  ('ZZ_FC_LE', 'ZZ-LE-R1', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'USD', -60, 'manual', 'Manual (as-entered)', 1, -60, ''),
  ('ZZ_FC_LE', 'ZZ-LE-R1', 'ZZE1', 2026, 9, 'ZZ4000', '', '', 'base', 'USD', 0, 'manual', 'Manual (as-entered)', 1, 0, ''),
  ('ZZ_FC_LE', 'ZZ-LE-R2', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'USD', -71, 'manual', 'Manual (as-entered)', 1, -71, ''),
  ('ZZ_FC_LE', 'ZZ-LE-R2', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'challenge', 'USD', -1, 'manual', 'Manual (as-entered)', 1, -1, ''),
  ('ZZ_FC_LE', 'ZZ-LE-R2', 'ZZE1', 2026, 12, 'ZZ4000', '', '', 'base', 'USD', -120, 'manual', 'Manual (as-entered)', 1, -120, ''),
  ('ZZ_PLAN_LE', 'ZZ-LE-B', 'ZZE1', 2026, 12, 'ZZ4000', '', '', 'base', 'USD', -33, 'manual', 'Manual (as-entered)', 1, -33, '');
