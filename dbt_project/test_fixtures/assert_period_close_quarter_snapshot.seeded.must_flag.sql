-- gate: expect assert_period_close_quarter_snapshot flag 3
-- Period-close family (konsolidat#<this issue>), check (c): the standing must_flag fixture for quarter-end snapshots. It
-- seeds gold_trial_balance, gold_pnl_quarterly, gold_ytd_trial_balance and the calendar directly and runs the test alone.
-- Calendar FY2026: P0 Opening, P1-P3 Regular Q1, P10-P12 Regular Q4, P13 Closing (labelled Q4, as konsol labels it).
-- ZZE1 revenue ZZ4000 (P&L) movements: P0 -20 (P&L in the Opening period), P1-P3 -10 each, P12 -100, P13 +130 (the close).
-- gold_pnl_quarterly as a mapping that counts the Closing period in Q4 would build it: Q1 -30, Q4 +30 (= P12 + P13),
-- OPN -20 (a label the calendar never gives a Regular period: not judged).
-- gold_ytd_trial_balance: P3 -50, P12 -150 (both carry the Opening period's -20).
-- Expected: FAIL 3 --
--   quarter_total_differs_from_calendar  Q4: gold_pnl_quarterly +30 against the calendar's Regular Q4 -100 (gap -130)
--   quarter_end_ytd_differs              Q1 (P3): YTD -50 against P1-P3 -30
--   quarter_end_ytd_differs              Q4 (P12): YTD -150 against P1-P12 Regular -130
-- Q1's total (-30 = -30) passes.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 0, 'FY2026-P00', 'FY2026 opening', 'Opening', '2026-01-01', '2026-01-01', 'Q1', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 10, 'FY2026-P10', 'Oct 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q4', 'Open'),
  (2026, 11, 'FY2026-P11', 'Nov 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_gold.gold_trial_balance (data_area_id, fiscal_year, fiscal_period, main_account, is_pnl, period_net_amount) VALUES
  ('ZZE1', 2026, 0, 'ZZ4000', 1, -20),
  ('ZZE1', 2026, 1, 'ZZ4000', 1, -10),
  ('ZZE1', 2026, 2, 'ZZ4000', 1, -10),
  ('ZZE1', 2026, 3, 'ZZ4000', 1, -10),
  ('ZZE1', 2026, 12, 'ZZ4000', 1, -100),
  ('ZZE1', 2026, 13, 'ZZ4000', 1, 130);
INSERT INTO epm_gold.gold_pnl_quarterly (data_area_id, fiscal_year, fiscal_quarter, main_account, quarter_net_amount) VALUES
  ('ZZE1', 2026, 'OPN', 'ZZ4000', -20),
  ('ZZE1', 2026, 'Q1', 'ZZ4000', -30),
  ('ZZE1', 2026, 'Q4', 'ZZ4000', 30);
INSERT INTO epm_gold.gold_ytd_trial_balance (data_area_id, fiscal_year, fiscal_period, main_account, is_pnl, ytd_net_amount) VALUES
  ('ZZE1', 2026, 3, 'ZZ4000', 1, -50),
  ('ZZE1', 2026, 12, 'ZZ4000', 1, -150);
