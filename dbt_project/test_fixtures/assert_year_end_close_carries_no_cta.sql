-- assert_year_end_close_carries_no_cta (konsolidat#259-1): must PASS once the close is translated
-- as a close. Seeds silver_gl_entries (with the 'Year-end close' posting layer), rates, calendar
-- and ownership, so the gate builds the partner TB, the consolidation and the CTA itself:
--   gate-x.sh <wt> dbt_project/test_fixtures/assert_year_end_close_carries_no_cta.sql \
--     "gold_trial_balance_by_partner gold_consolidated_trial_balance gold_fx_revaluation assert_year_end_close_carries_no_cta"
--
-- Two EUR entities in a USD group (ZZG), 100% owned. Calendar: FY2025 P11, P12 (Regular),
-- P13 (Closing, so it translates at P12's rates), FY2026 P1.
-- Governed EUR->USD: 2025 P11 closing 1.05 / average 1.00; 2025 P12 closing 1.20 / average 1.10;
-- 2026 P1 closing 1.25 / average 1.22.
-- Chart: ZZ1000 cash (closing), ZZ4000 revenue (average), ZZ3100 retained earnings (equity,
-- is_retained_earnings, declared HISTORICAL: #259-1 credits the close at the translated result
-- whatever 3100 declares). ZZE1 has a historical tranche for ZZ3100 (0.90); ZZE2 has none, so
-- its ZZ3100 falls back to the closing rate (#258-1), as a closing-declared 3100 would translate.
--   ZZE1: P11 revenue -60 / cash +60; P12 revenue -40 / cash +40;
--         P13 close revenue +100 / RE -100; FY2026 P1 revenue -50 / cash +50
--   ZZE2: P12 revenue -100 / cash +100; P13 close revenue +100 / RE -100; FY2026 P1 the same as ZZE1
-- Before #259 (close rows translated as activity):
--   ZZE1 P13: reversal +100 x 1.10 = 110, RE -100 x 0.90 = -90 -> CTA -20; the year's P&L
--             -60 - 44 + 110 = +6, not 0.
--   ZZE2 P13: reversal +110, RE -100 x 1.20 = -120 -> CTA +10 (P&L 0).
-- After: ZZE1 reversal +104, RE -104; ZZE2 reversal +110, RE -110; P13 CTA 0 and P&L 0 for both.
-- gold_trial_balance is seeded for the rate guard (pre_hook).
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 1, 1),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency, currency_source, governed_currency, erp_currency, in_konsol, in_erp)
VALUES
  ('ZZE1', 'EUR', 'konsol', 'EUR', '', 1, 0),
  ('ZZE2', 'EUR', 'konsol', 'EUR', '', 1, 0);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'USD'),
  ('ZZG', 'ZZE2', 'ZZ Entity 2', 'USD');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2025, 11, '2025-11-30', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2025, 12, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2025, 13, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2025, 11, '2025-11-30', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2025, 12, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2025, 13, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate)
VALUES
  ('ZZG', 'ZZE1', 'ZZ3100', '2020-01-01', 0.90);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 11, 'FY2025-P11', 'Nov 2025', 'Regular', '2025-11-01', '2025-11-30', 'Q4', 'Open'),
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', 'Q4', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'EUR', 2025, 11, 'Closing', 1.05, 'ZZ-GER-2025-11'),
  ('USD', 'EUR', 2025, 11, 'Average', 1.00, 'ZZ-GER-2025-11'),
  ('USD', 'EUR', 2025, 12, 'Closing', 1.20, 'ZZ-GER-2025-12'),
  ('USD', 'EUR', 2025, 12, 'Average', 1.10, 'ZZ-GER-2025-12'),
  ('USD', 'EUR', 2026, 1, 'Closing', 1.25, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.22, 'ZZ-GER-2026-01');
INSERT INTO epm_silver.silver_gl_entries
  (recid, data_area_id, accounting_date, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, debit_amount, credit_amount, partner_data_area_id, posting_layer)
VALUES
  (1, 'ZZE1', '2025-11-30', 2025, 11, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 60, 0, '', ''),
  (2, 'ZZE1', '2025-11-30', 2025, 11, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 60, '', ''),
  (3, 'ZZE1', '2025-12-31', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 40, 0, '', ''),
  (4, 'ZZE1', '2025-12-31', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 40, '', ''),
  (5, 'ZZE1', '2025-12-31', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 100, 0, '', 'Year-end close'),
  (6, 'ZZE1', '2025-12-31', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 100, '', 'Year-end close'),
  (7, 'ZZE1', '2026-01-31', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 50, 0, '', ''),
  (8, 'ZZE1', '2026-01-31', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, '', ''),
  (11, 'ZZE2', '2025-12-31', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, '', ''),
  (12, 'ZZE2', '2025-12-31', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, '', ''),
  (13, 'ZZE2', '2025-12-31', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 100, 0, '', 'Year-end close'),
  (14, 'ZZE2', '2025-12-31', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 100, '', 'Year-end close'),
  (15, 'ZZE2', '2026-01-31', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 50, 0, '', ''),
  (16, 'ZZE2', '2026-01-31', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, '', '');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2025, 11, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 60, 0, 60, 1),
  ('ZZE1', 2025, 11, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 60, -60, 1),
  ('ZZE1', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 40, 0, 40, 1),
  ('ZZE1', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 40, -40, 1),
  ('ZZE1', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 100, 0, 100, 1),
  ('ZZE1', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 100, -100, 1),
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, -50, 1),
  ('ZZE2', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE2', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, -100, 1),
  ('ZZE2', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 100, 0, 100, 1),
  ('ZZE2', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 100, -100, 1),
  ('ZZE2', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZE2', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, -50, 1);
