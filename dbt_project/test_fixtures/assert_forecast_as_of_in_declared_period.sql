-- gate: expect assert_forecast_as_of_in_declared_period pass
-- konsol#348 S6 WA3 (BUD-10-1): every approved forecast round's as-of date sits inside a declared Regular
-- period: must PASS. The calendar declares FY2026 P1-P12 plus Opening P0 and Closing P13 (P0 and P13 share
-- their day with P1 and P12, so a date on either day is held by the Regular period). ZZ-FC-Q1 is as of
-- 2026-03-31 (P3), ZZ-FC-Q2 as of 2026-06-30 (P6), ZZ-FC-YE as of 2026-12-31 (P12, the Closing day too).
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC', 'ZZ forecast', 'forecast', 1);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 0, 'FY2026-P00', 'Opening 2026', 'Opening', '2026-01-01', '2026-01-01', 'Q1', 'Open'),
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
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'Closing 2026', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-FC-Q1', 'ZZ_FC', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-FC-Q2', 'ZZ_FC', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-FC-YE', 'ZZ_FC', 2026, 'ZZRS', '2026-12-31', 12);
