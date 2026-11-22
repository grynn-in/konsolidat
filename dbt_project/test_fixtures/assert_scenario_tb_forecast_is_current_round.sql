-- gate: build +gold_scenario_trial_balance assert_scenario_tb_forecast_is_current_round assert_scenario_tb_currency_declared
-- gate: expect gold_scenario_trial_balance built
-- gate: expect assert_scenario_tb_forecast_is_current_round pass
-- gate: expect assert_scenario_tb_currency_declared pass
-- konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026: the hand case of the S6 plan (§7, "rounds
-- doubling in the gap"). Forecast scenario ZZ_FC_2026, FY2026 P1, account ZZ4000, entity ZZE1 (USD):
-- round ZZ-FC-R1 (as of 2026-03-31) credits 100, round ZZ-FC-R2 (as of 2026-06-30) credits 110, both
-- approved (both in budget_cycles). The Current Forecast declares R2. gold_scenario_trial_balance must
-- show -110 for the key (signed, debit positive): the declared round alone. On the pre-WA4 model it
-- showed -210 (the two rounds summed), which this fixture turned red (1 result: declared -110, TB -210).
-- Budget scenario ZZ_PLAN_2026 (one Cycle, 100) passes through the branch unchanged and is not checked.
-- assert_scenario_tb_currency_declared runs too: the branch still carries the fact's currency.
-- The lineage of gold_scenario_trial_balance reads these tables too, empty here, so they are named to exist
-- (empty): epm_gold.spread_profiles, epm_staging.dimension_mappings,
-- epm_staging.main_accounts, epm_raw.trial_balance_submissions, epm_raw.trial_balance_submission_control.
-- epm_staging.fiscal_periods (FY2026 Regular P1-P12) and epm_staging.entities (ZZE1, USD) are NOT empty:
-- the build selects +gold_scenario_trial_balance, so the error-severity tests on its lineage run first.
-- With both tables empty, assert_budget_period_declared, assert_budget_currency_is_entity_currency and
-- assert_forecast_as_of_in_declared_period (the rounds' as-of dates fall in P3 and P6) flag the rows,
-- dbt SKIPS gold_scenario_trial_balance, and the expected `built` cannot hold.
-- The live submission tables, chart and annual table may predate later columns: add them to the scratch
-- clones first, as assert_scenario_tb_currency_declared.sql does.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_ACT', 'ZZ actual', 'actual', 1),
  ('ZZ_FC_2026', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_2026', 'ZZ plan', 'budget', 1);
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-FC-R1', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-FC-R2', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-CY-A', 'ZZ_PLAN_2026', 2026, 'ZZRS', DEFAULT, 0);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 110, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-A', 'ZZ-CY-A', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', '');
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
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZE1', 'ZZ Entity 1', '', 0, 'Active', 'USD', 'US', '');
