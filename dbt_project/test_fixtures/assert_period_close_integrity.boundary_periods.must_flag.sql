-- gate: expect assert_period_close_integrity flag 5
-- Period-close family (konsolidat#397), checks (a), (d), (e): the standing must_flag fixture for the boundary
-- rules. It seeds silver_tb_movements' OUTPUT, silver_main_accounts and the calendar directly and runs the test alone.
-- Calendar: FY2025 P6 and P12 Regular, P13 Closing and P14 Adjustment on 2025-12-31; FY2026 P0 Opening and P1 Regular.
-- ZZE1 files 'Period-end balance'.
-- Expected: FAIL 5, one row per reason:
--   close_outside_closing_period     FY2025 P6  ZZ4000 'year_end_close' -10 (a close in a Regular period)
--   closing_period_phantom_movement  FY2025 P13 ZZ1000 +25 (cash moved on the day it shares with P12)
--   opening_period_pnl_movement      FY2026 P0  ZZ4000 -10
--   opening_period_balance_movement  FY2026 P0  ZZ1000 +5
--   pnl_after_closing_period         FY2025     ZZ4000 -40 in P14 (ZZE1 files FY2026, so FY2025 is closed)
-- Not named: the FY2025 P13 close rows on ZZ4000 (P&L) and ZZ3100 (retained earnings, partner ''), and every Regular row.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 6, 'FY2025-P06', 'Jun 2025', 'Regular', '2025-06-01', '2025-06-30', 'Q2', 'Open'),
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', 'Q4', 'Open'),
  (2025, 14, 'FY2025-P14', 'FY2025 adjustment', 'Adjustment', '2025-12-31', '2025-12-31', 'Q4', 'Open'),
  (2026, 0, 'FY2026-P00', 'FY2026 opening', 'Opening', '2026-01-01', '2026-01-01', 'Q1', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_silver.silver_tb_movements (data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id, amount_basis, movement_kind, source_net_amount, movement_amount) VALUES
  ('ZZE1', 2025, 6, 'ZZ4000', '', 'Period-end balance', 'year_end_close', 0, -10),
  ('ZZE1', 2025, 12, 'ZZ1000', '', 'Period-end balance', 'activity', 100, 100),
  ('ZZE1', 2025, 12, 'ZZ4000', '', 'Period-end balance', 'activity', -100, -100),
  ('ZZE1', 2025, 13, 'ZZ1000', '', 'Period-end balance', 'activity', 125, 25),
  ('ZZE1', 2025, 13, 'ZZ4000', '', 'Period-end balance', 'year_end_close', 0, 100),
  ('ZZE1', 2025, 13, 'ZZ3100', '', 'Period-end balance', 'year_end_close', -100, -100),
  ('ZZE1', 2025, 14, 'ZZ4000', '', 'Period-end balance', 'activity', -40, -40),
  ('ZZE1', 2026, 0, 'ZZ4000', '', 'Period-end balance', 'activity', -10, -10),
  ('ZZE1', 2026, 0, 'ZZ1000', '', 'Period-end balance', 'activity', 130, 5),
  ('ZZE1', 2026, 1, 'ZZ1000', '', 'Period-end balance', 'activity', 140, 10);
INSERT INTO epm_silver.silver_main_accounts (main_account_id, is_pnl, is_retained_earnings) VALUES ('ZZ1000', 0, 0), ('ZZ4000', 1, 0), ('ZZ3100', 0, 1);
