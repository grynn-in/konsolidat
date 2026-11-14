-- gate: build +gold_fully_consolidated_tb assert_journal_pnl_closed_at_year_end assert_end_to_end_bs_balances
-- gate: expect assert_journal_pnl_closed_at_year_end pass
-- gate: expect assert_end_to_end_bs_balances pass
-- konsolidat#316 7i GUARD (not red): ic_elimination is EXCLUDED from the journal close
-- (journal_close_excluded_layers()) because it already reverses its own P&L legs in the Closing period
-- with the #259 entity close. If the journal_close layer ever also closed ic_elimination, the IC
-- P&L would be reversed twice and this test would flag it (proved by removing 'ic_elimination' from the macro).
-- Group ZZG (EUR): ZZP and ZZS, both full 100%, both 'Period-end balance' files, no deal rows.
-- FY2026 P12 (first claimed period): ZZP sells to ZZS: ZZP cash +1000 Dr, ZZ4100 IC revenue 1000 Cr (partner ZZS);
-- ZZS ZZ5100 IC cost 1000 Dr (partner ZZP), cash 1000 Cr. FY2027 P1 files carry the year's result in
-- ZZ3100 retained earnings (ZZP 1000 Cr, ZZS 1000 Dr) with the P&L at 0, so a later fiscal year is present and
-- the #259 close is synthesised in the declared Closing period FY2026 P13. ZZ3100 is the one is_retained_earnings account.
-- Expected: the IC elimination eliminates the pair in P12 and its own reversal legs net the P&L to 0 by P13.
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS partial_period_treatment String DEFAULT '';
ALTER TABLE epm_staging.consolidation_adjustments ADD COLUMN IF NOT EXISTS reverse_fiscal_year UInt16 DEFAULT 0;
ALTER TABLE epm_staging.consolidation_adjustments ADD COLUMN IF NOT EXISTS reverse_fiscal_period UInt8 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_tolerance Float64 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4100', 'ZZ intercompany revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 1, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5100', 'ZZ intercompany cost', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 1, '', '', 0, 'EXPENSE', 'Published', 0);
INSERT INTO epm_staging.intercompany_accounts
  (main_account, counterpart_account, description, status)
VALUES
  ('ZZ4100', 'ZZ5100', 'ZZ test: konsolidat#316 7i', 'Published');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open'),
  (2027, 1, 'FY2027-P01', 'Jan 2027', 'Regular', '2027-01-01', '2027-01-31', 'Q1', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZP', 'ZZ Parent', 'ZZG', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZS', 'ZZ Subsidiary', 'ZZG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('EUR', 'Euro', 'E', 2);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, partial_period_treatment)
VALUES
  ('ZZG', '', 'ZZ Group', 'EUR', 'Whole period'),
  ('ZZG', 'ZZP', 'ZZ Parent', 'EUR', ''),
  ('ZZG', 'ZZS', 'ZZ Subsidiary', 'EUR', '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZP', 'ZZG', 'ZZP', 1, 1, 'ZZG/ZZP', 'ZZG/ZZP', 'ZZG', ''),
  ('ZZG', 'ZZS', 'ZZG', 'ZZS', 1, 1, 'ZZG/ZZS', 'ZZG/ZZS', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZP', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZS', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZBP1', 'ZZP', 2026, 12, 'ZZ1000', 1000, 0, '', 'ZZ-TBS-P1', '2027-01-05 09:00:00', ''),
  ('ZZBP1', 'ZZP', 2026, 12, 'ZZ4100', 0, 1000, '', 'ZZ-TBS-P1', '2027-01-05 09:00:00', 'ZZS'),
  ('ZZBS1', 'ZZS', 2026, 12, 'ZZ5100', 1000, 0, '', 'ZZ-TBS-S1', '2027-01-05 09:00:00', 'ZZP'),
  ('ZZBS1', 'ZZS', 2026, 12, 'ZZ1000', 0, 1000, '', 'ZZ-TBS-S1', '2027-01-05 09:00:00', ''),
  ('ZZBP2', 'ZZP', 2027, 1, 'ZZ1000', 1000, 0, '', 'ZZ-TBS-P2', '2027-02-05 09:00:00', ''),
  ('ZZBP2', 'ZZP', 2027, 1, 'ZZ3100', 0, 1000, '', 'ZZ-TBS-P2', '2027-02-05 09:00:00', ''),
  ('ZZBS2', 'ZZS', 2027, 1, 'ZZ3100', 1000, 0, '', 'ZZ-TBS-S2', '2027-02-05 09:00:00', ''),
  ('ZZBS2', 'ZZS', 2027, 1, 'ZZ1000', 0, 1000, '', 'ZZ-TBS-S2', '2027-02-05 09:00:00', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBP1', 'ZZ-TBS-P1', 'ZZP', 2026, 12, 2, '2027-01-05 09:00:00', 'Period-end balance'),
  ('ZZBS1', 'ZZ-TBS-S1', 'ZZS', 2026, 12, 2, '2027-01-05 09:00:00', 'Period-end balance'),
  ('ZZBP2', 'ZZ-TBS-P2', 'ZZP', 2027, 1, 2, '2027-02-05 09:00:00', 'Period-end balance'),
  ('ZZBS2', 'ZZ-TBS-S2', 'ZZS', 2027, 1, 2, '2027-02-05 09:00:00', 'Period-end balance');
