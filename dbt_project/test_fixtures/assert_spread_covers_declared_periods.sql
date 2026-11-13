-- gate: build gold_spread_budget assert_spread_covers_declared_periods
-- gate: expect assert_spread_covers_declared_periods pass
-- A 13-period fiscal year (13 declared Regular periods, plus a Closing period 14) and a 13-weight profile: the annual
-- input spreads into every declared Regular period, so the test must PASS.
-- epm_gold.budget_monthly_input is read too, empty here, so it is named to exist (empty).
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1300, 'ZZ_W', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_W', 'ZZ weights', 1, 1),
  ('ZZ_W', 'ZZ weights', 2, 1),
  ('ZZ_W', 'ZZ weights', 3, 1),
  ('ZZ_W', 'ZZ weights', 4, 1),
  ('ZZ_W', 'ZZ weights', 5, 1),
  ('ZZ_W', 'ZZ weights', 6, 1),
  ('ZZ_W', 'ZZ weights', 7, 1),
  ('ZZ_W', 'ZZ weights', 8, 1),
  ('ZZ_W', 'ZZ weights', 9, 1),
  ('ZZ_W', 'ZZ weights', 10, 1),
  ('ZZ_W', 'ZZ weights', 11, 1),
  ('ZZ_W', 'ZZ weights', 12, 1),
  ('ZZ_W', 'ZZ weights', 13, 1);
INSERT INTO epm_staging.fiscal_periods (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status) VALUES
  (2026, 1, 'FY2026-P01', 'P1 2026', 'Regular', toDate('2026-01-01') + 0, toDate('2026-01-01') + 27, 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'P2 2026', 'Regular', toDate('2026-01-01') + 28, toDate('2026-01-01') + 55, 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'P3 2026', 'Regular', toDate('2026-01-01') + 56, toDate('2026-01-01') + 83, 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'P4 2026', 'Regular', toDate('2026-01-01') + 84, toDate('2026-01-01') + 111, 'Q1', 'Open'),
  (2026, 5, 'FY2026-P05', 'P5 2026', 'Regular', toDate('2026-01-01') + 112, toDate('2026-01-01') + 139, 'Q2', 'Open'),
  (2026, 6, 'FY2026-P06', 'P6 2026', 'Regular', toDate('2026-01-01') + 140, toDate('2026-01-01') + 167, 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'P7 2026', 'Regular', toDate('2026-01-01') + 168, toDate('2026-01-01') + 195, 'Q2', 'Open'),
  (2026, 8, 'FY2026-P08', 'P8 2026', 'Regular', toDate('2026-01-01') + 196, toDate('2026-01-01') + 223, 'Q2', 'Open'),
  (2026, 9, 'FY2026-P09', 'P9 2026', 'Regular', toDate('2026-01-01') + 224, toDate('2026-01-01') + 251, 'Q3', 'Open'),
  (2026, 10, 'FY2026-P10', 'P10 2026', 'Regular', toDate('2026-01-01') + 252, toDate('2026-01-01') + 279, 'Q3', 'Open'),
  (2026, 11, 'FY2026-P11', 'P11 2026', 'Regular', toDate('2026-01-01') + 280, toDate('2026-01-01') + 307, 'Q3', 'Open'),
  (2026, 12, 'FY2026-P12', 'P12 2026', 'Regular', toDate('2026-01-01') + 308, toDate('2026-01-01') + 335, 'Q3', 'Open'),
  (2026, 13, 'FY2026-P13', 'P13 2026', 'Regular', toDate('2026-01-01') + 336, toDate('2026-01-01') + 363, 'Q4', 'Open'),
  (2026, 14, 'FY2026-P14', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
