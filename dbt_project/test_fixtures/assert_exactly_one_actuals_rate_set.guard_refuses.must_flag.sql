-- gate: build gold_consolidated_trial_balance
-- gate: refuse gold_consolidated_trial_balance 0 Rate Set(s) flagged Is Actuals
-- governed_rate_guard (konsol#348 S4-Q7 a, W2): the consolidated trial balance's first pre_hook must
-- REFUSE the build when no Rate Set is flagged Is Actuals, naming the count, even when nothing is
-- translated, as long as there is a trial balance (an empty TB is the fresh stack, which builds:
-- assert_exactly_one_actuals_rate_set.empty_stack.sql). This is the existing stack whose konsol has not synced epm_staging.rate_sets yet
-- (reconcile_all creates and fills it; konsol's patch creates and flags ACTUAL): it is refused by
-- name, not built at every set as before the column existed.
--
-- One USD entity (ZZE1) in a USD group (ZZG), 100% owned, FY2026 P1: same currency, so no rate key is
-- translated and the old guard had nothing to refuse. The Rate Sets table holds a budget's set only.
-- The selector names the model alone (no `+`), so the ERROR source test
-- assert_exactly_one_actuals_rate_set is not selected and cannot skip the model first: the guard
-- itself must stop the run. The model's rate tables are named so the gate creates them (empty):
-- epm_staging.group_exchange_rates, epm_staging.historical_equity_rates.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZE1', 'USD');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'USD');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('USD', 'US Dollar', '$', 2, 0);
-- No set is flagged Is Actuals.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZBUD', 'ZZ budget 2026', 0);
-- The live table may predate konsolidat#259's close flag: add it to the scratch clone first.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 100, -100, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, -100, 1);
