-- gate: build +gold_scenario_trial_balance assert_scenario_tb_currency_declared
-- gate: expect assert_scenario_tb_currency_declared flag 1
-- konsol#348 S3 B6 (QB3 a): a GL row whose entity declares no currency is named. Same rows as
-- assert_scenario_tb_currency_declared.sql, but epm_staging.entities holds no row for ZZE1, so
-- silver_entity_currencies has no currency for it and the GL branch's LEFT JOIN fills '' (join_use_nulls=0).
-- Exactly 1 result: (ZZ_ACT, ZZE1, gl). The budget row carries 'USD' from its line and is not named.
-- A model that dropped the unmatched entity instead would lose its trial balance from the scenario fact;
-- this test, with assert_every_tb_entity_has_a_currency, keeps the row and names it.
--
-- The lineage of gold_scenario_trial_balance reads these tables too, empty here, so they are named to exist
-- (empty): epm_staging.entities, epm_gold.entity_fiscal_calendars, epm_gold.spread_profiles,
-- epm_staging.dimension_mappings.
--
-- The live submission tables and chart may predate their partner, basis and retained-earnings columns, and
-- the live annual table may predate `cycle` (B3w): add them to the scratch clones first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ1000', 1000, 0, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', ''),
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1000, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZE1', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement');
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_ACT', 'ZZ actual', 'actual', 1),
  ('ZZ_B26', 'ZZ budget 2026', 'budget', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_B26', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1200, 'USD', 'Period movement', '', '');
