-- assert_historical_is_equity_only: must FLAG (konsolidat#92 finding 4).
-- konsol translates and does not remeasure, so fx_method = 'historical' is an Equity-only
-- declaration (konsol#239 refuses anything else at publish). A stack whose chart predates
-- that guard can still carry the wrong declaration, and today nothing says so: the rate is
-- simply never applied, because gold_consolidated_trial_balance applies one only where the
-- chart declares it. This chart carries one of each:
--   ZZ1400 Asset,  historical -> is_equity 0, uses_historical_rate 1  -> the offender
--   ZZ3000 Equity, historical -> is_equity 1, uses_historical_rate 1  -> legitimate, must NOT be named
-- A historical balance-sheet account is a legitimate declaration as far as the chart guard is
-- concerned (governed_chart_guard refuses only P&L at historical and balance sheet at average),
-- so the build reaches the test rather than being refused before it.
-- The live table may predate is_retained_earnings: add it to the scratch clone first.
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1400', 'ZZ land', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'FIXED_ASSET', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0);
