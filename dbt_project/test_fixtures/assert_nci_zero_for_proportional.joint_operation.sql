-- gate: build gold_entity_ownership gold_consolidated_trial_balance assert_effective_ownership_is_path_sum assert_group_equals_translated_for_full assert_group_equals_translated_times_share_for_proportional assert_nci_zero_for_proportional assert_nci_equals_translated_times_minority
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_group_equals_translated_for_full pass
-- gate: expect assert_group_equals_translated_times_share_for_proportional pass
-- gate: expect assert_nci_zero_for_proportional pass
-- gate: expect assert_nci_equals_translated_times_minority pass
-- konsol#117 pair 3, shape 3 as a joint operation (IFRS 11.20): ZZP operates a joint operation ZZJ
-- through a link at 50%, consolidation_method 'proportional'. ZZJ books in USD (ZZP's currency), so
-- every rate is 1.0. ZZJ's cash +1,000 and revenue -1,000 (FY2026 P1) line-consolidate at the
-- operator's share.
-- Expected: group_amount 500 / -500, nci_amount 0 on both rows; effective ownership 0.50, method
-- 'proportional', method_source 'link'. On a model that treats proportional like full, group is
-- 1,000 / -1,000 and nci is 500 / -500, so the share test and the nci test each flag 2 rows.
-- The model's other inputs are named so the gate creates them (empty):
-- epm_staging.historical_equity_rates, epm_staging.group_exchange_rates.
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to the shape the macro reads.
-- The owner joins the sorting key (konsol#117); this is the live upgrade statement, a no-op on an upgraded table.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZP', 'ZZJ', 'ZZP', 'ZZJ', 1, 1, 'ZZP/ZZJ', 'ZZP/ZZJ', 'ZZP', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZP', 'ZZJ', '2020-01-01', '2149-06-06', 50, 'proportional', 'ZZP', '');
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZJ', 'USD');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZP', '',    'ZZ Operator', 'USD'),
  ('ZZP', 'ZZJ', 'ZZ Joint operation', 'USD');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('USD', 'US Dollar', '$', 2, 0);
-- The live table may predate konsolidat#259's close flag: add it to the scratch clone first.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZJ', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 1000, 0, 1000, 1),
  ('ZZJ', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 1000, -1000, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZJ', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZJ', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
