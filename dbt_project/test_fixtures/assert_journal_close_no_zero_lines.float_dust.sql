-- konsolidat#357 re-review R2 (7n): float dust. Three topside journals on ZZ4000 revenue in FY2026 net to 0 in decimal
-- (0.10 Cr in P6, 0.20 Cr in P7, 0.30 Dr in P8, each against ZZ1000 cash, none reversed), but their Float64 sum is about
-- 1e-17. Journals are kept to 4 places (#353): the close rounds each line to 4 places and posts no line whose rounded
-- amount is 0, and assert_journal_close_no_zero_lines judges the rounded amount the same way.
-- RED on the base (b89e027): `having abs(sum) > 0` keeps a ~1e-17 ZZ4000 line and a matching ZZ3100 line, and the
-- test flags both (FAIL 2).
-- gate: build +gold_fully_consolidated_tb assert_journal_close_no_zero_lines assert_journal_pnl_closed_at_year_end
-- gate: expect assert_journal_close_no_zero_lines pass
-- gate: expect assert_journal_pnl_closed_at_year_end pass
-- Scaffold: group ZZG (USD) fully owns ZZS (USD books; P12 balance sheet only: cash ZZ1000 1,000 Dr | share capital
-- ZZ3000 1,000 Cr); FY2026 P13 is the declared Closing period; ZZ3100 is the one is_retained_earnings account; ZZS files
-- a FY2027 P1 movement (cash 10 Dr | ZZ3000 10 Cr) so FY2026 is a closed year (a later entity year follows).
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS partial_period_treatment String DEFAULT '';
CREATE TABLE IF NOT EXISTS epm_staging.business_combinations (name String, consolidation_group String, acquired_entity String, acquisition_date Date, share_acquired_pct Float64, consideration_currency String, total_consideration Float64, net_assets_acquired Float64, fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, nci_at_acquisition Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_fair_value Float64 DEFAULT 0;
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_consideration (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_acquired_balances (parent String, idx UInt16, main_account String, book_amount Float64, fair_value_adjustment Float64, note String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_costs (parent String, idx UInt16, kind String, amount Float64, currency String, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.business_disposal_proceeds (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
ALTER TABLE epm_staging.consolidation_adjustments ADD COLUMN IF NOT EXISTS reverse_fiscal_year UInt16 DEFAULT 0;
ALTER TABLE epm_staging.consolidation_adjustments ADD COLUMN IF NOT EXISTS reverse_fiscal_period UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open'),
  (2026, 8, 'FY2026-P08', 'Aug 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q3', 'Open'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZS', 'ZZ Subsidiary', 'ZZG', 0, 'Active', 'USD', 'US', '');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, partial_period_treatment)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD', 'Whole period'),
  ('ZZG', 'ZZS', 'ZZ Subsidiary', 'USD', '');
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZG', 'ZZS', '', 1, 'ZZG');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES
  ('ZZG', 'ZZS', 'ZZG', 'ZZS', 1, 1, 'ZZG/ZZS');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZS', '2020-01-01', '2149-06-06', 100, 'full');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('USD', 'US Dollar', '$', 2);
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZT1', 'ZZS', 2026, 12, 'ZZ1000', 1000, 0, 'Cash', 'ZZ-TBS-T1', now(), ''),
  ('ZZT1', 'ZZS', 2026, 12, 'ZZ3000', 0, 1000, 'Share capital', 'ZZ-TBS-T1', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZT1', 'ZZ-TBS-T1', 'ZZS', 2026, 12, 2, now(), 'Period movement');
INSERT INTO epm_staging.consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, posted_by, status, approved_by, reverse_fiscal_year, reverse_fiscal_period)
VALUES
  ('ZZG', 'topside', 'ZZJ-00001', 'ZZS', 2026, 6, 'ZZ1000', 0.1, 0, 'dust a', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-00001', 'ZZS', 2026, 6, 'ZZ4000', 0, 0.1, 'dust a', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-00002', 'ZZS', 2026, 7, 'ZZ1000', 0.2, 0, 'dust b', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-00002', 'ZZS', 2026, 7, 'ZZ4000', 0, 0.2, 'dust b', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-00003', 'ZZS', 2026, 8, 'ZZ1000', 0, 0.3, 'dust c', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-00003', 'ZZS', 2026, 8, 'ZZ4000', 0.3, 0, 'dust c', 'zz', 'Approved', 'zz', 0, 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2027, 1, 'FY2027-P01', 'Jan 2027', 'Regular', '2027-01-01', '2027-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZT2', 'ZZS', 2027, 1, 'ZZ1000', 10, 0, 'Cash', 'ZZ-TBS-ZZT2', now(), ''),
  ('ZZT2', 'ZZS', 2027, 1, 'ZZ3000', 0, 10, 'Later year', 'ZZ-TBS-ZZT2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZT2', 'ZZ-TBS-ZZT2', 'ZZS', 2027, 1, 2, now(), 'Period movement');
