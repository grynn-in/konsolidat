-- gate: build gold_entity_ownership gold_consolidated_trial_balance gold_acquisition_adjustments gold_business_combination_journal gold_business_disposal_journal gold_consolidation_adjustments gold_equity_method_associates gold_fx_revaluation gold_goodwill_amortisation_journal gold_ic_reconciliation gold_ic_eliminations gold_nci_attribution_journal gold_fully_consolidated_tb assert_no_ownership_step_on_partial_full_subsidiary
-- gate: expect assert_no_ownership_step_on_partial_full_subsidiary flag 1
-- MUST FLAG (konsol#117 pair 3 review, finding C): a change of METHOD at the same share. ZZP holds 50% of ZZJ as a
-- full subsidiary (control by contract) until 2026-03-31 and 50% as a joint operation (proportional) from 2026-04-01,
-- with no acquisition or disposal journal line. The percentage does not move, so the old trigger (a change of
-- effective_ownership_pct) saw nothing; but layer 1 carries the earlier movements at 100% with NCI and the later ones at
-- 50% with none, and the movement-grained CTB mixes them. Expect one row naming both methods (FY2026 P3 -> P4).
-- Before the fix the test flags 0 and this fixture fails (red).
--
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZP', 'ZZJ', 'ZZP', 'ZZJ', 1, 1, 'ZZP/ZZJ', 'ZZP/ZZJ', 'ZZP', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZP', 'ZZJ', '2020-01-01', '2026-03-31', 50, 'full', 'ZZP', ''),
  ('ZZP', 'ZZJ', '2026-04-01', '2149-06-06', 50, 'proportional', 'ZZP', '');
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1100', 'ZZ receivables', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ5000', 'ZZ cost', 'Expense', 'Expense', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZJ', 'USD');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZP', '',    'ZZ Parent', 'USD'),
  ('ZZP', 'ZZJ', 'ZZ Joint operation', 'USD');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('USD', 'US Dollar', '$', 2, 0);
-- The live table may predate konsolidat#259's close flag: add it to the scratch clone first.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZJ', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 600, 0, 600, 1),
  ('ZZJ', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 400, 0, 400, 1),
  ('ZZJ', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 1000, -1000, 1),
  ('ZZJ', 2026, 4, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 100, 0, 100, 1),
  ('ZZJ', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 100, -100, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZJ', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 600, 0, 600, 1),
  ('ZZJ', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 400, 0, 400, 1),
  ('ZZJ', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1),
  ('ZZJ', 2026, 4, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZJ', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, -100, 1);
