-- assert_equity_never_revalued (konsolidat#257 Q2): must PASS on the #257 model.
--
-- Seeds gold_consolidated_trial_balance's direct inputs, so the gate builds the model itself:
--   gate-x.sh <wt> dbt_project/test_fixtures/assert_equity_never_revalued.sql \
--     "gold_consolidated_trial_balance assert_equity_never_revalued assert_bs_translated_at_closing_rate"
--
-- One EUR entity (ZZE1) in a USD group (ZZG), 100% owned, FY2026 P1 and P2.
-- Governed EUR->USD: P1 closing 1.10 / average 1.05; P2 closing 1.20 / average 1.15.
--   P1: ZZ1000 cash +50 (closing), ZZ3000 share capital -40 (equity, DECLARED closing),
--       ZZ3300 other reserve -10 (equity, DECLARED closing)
--   P2: ZZ1000 cash +5, ZZ3300 other reserve -5 -- ZZ3000 does not move
-- ZZ1000 is retranslated: 50 x (1.20 - 1.10) = +5 at P2 (balance 66 = 55 x 1.20).
-- Equity is not: ZZ3000 stays -44 (no P2 row at all), ZZ3300's P2 row is -5 x 1.20 = -6 with
-- no retranslation (balance -17, not 15 x 1.20 = -18).
-- Revaluing equity would add a ZZ3000 P2 filler of -4 and a ZZ3300 P2 retranslation of -1.
-- gold_trial_balance is seeded for the rate guard (pre_hook). The model's other inputs are named here
-- so the gate creates them (empty):
-- epm_staging.historical_equity_rates.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ share capital', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0),
  ('ZZ3300', 'ZZ other reserve', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency, currency_source, governed_currency, erp_currency, in_konsol, in_erp)
VALUES
  ('ZZE1', 'EUR', 'konsol', 'EUR', '', 1, 0);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'USD');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2026, 2, '2026-02-28', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'EUR', 2026, 1, 'Closing', 1.10, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.05, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 2, 'Closing', 1.20, 'ZZ-GER-2026-02'),
  ('USD', 'EUR', 2026, 2, 'Average', 1.15, 'ZZ-GER-2026-02');
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 50, 0, 50, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, '', 0, 40, -40, 1),
  ('ZZE1', 2026, 1, 'ZZ3300', 'ZZ other reserve', 'Equity', 1, 0, '', 0, 10, -10, 1),
  ('ZZE1', 2026, 2, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 5, 0, 5, 1),
  ('ZZE1', 2026, 2, 'ZZ3300', 'ZZ other reserve', 'Equity', 1, 0, '', 0, 5, -5, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 40, -40, 1),
  ('ZZE1', 2026, 1, 'ZZ3300', 'ZZ other reserve', 'Equity', 1, 0, 0, 10, -10, 1),
  ('ZZE1', 2026, 2, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 5, 0, 5, 1),
  ('ZZE1', 2026, 2, 'ZZ3300', 'ZZ other reserve', 'Equity', 1, 0, 0, 5, -5, 1);
