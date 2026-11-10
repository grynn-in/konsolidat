-- gate: build gold_entity_ownership gold_consolidated_trial_balance gold_fx_revaluation gold_business_combination_journal gold_goodwill_amortisation_journal gold_business_disposal_journal assert_ownership_window_matches_deal_period assert_ownership_uses_effective_date assert_post_disposal_excluded assert_ownership_chain_complete
-- gate: expect assert_ownership_window_matches_deal_period pass
-- gate: expect assert_ownership_uses_effective_date pass
-- gate: expect assert_post_disposal_excluded pass
-- gate: expect assert_ownership_chain_complete pass
-- konsolidat#252 (task 2b): fiscal period P is the declared period, not calendar month P. A fiscal year that
-- starts in April: FY2023 runs 2023-04-01 to 2024-03-31 and FY2024 2024-04-01 to 2025-03-31, monthly Regular
-- periods, P13 Closing on the year's last day. ZZG (USD) holds 60% of ZZF (USD, full) from 2023-04-01 to
-- 2024-03-31 and 80% from 2024-04-01. ZZF uploads FY2023 P12 (March 2024), FY2024 P1 (April 2024) and
-- FY2024 P2 (May 2024).
-- Expected: the 80% holding applies from FY2024 P1, the period whose declared span starts on 1 April; FY2023
-- P12 stays at 60%. assert_ownership_uses_effective_date reads the expectation from the calendar source.
-- On main FY2024 P1 was judged on 2024-01-01 (calendar month 1) and resolved the 60% holding; the 80% one
-- first applied in FY2024 P4 (judged on 2024-04-01), which is July.
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to the shape the
-- ownership macro reads.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
-- The deal tables and the group's policy columns, as business_disposal.sql creates them (konsol's DDL).
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
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1100', 'ZZ receivables', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1800', 'ZZ goodwill', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ share capital', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 0, 0),
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 1, 0),
  ('ZZ3500', 'ZZ investment', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ4950', 'ZZ gain or loss on disposal', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('USD', 'US Dollar', '$', 2);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2023, 1, 'FY2023-P01', 'Apr 2023', 'Regular', '2023-04-01', '2023-04-30', 'Q1', 'Open'),
  (2023, 2, 'FY2023-P02', 'May 2023', 'Regular', '2023-05-01', '2023-05-31', 'Q1', 'Open'),
  (2023, 3, 'FY2023-P03', 'Jun 2023', 'Regular', '2023-06-01', '2023-06-30', 'Q1', 'Open'),
  (2023, 4, 'FY2023-P04', 'Jul 2023', 'Regular', '2023-07-01', '2023-07-31', 'Q2', 'Open'),
  (2023, 5, 'FY2023-P05', 'Aug 2023', 'Regular', '2023-08-01', '2023-08-31', 'Q2', 'Open'),
  (2023, 6, 'FY2023-P06', 'Sep 2023', 'Regular', '2023-09-01', '2023-09-30', 'Q2', 'Open'),
  (2023, 7, 'FY2023-P07', 'Oct 2023', 'Regular', '2023-10-01', '2023-10-31', 'Q3', 'Open'),
  (2023, 8, 'FY2023-P08', 'Nov 2023', 'Regular', '2023-11-01', '2023-11-30', 'Q3', 'Open'),
  (2023, 9, 'FY2023-P09', 'Dec 2023', 'Regular', '2023-12-01', '2023-12-31', 'Q3', 'Open'),
  (2023, 10, 'FY2023-P10', 'Jan 2024', 'Regular', '2024-01-01', '2024-01-31', 'Q4', 'Open'),
  (2023, 11, 'FY2023-P11', 'Feb 2024', 'Regular', '2024-02-01', '2024-02-29', 'Q4', 'Open'),
  (2023, 12, 'FY2023-P12', 'Mar 2024', 'Regular', '2024-03-01', '2024-03-31', 'Q4', 'Open'),
  (2023, 13, 'FY2023-P13', 'FY2023 closing', 'Closing', '2024-03-31', '2024-03-31', 'Q4', 'Open'),
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
  (2024, 13, 'FY2024-P13', 'FY2024 closing', 'Closing', '2025-03-31', '2025-03-31', 'Q4', 'Open');
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZF', 'USD');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZF', 'ZZ Held through April', 'USD');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZF', 'ZZG', 'ZZF', 1, 1, 'ZZG/ZZF', 'ZZG/ZZF', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id, is_disposal, disposal_date)
VALUES
  ('ZZG', 'ZZF', '2023-04-01', '2024-03-31', 60, 'full', 'ZZG', '', 0, '2149-06-06'),
  ('ZZG', 'ZZF', '2024-04-01', '2149-06-06', 80, 'full', 'ZZG', '', 0, '2149-06-06');
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZF', 2023, 12, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 30, 0, 30, 1),
  ('ZZF', 2023, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 30, -30, 1),
  ('ZZF', 2024, 1, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 40, 0, 40, 1),
  ('ZZF', 2024, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 40, -40, 1),
  ('ZZF', 2024, 2, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 50, 0, 50, 1),
  ('ZZF', 2024, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 50, -50, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZF', 2023, 12, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 30, 0, 30, 1),
  ('ZZF', 2023, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 30, -30, 1),
  ('ZZF', 2024, 1, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 40, 0, 40, 1),
  ('ZZF', 2024, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 40, -40, 1),
  ('ZZF', 2024, 2, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZF', 2024, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, -50, 1);
