-- gate: expect assert_period_close_integrity flag 1
-- Period-close family (konsolidat#397), check (a): a P&L balance carried wrongly over a boundary is named in the
-- period it lands in. It seeds the claimed batch (bronze_trial_balance_submissions), gold_ytd_trial_balance's OUTPUT,
-- silver_main_accounts and the calendar directly and runs the test alone.
-- (On the model as built this cannot be produced through the year end: the one path, a year with no Closing period
-- declared, is refused upstream by assert_year_end_close_declared (error), which skips silver_tb_movements. The test is
-- the lock should that guard or the #259 close change.)
-- ZZE1 files 'Period-end balance'. FY2025 P12: revenue ZZ4000 100 Cr. FY2026 P1: revenue ZZ4000 30 Cr.
-- Seeded gold_ytd_trial_balance, as an unclosed year end would build it: FY2025 P12 revenue -100 (ties); FY2026 P1
-- revenue +70 (= -30 - (-100): the prior year's result reversed into the new year's first period).
-- Expected: FAIL 1 -- ZZE1 FY2026 P1 ZZ4000 pnl_not_carried_forward, difference -100.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_bronze.bronze_trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, partner_data_area_id, claimed_at, amount_basis)
VALUES
  ('ZZN1', 'ZZE1', 2025, 12, 'ZZ4000', 0, 100, '', now(), 'Period-end balance'),
  ('ZZN2', 'ZZE1', 2026, 1, 'ZZ4000', 0, 30, '', now(), 'Period-end balance');
INSERT INTO epm_gold.gold_ytd_trial_balance (data_area_id, fiscal_year, fiscal_period, main_account, is_pnl, ytd_net_amount) VALUES
  ('ZZE1', 2025, 12, 'ZZ4000', 1, -100),
  ('ZZE1', 2026, 1, 'ZZ4000', 1, 70);
INSERT INTO epm_silver.silver_main_accounts (main_account_id, is_pnl, is_retained_earnings) VALUES ('ZZ4000', 1, 0);
