-- gate: build +gold_variance_analysis +gold_variance_ytd +gold_variance_quarterly assert_variance_single_currency assert_variance_ytd_single_currency assert_variance_quarterly_single_currency --exclude assert_budget_currency_is_entity_currency
-- gate: expect assert_variance_single_currency flag 1
-- gate: expect assert_variance_ytd_single_currency flag 1
-- gate: expect assert_variance_quarterly_single_currency flag 1
-- konsol#348 S3 B8 (QB3 a): the currency joins the variance grain, so a budget row never nets against an
-- actual in another currency. Entity ZZE1 keeps its books in USD; its FY2026 P1 actuals are ZZ1000 cash
-- Dr 1000 | ZZ4000 revenue Cr 1000 (USD, from the entity). Budget scenario ZZ_PLAN_2026 budgets ZZ4000 P1
-- at -1200 in EUR. gold_variance_analysis must carry two rows for (ZZE1, 2026, 1, ZZ4000, ZZ_PLAN_2026):
-- USD actual -1000 with no budget, and EUR budget -1200 with actual 0; never one row netting -1000
-- against -1200. assert_variance_single_currency must FLAG exactly that grain (1 row); ZZ1000 has one
-- currency and is not named. gold_variance_ytd (B9) runs the same totals through P1 and
-- assert_variance_ytd_single_currency must FLAG the same grain (1 row); gold_variance_quarterly (B10) sums
-- P1 into Q1 and assert_variance_quarterly_single_currency must FLAG the same grain (1 row).
--
-- Red on the S3-B7 model: gold_variance_analysis has no `currency` column, so the test errors (missing
-- column) and nothing can flag; green once the grain carries it.
--
-- assert_budget_currency_is_entity_currency (B7, error) refuses exactly this EUR line upstream, and in a
-- build its failure would skip every model below gold_spread_budget, this one included. It is excluded
-- here on purpose: this fixture proves the backstop at the variance grain can fail, which is only
-- reachable past the upstream guard.
--
-- The lineage of gold_scenario_trial_balance reads these tables too, empty here, so they are named to exist
-- (empty): epm_raw.budget_register_entries, epm_raw.fiscal_calendar_years,
-- epm_raw.general_journal_account_entry_bi_entities, epm_raw.general_journal_entry_bi_entities,
-- epm_gold.budget_annual_input, epm_gold.entity_fiscal_calendars, epm_gold.spread_profiles,
-- epm_staging.dimension_mappings.
--
-- The live submission tables and chart may predate their partner, basis and retained-earnings columns, and
-- the live annual table may predate `cycle` (B3w): add them to the scratch clones first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZE1', 'ZZ entity 1', '', 0, 'Published', 'USD', 'US', '');
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
  ('ACTUAL', 'Actual', 'actual', 1),
  ('ZZ_PLAN_2026', 'ZZ plan 2026', 'budget', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1200, 'EUR', 'Period movement', '', '');
