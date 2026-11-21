-- gate: expect assert_retained_earnings_account_unique flag 1
-- konsolidat#316: two chart accounts flagged is_retained_earnings (ZZ3100, ZZ3200) and one topside
-- P&L adjustment row for group ZZG: the close has no single account to post to, so the test flags
-- group ZZG (count 2). Twin that passes: assert_retained_earnings_account_unique.one_account.sql.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 1, 1),
  ('ZZ3200', 'ZZ retained earnings 2', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 1, 1),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 3, 'ZZ4000', 'ZZ revenue', 'USD', 100, 'topside', 'ZZJ-00001');
