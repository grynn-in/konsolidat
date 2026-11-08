-- gate: build +gold_consolidated_trial_balance gold_fully_consolidated_tb assert_group_equals_translated_for_full assert_nci_equals_translated_times_minority assert_nci_zero_for_full_ownership assert_end_to_end_bs_balances
-- gate: expect assert_group_equals_translated_for_full pass
-- gate: expect assert_nci_equals_translated_times_minority pass
-- gate: expect assert_nci_zero_for_full_ownership pass
-- gate: expect assert_end_to_end_bs_balances pass
-- konsolidat#204 option (a), konsol#117 pair 2 K1 (IFRS 10.B86): layer 1 carries a full-method
-- subsidiary at 100%. ZZP (USD, root) holds 70% of ZZC (USD, method full). ZZC's FY2026 P3:
-- revenue -1,000, cost +400, receivables +600 (sums to 0). Every rate is 1.0 (same currency).
-- Expected on the three ZZC rows: group_amount = translated_amount (600 / 400 / -1,000), and
-- nci_amount = 0.30 x translated_amount (180 / 120 / -300), the attribution task K2 posts as the
-- one NCI line. Before the model change group_amount was 0.7 x translated_amount and
-- assert_group_equals_translated_for_full flagged these 3 rows. No .must_flag variant: the
-- defect is model code, not data.
--
-- The live tables may predate konsol#117's graph columns and the declarations table: bring the
-- scratch clones to the shape the macro reads.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZP', 'ZZC', 'ZZP', 'ZZC', 1, 1, 'ZZP/ZZC', 'ZZP/ZZC', 'ZZP', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZP', 'ZZC', '2020-01-01', '2149-06-06', 70, 'full', 'ZZP', '');
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1100', 'ZZ receivables', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ5000', 'ZZ cost', 'Expense', 'Expense', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZC', 'USD');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZP', '',    'ZZ Parent', 'USD'),
  ('ZZP', 'ZZC', 'ZZ Controlled at 70', 'USD');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('USD', 'US Dollar', '$', 2, 0);
-- The live table may predate konsolidat#259's close flag: add it to the scratch clone first.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 600, 0, 600, 1),
  ('ZZC', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 400, 0, 400, 1),
  ('ZZC', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 1000, -1000, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 600, 0, 600, 1),
  ('ZZC', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 400, 0, 400, 1),
  ('ZZC', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
