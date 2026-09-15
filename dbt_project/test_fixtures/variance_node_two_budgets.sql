-- konsolidat#206: gold_variance_at_hierarchy_node keeps each budget scenario apart. gold_variance_analysis has
-- one set of rows per active budget-type scenario (budget_scenario_id), so a node model that groups without it
-- counts the actuals once per budget scenario and adds the budgets together.
-- `+gold_variance_at_hierarchy_node assert_variance_node_single_budget` must BUILD and PASS on these rows.
--
-- Copied from variance_budget_scenario.sql, with a second active budget scenario and a cost centre:
-- Entity ZZE1 (USD), FY2026 P1.
--   Trial balance upload (period movement): ZZ1000 cash Dr 1000 | ZZ4000 revenue Cr 1000. A submitted trial
--   balance carries no dimensions (silver_gl_entries gives its rows dim_empty_strings()), so it never reaches
--   the hierarchy node model; the cost-centred actuals come from one balanced GL voucher instead:
--   GL voucher ZZV1 (2026-01-15), cost centre ZZCC1: ZZ1000 Dr 1000 | ZZ4000 Cr 1000.
-- Declared scenarios: ACTUAL (actual), ZZ_PLAN_2026 (budget, active), ZZ_PLAN_2026_B (budget, active),
--   ZZ_FCST_2026 (forecast, active).
-- Budget Sheet (epm_gold.budget_monthly_input), base layer, FY2026 P1 on ZZ4000, cost centre ZZCC1:
--   ZZ_PLAN_2026 -1200 | ZZ_PLAN_2026_B -1100 | ZZ_FCST_2026 -900
-- Reporting hierarchy ZZH_CC over dim_cost_center: group ZZCCG with leaf ZZCC1.
-- For each budget scenario the ZZCC1 leaf must carry ZZ1000 actual 1000 and ZZ4000 actual -1000 once, never 2000.
--
-- The lineage of gold_scenario_trial_balance reads these tables too, empty here, so they are named to exist
-- (empty): epm_raw.budget_register_entries, epm_raw.fiscal_calendar_years,
-- epm_gold.budget_annual_input, epm_gold.entity_fiscal_calendars, epm_gold.spread_profiles,
-- epm_staging.dimension_mappings.
--
-- The live submission tables and chart may predate their partner, basis and retained-earnings columns: add them first.
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
INSERT INTO epm_raw.general_journal_entry_bi_entities
  (_airbyte_raw_id, _airbyte_extracted_at, SourceKey, DocumentDate, PostingLayer, JournalNumber, AccountingDate, DocumentNumber, JournalCategory, SubledgerVoucher, FiscalCalendarYear, FiscalCalendarPeriod, SubledgerVoucherDataAreaId)
VALUES
  ('zz-gje-1', '2026-02-01 00:00:00', 990001, '2026-01-15', 'Current', 'ZZJ1', '2026-01-15', 'ZZD1', 'Daily', 'ZZV1', 2026, 1, 'ZZE1');
INSERT INTO epm_raw.general_journal_account_entry_bi_entities
  (_airbyte_raw_id, _airbyte_extracted_at, Text, SourceKey, PostingType, LedgerAccount, AccountingDate, GeneralJournalEntry, ReportingCurrencyAmount, TransactionCurrencyCode, AccountingCurrencyAmount, LedgerDimensionValuesJson, TransactionCurrencyAmount)
VALUES
  ('zz-gae-1', '2026-02-01 00:00:00', 'ZZ cash', 990011, 'LedgerJournal', 'ZZ1000-ZZCC1', '2026-01-15', 990001, 1000, 'USD', 1000, '[{"MAINACCOUNT":"ZZ1000","COSTCENTER":"ZZCC1"}]', 1000),
  ('zz-gae-2', '2026-02-01 00:00:00', 'ZZ revenue', 990012, 'LedgerJournal', 'ZZ4000-ZZCC1', '2026-01-15', 990001, -1000, 'USD', -1000, '[{"MAINACCOUNT":"ZZ4000","COSTCENTER":"ZZCC1"}]', -1000);
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ACTUAL', 'Actual', 'actual', 1),
  ('ZZ_PLAN_2026', 'ZZ plan 2026', 'budget', 1),
  ('ZZ_PLAN_2026_B', 'ZZ plan 2026 B', 'budget', 1),
  ('ZZ_FCST_2026', 'ZZ forecast 2026', 'forecast', 1);
INSERT INTO epm_gold.budget_monthly_input
  (scenario_id, data_area_id, fiscal_year, main_account, dim_cost_center, dim_department, fiscal_period, amount, layer)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'ZZCC1', '', 1, -1200, 'base'),
  ('ZZ_PLAN_2026_B', 'ZZE1', 2026, 'ZZ4000', 'ZZCC1', '', 1, -1100, 'base'),
  ('ZZ_FCST_2026', 'ZZE1', 2026, 'ZZ4000', 'ZZCC1', '', 1, -900, 'base');
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status)
VALUES
  ('ZZH_CC', 'dim_cost_center', 'ZZCCG', 'ZZ cost centre group', '', 1, 1, 'ZZCCG', '', '', 1, 'Published'),
  ('ZZH_CC', 'dim_cost_center', 'ZZCC1', 'ZZ cost centre 1', 'ZZCCG', 0, 2, 'ZZCCG/ZZCC1', '', '', 1, 'Published');
