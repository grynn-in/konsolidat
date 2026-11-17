-- gate: build +gold_fully_consolidated_tb assert_exit_matches_ic_left
-- gate: expect assert_exit_matches_ic_left pass
-- konsolidat#358 review F2 (task X11): an exit in the group's LAST trial-balance period is not judged until the
-- intercompany spine has the period after it. The .receivable shape, but ZZXE's bare end is mid-period
-- (end_date 2026-03-15) and nobody has submitted P4 yet: the trial balance (so the IC spine) ends at FY2026 P3
-- (ZZXA books a P3 movement).
-- The exit posts in P3, the Regular period holding end_date; the pair leaves the IC reconciliation in the first
-- period ZZXE is not live, P4, and gold_ic_reconciliation has no row there until a P4 trial balance arrives.
-- EXPECT pass: the exit's 'left' row is pending, not missing. On the base the test flags left_missing for the pair,
-- which fails the build and blocks the close of P3, the month the link ended.
-- Inputs named so they exist (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings, epm_staging.group_exchange_rates, epm_staging.ic_balances,
-- epm_staging.ic_elimination_rules, epm_staging.consolidation_adjustments.
-- konsolidat#335: the live consolidation_groups may predate exit_gain_loss_account (gold_ownership_exit_journal, assert_exit_accounts_declared read it).
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS exit_gain_loss_account String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS accounting_framework String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS framework_note String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_treatment String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_amortisation_years UInt16 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS acquisition_costs_treatment String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS measurement_period String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS bargain_purchase String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS fair_value_adjustment_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS investment_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS bargain_purchase_gain_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS disposal_gain_loss_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS disposal_proceeds_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_amortisation_expense_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS acquisition_costs_account String DEFAULT '';
CREATE TABLE IF NOT EXISTS epm_staging.business_combinations (name String, consolidation_group String, acquired_entity String, acquisition_date Date, share_acquired_pct Float64, consideration_currency String, total_consideration Float64, net_assets_acquired Float64, fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, nci_at_acquisition Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_fair_value Float64 DEFAULT 0;
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_consideration (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_acquired_balances (parent String, idx UInt16, main_account String, book_amount Float64, fair_value_adjustment Float64, note String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_costs (parent String, idx UInt16, kind String, amount Float64, currency String, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.business_disposal_proceeds (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
-- The fully consolidated TB's other layers read these live tables, empty here: epm_staging.consolidation_adjustments,
-- epm_staging.ic_balances, epm_staging.ic_elimination_rules, epm_staging.intercompany_accounts, and the deal tables below.
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_tolerance Float64 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ1200', 'ZZ intercompany receivables', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ2100', 'ZZ intercompany payables', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ4960', 'ZZ gain or loss on exit', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0),
  ('ZZ5900', 'ZZ intercompany differences', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0);
INSERT INTO epm_staging.intercompany_accounts
  (main_account, counterpart_account, description, status)
VALUES
  ('ZZ1200', 'ZZ2100', 'ZZ test: konsolidat#335 X6', 'Published');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Open'),
  (2026, 5, 'FY2026-P05', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZXA', 'ZZ Held', 'ZZXG', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZXE', 'ZZ Exited', 'ZZXG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('EUR', 'Euro', 'E', 2);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, ic_difference_account, ic_difference_tolerance, nci_account, exit_gain_loss_account)
VALUES
  ('ZZXG', '', 'ZZ Group', 'EUR', 'ZZ5900', 0, '', 'ZZ4960'),
  ('ZZXG', 'ZZXA', 'ZZ Held', 'EUR', '', 0, '', ''),
  ('ZZXG', 'ZZXE', 'ZZ Exited', 'EUR', '', 0, '', '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZXG', 'ZZXA', 'ZZXG', 'ZZXA', 1, 1, 'ZZXG/ZZXA', 'ZZXG/ZZXA', 'ZZXG', ''),
  ('ZZXG', 'ZZXE', 'ZZXG', 'ZZXE', 1, 1, 'ZZXG/ZZXE', 'ZZXG/ZZXE', 'ZZXG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id, is_disposal, disposal_date)
VALUES
  ('ZZXG', 'ZZXA', '2026-01-01', '2149-06-06', 100, 'full', 'ZZXG', '', 0, '9999-12-31'),
  ('ZZXG', 'ZZXE', '2026-01-01', '2026-03-15', 100, 'full', 'ZZXG', '', 0, '9999-12-31');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZBE1', 'ZZXE', 2026, 1, 'ZZ1200', 100, 0, '', 'ZZ-TBS-E1', '2026-02-05 09:00:00', 'ZZXA'),
  ('ZZBE1', 'ZZXE', 2026, 1, 'ZZ3000', 0, 100, '', 'ZZ-TBS-E1', '2026-02-05 09:00:00', ''),
  ('ZZBA1', 'ZZXA', 2026, 1, 'ZZ1000', 100, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', ''),
  ('ZZBA1', 'ZZXA', 2026, 1, 'ZZ2100', 0, 100, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZXE'),
  ('ZZBA3', 'ZZXA', 2026, 3, 'ZZ1000', 10, 0, '', 'ZZ-TBS-A3', '2026-04-05 09:00:00', ''),
  ('ZZBA3', 'ZZXA', 2026, 3, 'ZZ4000', 0, 10, '', 'ZZ-TBS-A3', '2026-04-05 09:00:00', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBE1', 'ZZ-TBS-E1', 'ZZXE', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBA1', 'ZZ-TBS-A1', 'ZZXA', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBA3', 'ZZ-TBS-A3', 'ZZXA', 2026, 3, 2, '2026-04-05 09:00:00', 'Period movement');
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals. The consolidation reads rates of
-- this set only, and its guard refuses a build with zero or two flagged sets.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
