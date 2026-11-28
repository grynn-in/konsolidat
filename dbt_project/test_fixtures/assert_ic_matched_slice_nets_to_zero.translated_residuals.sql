-- gate: build +gold_fully_consolidated_tb assert_ic_matched_slice_nets_to_zero
-- gate: expect assert_ic_matched_slice_nets_to_zero pass
-- konsolidat#395 (PR #404, live check 28 Nov 2026 on the aquila-bike example): the "fully matched"
-- decision in assert_ic_matched_slice_nets_to_zero is made per side, within the floor. Translated
-- legs leave a sub-floor residual on each side, and the final check summed those residuals across
-- the account's sides against the same floor, so 15 correct rows (0.005 to 0.012) were reported.
-- Group ZZG (EUR), no intercompany-difference account. ZZA reports a receivable ZZ1100 of 100.003
-- against each of three partners ZZB, ZZC, ZZD; each reports a payable ZZ2100 of 100.00. Every pair
-- matches 100.00 (the difference 0.003 is under the floor, status 'none', no difference leg), so each
-- ZZA side is left with a residual of 0.003 (under 0.005, accepted per side) and ZZ1100 carries
-- 0.009 in total, over the floor. ZZ2100 nets to 0.
-- Expected: assert_ic_matched_slice_nets_to_zero passes: the tolerance on the account is the floor
-- plus the residuals already accepted on its sides (0.005 + 0.009).
-- Red before the fix: one row, ZZ1100 at P1, consolidated_ic_to_date 0.009.
-- Tables named so the gate creates them (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings, epm_staging.group_exchange_rates, epm_staging.ic_balances,
-- epm_staging.ic_elimination_rules, epm_staging.consolidation_adjustments.
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_business_unit String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_tolerance Float64 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ1100', 'ZZ intercompany receivables (a)', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ1200', 'ZZ intercompany receivables (b)', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ2100', 'ZZ intercompany payables (a)', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ2200', 'ZZ intercompany payables (b)', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0);
INSERT INTO epm_staging.intercompany_accounts
  (main_account, counterpart_account, description, status)
VALUES
  ('ZZ1100', 'ZZ2100', 'ZZ test: #395 sub-floor residuals', 'Published');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZA', 'ZZ Parent', 'ZZG', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZB', 'ZZ Subsidiary B', 'ZZG', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZC', 'ZZ Subsidiary C', 'ZZG', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZD', 'ZZ Subsidiary D', 'ZZG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('EUR', 'Euro', 'E', 2);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, ic_difference_account, ic_difference_tolerance, nci_account)
VALUES
  ('ZZG', '', 'ZZ Group', 'EUR', '', 0, 'ZZ3400'),
  ('ZZG', 'ZZA', 'ZZ Parent', 'EUR', '', 0, ''),
  ('ZZG', 'ZZB', 'ZZ Subsidiary B', 'EUR', '', 0, ''),
  ('ZZG', 'ZZC', 'ZZ Subsidiary C', 'EUR', '', 0, ''),
  ('ZZG', 'ZZD', 'ZZ Subsidiary D', 'EUR', '', 0, '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZA', 'ZZG', 'ZZA', 1, 1, 'ZZG/ZZA', 'ZZG/ZZA', 'ZZG', ''),
  ('ZZG', 'ZZB', 'ZZG', 'ZZB', 1, 1, 'ZZG/ZZB', 'ZZG/ZZB', 'ZZG', ''),
  ('ZZG', 'ZZC', 'ZZG', 'ZZC', 1, 1, 'ZZG/ZZC', 'ZZG/ZZC', 'ZZG', ''),
  ('ZZG', 'ZZD', 'ZZG', 'ZZD', 1, 1, 'ZZG/ZZD', 'ZZG/ZZD', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZA', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZB', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZC', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZD', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_cost_center)
VALUES
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1100', 100.003, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZB', ''),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1100', 100.003, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZC', ''),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1100', 100.003, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZD', ''),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ3000', 0, 300.009, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', '', ''),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ1000', 100, 0, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', '', ''),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ2100', 0, 100, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', 'ZZA', ''),
  ('ZZBC1', 'ZZC', 2026, 1, 'ZZ1000', 100, 0, '', 'ZZ-TBS-C1', '2026-02-05 09:00:00', '', ''),
  ('ZZBC1', 'ZZC', 2026, 1, 'ZZ2100', 0, 100, '', 'ZZ-TBS-C1', '2026-02-05 09:00:00', 'ZZA', ''),
  ('ZZBD1', 'ZZD', 2026, 1, 'ZZ1000', 100, 0, '', 'ZZ-TBS-D1', '2026-02-05 09:00:00', '', ''),
  ('ZZBD1', 'ZZD', 2026, 1, 'ZZ2100', 0, 100, '', 'ZZ-TBS-D1', '2026-02-05 09:00:00', 'ZZA', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBA1', 'ZZ-TBS-A1', 'ZZA', 2026, 1, 4, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBB1', 'ZZ-TBS-B1', 'ZZB', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBC1', 'ZZ-TBS-C1', 'ZZC', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBD1', 'ZZ-TBS-D1', 'ZZD', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement');
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals; the consolidation guard refuses a build with zero flagged sets even when nothing is translated.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
