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
-- (empty): epm_gold.entity_fiscal_calendars, epm_gold.spread_profiles, epm_staging.dimension_mappings,
-- epm_staging.entities, epm_staging.main_accounts, epm_staging.fiscal_periods,
-- epm_raw.trial_balance_submissions, epm_raw.trial_balance_submission_control.
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
  (scenario_id, fiscal_year, cycle, as_of_date)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2', '2026-06-30');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 110, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-A', 'ZZ-CY-A', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', '');
