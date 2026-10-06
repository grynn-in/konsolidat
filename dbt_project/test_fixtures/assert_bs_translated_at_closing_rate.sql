-- assert_bs_translated_at_closing_rate (konsolidat#257): must PASS once the model retranslates.
--
-- Seeds gold_consolidated_trial_balance's direct inputs, so the gate builds the model itself:
--   gate-v.sh <wt> dbt_project/test_fixtures/assert_bs_translated_at_closing_rate.sql \
--     "gold_consolidated_trial_balance gold_fx_revaluation assert_bs_translated_at_closing_rate"
--
-- One EUR entity (ZZE1) in a USD group (ZZG), 100% owned, FY2026 P1 and P2.
-- Governed EUR->USD: P1 closing 1.10 / average 1.05; P2 closing 1.20 / average 1.15.
--   P1: ZZ1000 cash +100 (closing), ZZ2000 payables -100 (closing),
--       ZZ1200 receivable +40 (UNDECLARED: not in the chart, so translated at closing),
--       ZZ3000 share capital -40 (equity, declared closing: never revalued, #257 Q2)
--   P2: ZZ1100 bank +50 (closing) | ZZ4000 revenue -50 (average) -- the only movements
-- ZZ1000, ZZ2000 and ZZ1200 do not move in P2 but are in the entity's P2 spine, so at P2:
--   ZZ1000 = 100 x 1.20 = 120 (movement-only translation leaves it at 110)
--   ZZ2000 = -120, ZZ1200 = 48, ZZ1100 = 60; ZZ3000 stays -44 (equity is not checked).
-- The model's other inputs are named here so the gate creates them (empty):
-- epm_staging.historical_equity_rates.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1100', 'ZZ bank', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ2000', 'ZZ payables', 'Liability', 'Liability', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ share capital', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
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
-- The live table may predate konsolidat#259's close flag: add it to the scratch clone first.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ2000', 'ZZ payables', 'Liability', 1, 0, '', 0, 100, -100, 1),
  ('ZZE1', 2026, 1, 'ZZ1200', 'ZZ receivable', 'Asset', 1, 0, '', 40, 0, 40, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, '', 0, 40, -40, 1),
  ('ZZE1', 2026, 2, 'ZZ1100', 'ZZ bank', 'Asset', 1, 0, '', 50, 0, 50, 1),
  ('ZZE1', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 50, -50, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ2000', 'ZZ payables', 'Liability', 1, 0, 0, 100, -100, 1),
  ('ZZE1', 2026, 1, 'ZZ1200', 'ZZ receivable', 'Asset', 1, 0, 40, 0, 40, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 40, -40, 1),
  ('ZZE1', 2026, 2, 'ZZ1100', 'ZZ bank', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZE1', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, -50, 1);
