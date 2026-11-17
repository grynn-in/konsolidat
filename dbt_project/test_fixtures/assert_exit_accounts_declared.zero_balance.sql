-- gate: build +assert_exit_accounts_declared
-- gate: expect assert_exit_accounts_declared pass
-- konsolidat#335 review F3: a bare end of an entity that carries no balances (no TB rows: a legacy link ended in the past).
-- The exit journal posts nothing, so the root need not declare exit_gain_loss_account. Expect pass (base: 1 row, 'missing').
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS exit_gain_loss_account String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ1100', 'ZZ receivables', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ1420', 'ZZ plant', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'PPE', 'Published', 0),
  ('ZZ1800', 'ZZ goodwill', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'INTANGIBLES', 'Published', 0),
  ('ZZ1900', 'ZZ fair value adjustments', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'PPE', 'Published', 0),
  ('ZZ2100', 'ZZ payables', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3500', 'ZZ investment in subsidiaries', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'INVESTMENTS', 'Published', 0),
  ('ZZ4900', 'ZZ bargain purchase gain', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Other income', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OTHER_INCOME', 'Published', 0),
  ('ZZ4950', 'ZZ gain or loss on disposal', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Other income', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OTHER_INCOME', 'Published', 0),
  ('ZZ6900', 'ZZ goodwill amortisation', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OPEX', 'Published', 0),
  ('ZZ6950', 'ZZ acquisition costs', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OPEX', 'Published', 0);
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2024, 0, 'FY2024-P00', 'FY2024 opening', 'Opening', '2024-04-01', '2024-04-01', '', 'Open'),
  (2024, 1, 'FY2024-P01', 'Apr 2024', 'Regular', '2024-04-01', '2024-04-30', 'Q1', 'Open'),
  (2024, 2, 'FY2024-P02', 'May 2024', 'Regular', '2024-05-01', '2024-05-31', 'Q1', 'Open'),
  (2024, 3, 'FY2024-P03', 'Jun 2024', 'Regular', '2024-06-01', '2024-06-30', 'Q1', 'Open'),
  (2024, 4, 'FY2024-P04', 'Jul 2024', 'Regular', '2024-07-01', '2024-07-31', 'Q2', 'Open'),
  (2024, 5, 'FY2024-P05', 'Aug 2024', 'Regular', '2024-08-01', '2024-08-31', 'Q2', 'Open'),
  (2024, 6, 'FY2024-P06', 'Sep 2024', 'Regular', '2024-09-01', '2024-09-30', 'Q2', 'Open'),
  (2024, 7, 'FY2024-P07', 'Oct 2024', 'Regular', '2024-10-01', '2024-10-31', 'Q3', 'Open'),
  (2024, 8, 'FY2024-P08', 'Nov 2024', 'Regular', '2024-11-01', '2024-11-30', 'Q3', 'Open'),
  (2024, 9, 'FY2024-P09', 'Dec 2024', 'Regular', '2024-12-01', '2024-12-31', 'Q3', 'Open'),
  (2024, 10, 'FY2024-P10', 'Jan 2025', 'Regular', '2025-01-01', '2025-01-31', 'Q4', 'Open'),
  (2024, 11, 'FY2024-P11', 'Feb 2025', 'Regular', '2025-02-01', '2025-02-28', 'Q4', 'Open'),
  (2024, 12, 'FY2024-P12', 'Mar 2025', 'Regular', '2025-03-01', '2025-03-31', 'Q4', 'Open'),
  (2024, 13, 'FY2024-P13', 'FY2024 closing', 'Closing', '2025-03-31', '2025-03-31', '', 'Open'),
  (2024, 14, 'FY2024-P14', 'FY2024 adjustment', 'Adjustment', '2025-03-31', '2025-03-31', '', 'Open'),
  (2025, 0, 'FY2025-P00', 'FY2025 opening', 'Opening', '2025-04-01', '2025-04-01', '', 'Open'),
  (2025, 1, 'FY2025-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open'),
  (2025, 2, 'FY2025-P02', 'May 2025', 'Regular', '2025-05-01', '2025-05-31', 'Q1', 'Open'),
  (2025, 3, 'FY2025-P03', 'Jun 2025', 'Regular', '2025-06-01', '2025-06-30', 'Q1', 'Open'),
  (2025, 4, 'FY2025-P04', 'Jul 2025', 'Regular', '2025-07-01', '2025-07-31', 'Q2', 'Open'),
  (2025, 5, 'FY2025-P05', 'Aug 2025', 'Regular', '2025-08-01', '2025-08-31', 'Q2', 'Open'),
  (2025, 6, 'FY2025-P06', 'Sep 2025', 'Regular', '2025-09-01', '2025-09-30', 'Q2', 'Open'),
  (2025, 7, 'FY2025-P07', 'Oct 2025', 'Regular', '2025-10-01', '2025-10-31', 'Q3', 'Open'),
  (2025, 8, 'FY2025-P08', 'Nov 2025', 'Regular', '2025-11-01', '2025-11-30', 'Q3', 'Open'),
  (2025, 9, 'FY2025-P09', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q3', 'Open'),
  (2025, 10, 'FY2025-P10', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q4', 'Open'),
  (2025, 11, 'FY2025-P11', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q4', 'Open'),
  (2025, 12, 'FY2025-P12', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2026-03-31', '2026-03-31', '', 'Open'),
  (2025, 14, 'FY2025-P14', 'FY2025 adjustment', 'Adjustment', '2026-03-31', '2026-03-31', '', 'Open');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZXG', 'ZZXB', 'ZZXG', 'ZZXB', 1, 1, 'ZZXG/ZZXB', 'ZZXG/ZZXB', 'ZZXG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id, is_disposal, disposal_date)
VALUES
  ('ZZXG', 'ZZXB', '2020-01-01', '2024-08-15', 100, 'full', 'ZZXG', '', 0, '9999-12-31');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, nci_account, exit_gain_loss_account)
VALUES
  ('ZZXG', '', 'ZZ Exit Group', 'USD', '', '');
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals. The consolidation reads rates of
-- this set only, and its guard refuses a build with zero or two flagged sets.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
