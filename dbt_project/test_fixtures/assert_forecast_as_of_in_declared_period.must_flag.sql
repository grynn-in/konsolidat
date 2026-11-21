-- gate: expect assert_forecast_as_of_in_declared_period flag 1
-- konsol#348 S6 WA3 (BUD-10-1): a forecast round whose as-of date is in no declared Regular period is
-- named. The calendar declares FY2026 P1-P12 (Regular) plus an Opening P0 and a Closing P13. Scenario
-- ZZ_FC is 'forecast'. Round ZZ-FC-IN (as of 2026-06-30) is inside P6: not named. Round ZZ-FC-OUT (as of
-- 2027-02-15) is in a year the calendar does not declare: 1 result. Budget Cycle ZZ-CY-B of the budget
-- scenario ZZ_PLAN has no round (as_of_date is the 1900-01-01 default): not read.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN', 'ZZ plan', 'budget', 1);
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
  ('ZZ-FC-IN', 'ZZ_FC', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-FC-OUT', 'ZZ_FC', 2027, 'ZZRS', '2027-02-15', 10),
  ('ZZ-CY-B', 'ZZ_PLAN', 2026, 'ZZRS', DEFAULT, 0);
