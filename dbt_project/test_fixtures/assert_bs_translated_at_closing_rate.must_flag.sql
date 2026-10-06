-- assert_bs_translated_at_closing_rate (konsolidat#257): must FLAG, before and after the fix.
--
-- Seeds gold_consolidated_trial_balance as the movement-only translation produced it before #257,
-- and runs the test alone:
--   gate-v.sh <wt> dbt_project/test_fixtures/assert_bs_translated_at_closing_rate.must_flag.sql \
--     "assert_bs_translated_at_closing_rate"
--
-- ZZE1 (EUR) in ZZG (USD). ZZ1000 cash +100 at P1 (closing 1.10) translated 110; no movement at P2
-- (closing 1.20), so the balance stays at 110 instead of 120. ZZ2000 mirrors it (-110 for -120).
-- ZZ1100 moves only at P2, so the entity has a P2 spine. Expected: 2 rows (ZZ1000 and ZZ2000 at P2).
-- ZZ3000 is equity and ZZ4000 is declared average: neither is checked, so neither is named.
-- ZZ1200 (undeclared, so checked at closing) carries the retranslation row the fix adds
-- (+4 at P2: 40 x (1.20 - 1.10)), so its balance is 48 and it is not named either.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1100', 'ZZ bank', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ2000', 'ZZ payables', 'Liability', 'Liability', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ share capital', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, local_amount, accounting_currency, reporting_currency, ownership_pct,
   consolidation_method, closing_rate, average_rate, historical_equity_rate, translation_rate, translated_amount,
   group_amount, nci_amount, partner_data_area_id, uses_historical_rate)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 0, 100, 'EUR', 'USD', 1, 'full', 1.10, 1.05, NULL, 1.10, 110, 110, 0, '', 0),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ2000', 'ZZ payables', 'Liability', 1, 0, 0, -100, 'EUR', 'USD', 1, 'full', 1.10, 1.05, NULL, 1.10, -110, -110, 0, '', 0),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 1, -40, 'EUR', 'USD', 1, 'full', 1.10, 1.05, NULL, 1.10, -44, -44, 0, '', 0),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1200', 'ZZ receivable', 'Asset', 1, 0, 0, 40, 'EUR', 'USD', 1, 'full', 1.10, 1.05, NULL, 1.10, 44, 44, 0, '', 0),
  ('ZZG', 'ZZE1', 2026, 2, 'ZZ1200', 'ZZ receivable', 'Asset', 1, 0, 0, 0, 'EUR', 'USD', 1, 'full', 1.20, 1.15, NULL, 1.20, 4, 4, 0, '', 0),
  ('ZZG', 'ZZE1', 2026, 2, 'ZZ1100', 'ZZ bank', 'Asset', 1, 0, 0, 50, 'EUR', 'USD', 1, 'full', 1.20, 1.15, NULL, 1.20, 60, 60, 0, '', 0),
  ('ZZG', 'ZZE1', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, -50, 'EUR', 'USD', 1, 'full', 1.20, 1.15, NULL, 1.15, -57.5, -57.5, 0, '', 0);
