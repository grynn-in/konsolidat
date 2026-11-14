-- gate: build gold_entity_ownership gold_consolidated_trial_balance assert_method_declared_for_multi_path assert_effective_ownership_is_path_sum assert_effective_ownership_in_range assert_group_equals_translated_for_full
-- gate: expect assert_method_declared_for_multi_path pass
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- gate: expect assert_group_equals_translated_for_full pass
-- konsol#117 shape 2, declared FULL: the same graph as the .undeclared fixture (P holds 100% of A
-- and B; A and B hold 30% of D each, at equity; eff(P, D) = 0.60 along two equity paths), and P
-- declares that it controls D (consolidation_method_declarations: ZZP, ZZD, full, from
-- 2020-01-01). gold_entity_ownership (P, D): 'declared', full, 0.60, NCI 0.40; D's profit of
-- 1,000 line-consolidates into P at group 1,000 (100%, konsolidat#204 (a)) / NCI 400 on each row (nci = 1 - eff downstream),
-- and nothing flags. At A and B, D stays an associate (one path, equity, 'link').
--
-- gold_consolidated_trial_balance is built from its direct inputs; D books in P's currency, so
-- every rate is 1.0 and no governed rate row is needed. The model's other inputs are named so the
-- the gate creates them (empty): epm_staging.historical_equity_rates, epm_staging.group_exchange_rates.
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
  ('ZZP', 'ZZA', 'ZZA', 'ZZA', 1, 1, 'ZZP/ZZA',     'ZZP/ZZA',     'ZZP', ''),
  ('ZZP', 'ZZB', 'ZZB', 'ZZB', 1, 1, 'ZZP/ZZB',     'ZZP/ZZB',     'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZA', 1, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZA/ZZD', 'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZD', 2, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZA/ZZD', 'ZZA', 'ZZA'),
  ('ZZP', 'ZZD', 'ZZB', 'ZZB', 1, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZB/ZZD', 'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZD', 2, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZB/ZZD', 'ZZB', 'ZZB'),
  ('ZZA', 'ZZD', 'ZZA', 'ZZD', 1, 1, 'ZZP/ZZA/ZZD', 'ZZA/ZZD',     'ZZA', 'ZZA'),
  ('ZZB', 'ZZD', 'ZZA', 'ZZD', 1, 1, 'ZZP/ZZA/ZZD', 'ZZB/ZZD',     'ZZB', 'ZZB');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZA', 'ZZA', '2020-01-01', '2149-06-06', 100, 'full',   'ZZP', ''),
  ('ZZB', 'ZZB', '2020-01-01', '2149-06-06', 100, 'full',   'ZZP', ''),
  ('ZZA', 'ZZD', '2020-01-01', '2149-06-06', 30,  'equity', 'ZZA', 'ZZA'),
  ('ZZA', 'ZZD', '2020-01-01', '2149-06-06', 30,  'equity', 'ZZB', 'ZZB');
INSERT INTO epm_staging.consolidation_method_declarations
  (consolidation_group, data_area_id, consolidation_method, effective_date, reason)
VALUES
  ('ZZP', 'ZZD', 'full', '2020-01-01', 'ZZ fixture: P directs D''s relevant activities through A and B (IFRS 10.7); the 60% is control');
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZD', 'USD');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZP', '',    'ZZ Parent', 'USD'),
  ('ZZA', '',    'ZZ Member A', 'USD'),
  ('ZZB', '',    'ZZ Member B', 'USD'),
  ('ZZA', 'ZZD', 'ZZ Jointly held D', 'USD');
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
  ('ZZD', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 1000, 0, 1000, 1),
  ('ZZD', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 1000, -1000, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZD', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZD', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
