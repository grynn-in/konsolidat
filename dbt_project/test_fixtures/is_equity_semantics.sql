-- assert_is_equity_is_account_type_equity: must PASS (konsolidat#213).
-- is_equity is what the account IS (account_type = 'Equity'); uses_historical_rate is what the
-- chart DECLARES about translation (fx_method = 'historical'). The two are independent, so this
-- chart crosses them in all four combinations:
--   ZZ1400 Asset,     historical -> is_equity 0, uses_historical_rate 1
--   ZZ2300 Liability, historical -> is_equity 0, uses_historical_rate 1
--   ZZ3000 Equity,    historical -> is_equity 1, uses_historical_rate 1
--   ZZ3400 Equity,    closing    -> is_equity 1, uses_historical_rate 0
-- Today silver derives is_equity from fx_method, so ZZ1400 and ZZ2300 come back 1 and ZZ3400 comes
-- back 0: the three rows this test flags until the meaning is fixed.
-- A historical balance-sheet account is a legitimate declaration (governed_chart_guard refuses only
-- P&L at historical and balance sheet at average), so the guard passes on this chart.
-- The live table may predate is_retained_earnings: add it to the scratch clone first.
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1400', 'ZZ land', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'FIXED_ASSET', 'Published', 0),
  ('ZZ2300', 'ZZ deferred income', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Non-current Liabilities', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'LIABILITY', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0);
