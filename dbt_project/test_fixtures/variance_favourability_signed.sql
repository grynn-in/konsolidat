-- gate: build +gold_variance_analysis assert_variance_favourability_follows_sign
-- gate: expect assert_variance_favourability_follows_sign pass
-- konsol#562 E + ii (Deepak Pai, 18 Nov 2026; amends BUD-7-a's gate; konsol#348 S6 WB1, konsolidat#214):
-- favourability follows the variance sign on signed amounts and is four states (favourable / unfavourable /
-- on_budget / not_applicable), never a summable flag. ZZ8000 is a P&L account with a BLANK normal balance.
-- Entity ZZE1 (USD), FY2026 P1. Chart: ZZ4000 revenue (Profit and Loss, normal balance Credit), ZZ5000 costs
-- (Profit and Loss, normal balance Debit), ZZ6000 rent (Profit and Loss, Debit). Trial balance (period
-- movement): ZZ4000 Cr 1,200 | ZZ5000 Dr 1,200 | ZZ6000 Dr 700 | ZZ6100 Dr 30 | ZZ8000 Dr 100 | ZZ1000 cash Cr 830 (balance
-- sheet, so the batch balances for assert_tb_submission_batches_balance), so the actuals are ZZ4000 -1,200, ZZ5000
-- +1,200, ZZ6000 +700 and ZZ8000 +100. Budget scenario ZZ_PLAN_2026, base layer, Period movement, USD: ZZ4000 Cr 1,000
-- (-1,000) | ZZ5000 Dr 1,000 (+1,000) | ZZ6000 Dr 700 (+700) | ZZ8000 Dr 200 (+200).
-- Hand-computed: revenue 1,200 actual against 1,000 budget is MORE revenue, 'favourable'; expense 1,200 against
-- 1,000 is MORE cost, 'unfavourable'; rent 700 against 700 is a zero variance, 'on_budget'; ZZ8000 100 against 200
-- is below budget, 'favourable' though its normal balance is blank; cash stays 'not_applicable'. ZZ6100 unbudgeted costs Dr 30 with no Budget Entry: budget zero ("Unbudgeted is
-- unfavourable", Deepak Pai, 22 Sep 2026), so 30 against 0 is 'unfavourable', never 'not_applicable'.
-- `+gold_variance_analysis assert_variance_favourability_follows_sign` must
-- BUILD and PASS.
--
-- Red on the S5 model: the column is the S3 Bool (favourable yes/no), so the test does not compile (no
-- variance_favourability column), and the S3 history stands: the S3-B11 rule read "Revenue: actual > budget",
-- which on signed amounts asked -1,200 > -1,000 and marked the extra revenue unfavourable.
--
-- The lineage of gold_scenario_trial_balance reads these tables too, empty here, so they are named to exist
-- (empty): epm_raw.fiscal_calendar_years,
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
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5000', 'ZZ costs', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0),
  ('ZZ6000', 'ZZ rent', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0),
  ('ZZ6100', 'ZZ unbudgeted costs', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0),
  ('ZZ8000', 'ZZ undeclared', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', '', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0),
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'ASSET', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1200, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', ''),
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ5000', 1200, 0, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', ''),
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ6000', 700, 0, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', ''),
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ6100', 30, 0, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', ''),
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ8000', 100, 0, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', ''),
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ1000', 0, 830, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZE1', 2026, 1, 6, '2026-02-05 09:00:00', 'Period movement');
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ACTUAL', 'Actual', 'actual', 1),
  ('ZZ_PLAN_2026', 'ZZ plan 2026', 'budget', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1000, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ5000', 1000, 0, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 700, 0, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-4', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ8000', 200, 0, 'USD', 'Period movement', '', '');
