-- gate: build gold_entity_ownership gold_consolidated_trial_balance gold_acquisition_adjustments gold_business_combination_journal gold_business_disposal_journal gold_consolidation_adjustments gold_equity_method_associates gold_fx_revaluation gold_goodwill_amortisation_journal gold_ic_reconciliation gold_ic_eliminations gold_nci_attribution_journal gold_ownership_exit_journal gold_fully_consolidated_tb assert_exit_derecognises_carried assert_end_to_end_bs_balances assert_exit_accounts_declared assert_exit_out_of_scope_named
-- gate: expect assert_exit_derecognises_carried pass
-- gate: expect assert_exit_out_of_scope_named pass
-- gate: expect assert_end_to_end_bs_balances pass
-- gate: expect assert_exit_accounts_declared pass
-- konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X3: a 70% full subsidiary acquired by a
-- Business Combination ends its Ownership Period with no Business Disposal and no successor (a bare end).
-- Group ZZQG (USD, root declares goodwill ZZ1800, FVA ZZ1900, investment ZZ3500, NCI ZZ3400, exit gain/loss ZZ4960;
-- Impairment only, so no amortisation). Entity ZZQS (EUR), 70% full from 2026-01-01, end_date 2026-03-31:
-- the exit event is FY2026 P4 (ownership_exits()). Equity accounts declare fx_method 'closing' (equity is never
-- revalued: movement x the closing rate of the period it was posted, #257 Q2).
-- Governed EUR->USD: P1 Closing 1.10 / Average 1.10, P2 1.20 / 1.15, P3 1.25 / 1.22 (P4 1.30 / 1.28, unused).
-- Acquisition BC-ZZQG-ZZQS-2026-01-01 (FY2026 P1), 70% for 1,500 USD, NCI partial. Acquired balances (EUR):
-- ZZ1100 +1,000 | ZZ1420 +500 (FVA +200) | ZZ2100 -300 | ZZ3000 -200 | ZZ3100 -1,000, so at 1.10:
-- net assets 1,320, FVA 220, NCI 0.30 x 1,540 = 462, goodwill 1,500 + 462 - 1,540 = 422.
-- TB (EUR movements): P1 the acquired balance sheet above; P2 ZZ1100 +300, ZZ5000 +200, ZZ4000 -500;
-- P3 ZZ1100 +100, ZZ5000 +100, ZZ4000 -200. Nothing in P4.
-- Carried at P3 (USD): layer 1 non-equity BS at cum_local x 1.25: ZZ1100 1,750 | ZZ1420 625 | ZZ2100 -375.
-- CTA (fx_revaluation plug): P2 -135, P3 -78 (P1 0), total -213; NCI attribution 30%: result P2 -103.50, P3 -36.60;
-- CTA leg +40.50, +23.40; NCI P2 -144.00, P3 -60.00. So the 'CTA' line carries -213 + 63.90 = -149.10 (the group's
-- 70%), and ZZ3400 carries -462 - 144 - 60 = -666 (= 0.30 x (2,000 net assets + 220 FVA)).
-- Expected journal EXIT_ZZQG_ZZQS_2026_4 in FY2026 P4:
--   Cr ZZ1100 1,750 | Cr ZZ1420 625 | Dr ZZ2100 375 | Cr ZZ1800 422 | Cr ZZ1900 220 | Dr CTA 149.10 | Dr ZZ3400 666
--   Dr ZZ4960 1,826.90  (loss = 2,000 + 422 + 220 - 666 - 149.10: net assets, goodwill and FVA out, NCI out,
--                         the group's CTA recycled to P&L; no proceeds)
-- Equity (ZZ3000, ZZ3100) and the P&L are not touched (IFRS 10.B98). On the base (no exit journal) the balances
-- stay in the group: assert_exit_derecognises_carried flags the 7 carried accounts in P4.
-- Inputs named so they exist (empty): epm_staging.consolidation_adjustments, epm_staging.ic_balances,
-- epm_staging.ic_elimination_rules, epm_staging.intercompany_accounts, epm_staging.historical_equity_rates.
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_tolerance Float64 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS partial_period_treatment String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS exit_gain_loss_account String DEFAULT '';
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
CREATE TABLE IF NOT EXISTS epm_staging.business_combinations (name String, consolidation_group String, acquired_entity String, acquisition_date Date, share_acquired_pct Float64, consideration_currency String, total_consideration Float64, net_assets_acquired Float64, fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, nci_at_acquisition Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_fair_value Float64 DEFAULT 0;
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_consideration (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_acquired_balances (parent String, idx UInt16, main_account String, book_amount Float64, fair_value_adjustment Float64, note String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_costs (parent String, idx UInt16, kind String, amount Float64, currency String, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.business_disposal_proceeds (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZQG', 'ZZQS', 'ZZQG', 'ZZQS', 1, 1, 'ZZQG/ZZQS', 'ZZQG/ZZQS', 'ZZQG', '');
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZQG', 'ZZQS', '', 1, 'ZZQG');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id, is_disposal, disposal_date)
VALUES
  ('ZZQG', 'ZZQS', '2026-01-01', '2026-03-31', 70, 'full', 'ZZQG', '', 0, '9999-12-31');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZQS', 'ZZ Exit Subsidiary', 'ZZQG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZQS', 'EUR');
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1100', 'ZZ receivables', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1420', 'ZZ plant', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1800', 'ZZ goodwill', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1900', 'ZZ fair value adjustments', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ2100', 'ZZ payables', 'Liability', 'Liability', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ share capital', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0),
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 1, 0),
  ('ZZ3400', 'ZZ non-controlling interest', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0),
  ('ZZ3500', 'ZZ investment in subsidiaries', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ4960', 'ZZ gain or loss on exit', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ5000', 'ZZ cost', 'Expense', 'Expense', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency,
   nci_measurement, accounting_framework, goodwill_treatment, acquisition_costs_treatment, measurement_period, bargain_purchase,
   goodwill_account, fair_value_adjustment_account, investment_account, nci_account, bargain_purchase_gain_account,
   disposal_gain_loss_account, disposal_proceeds_account, partial_period_treatment, exit_gain_loss_account)
VALUES
  ('ZZQG', '', 'ZZ Exit Group', 'USD',
   'partial', 'IFRS', 'Impairment only', 'Expense', 'Off', 'Recognise gain',
   'ZZ1800', 'ZZ1900', 'ZZ3500', 'ZZ3400', '',
   '', '', 'Whole period', 'ZZ4960'),
  ('ZZQG', 'ZZQS', 'ZZ Exit Subsidiary', 'USD',
   '', '', '', '', '', '',
   '', '', '', '', '',
   '', '', '', '');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Open'),
  (2026, 5, 'FY2026-P05', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('USD', 'US Dollar', '$', 2, 0),
  ('EUR', 'Euro', 'E', 2, 0);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'EUR', 2026, 1, 'Closing', 1.10, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.10, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 2, 'Closing', 1.20, 'ZZ-GER-2026-02'),
  ('USD', 'EUR', 2026, 2, 'Average', 1.15, 'ZZ-GER-2026-02'),
  ('USD', 'EUR', 2026, 3, 'Closing', 1.25, 'ZZ-GER-2026-03'),
  ('USD', 'EUR', 2026, 3, 'Average', 1.22, 'ZZ-GER-2026-03'),
  ('USD', 'EUR', 2026, 4, 'Closing', 1.30, 'ZZ-GER-2026-04'),
  ('USD', 'EUR', 2026, 4, 'Average', 1.28, 'ZZ-GER-2026-04');
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZQS', 2026, 1, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 1000, 0, 1000, 1),
  ('ZZQS', 2026, 1, 'ZZ1420', 'ZZ plant', 'Asset', 1, 0, '', 500, 0, 500, 1),
  ('ZZQS', 2026, 1, 'ZZ2100', 'ZZ payables', 'Liability', 1, 0, '', 0, 300, -300, 1),
  ('ZZQS', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, '', 0, 200, -200, 1),
  ('ZZQS', 2026, 1, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, '', 0, 1000, -1000, 1),
  ('ZZQS', 2026, 2, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 300, 0, 300, 1),
  ('ZZQS', 2026, 2, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 200, 0, 200, 1),
  ('ZZQS', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 500, -500, 1),
  ('ZZQS', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 100, 0, 100, 1),
  ('ZZQS', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 100, 0, 100, 1),
  ('ZZQS', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 200, -200, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZQS', 2026, 1, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZQS', 2026, 1, 'ZZ1420', 'ZZ plant', 'Asset', 1, 0, 500, 0, 500, 1),
  ('ZZQS', 2026, 1, 'ZZ2100', 'ZZ payables', 'Liability', 1, 0, 0, 300, -300, 1),
  ('ZZQS', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 200, -200, 1),
  ('ZZQS', 2026, 1, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 1000, -1000, 1),
  ('ZZQS', 2026, 2, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 300, 0, 300, 1),
  ('ZZQS', 2026, 2, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 200, 0, 200, 1),
  ('ZZQS', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 500, -500, 1),
  ('ZZQS', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZQS', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 100, 0, 100, 1),
  ('ZZQS', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 200, -200, 1);
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period, nci_measurement)
VALUES
  ('BC-ZZQG-ZZQS-2026-01-01', 'ZZQG', 'ZZQS', '2026-01-01', 70, 'USD', 1500, 1320, 220, 422, 0, 462, 'ZZ-OP-ZZQS-1', 'partial');
INSERT INTO epm_staging.business_combination_consideration
  (parent, idx, component, amount, currency, settlement_date, description)
VALUES
  ('BC-ZZQG-ZZQS-2026-01-01', 1, 'Cash', 1500, 'USD', '2026-01-01', 'Cash paid at completion');
INSERT INTO epm_staging.business_combination_acquired_balances
  (parent, idx, main_account, book_amount, fair_value_adjustment, note)
VALUES
  ('BC-ZZQG-ZZQS-2026-01-01', 1, 'ZZ1100', 1000, 0, 'Receivables'),
  ('BC-ZZQG-ZZQS-2026-01-01', 2, 'ZZ1420', 500, 200, 'Plant, stepped up to fair value'),
  ('BC-ZZQG-ZZQS-2026-01-01', 3, 'ZZ2100', -300, 0, 'Payables'),
  ('BC-ZZQG-ZZQS-2026-01-01', 4, 'ZZ3000', -200, 0, 'Share capital'),
  ('BC-ZZQG-ZZQS-2026-01-01', 5, 'ZZ3100', -1000, 0, 'Retained earnings at acquisition');
