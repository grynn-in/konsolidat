-- gate: expect assert_trial_balance_period_declared flag 1
-- konsolidat#171 / #252 (task 2a): a trial-balance period the calendar does not declare is refused at ERROR
-- severity, never judged at a date built from the period number. ZZT uploads FY2024 P5 and P6; the
-- calendar declares P5 only. Expected: one row, (ZZT, 2024, 6, 'period not declared in
-- epm_staging.fiscal_periods').
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2024, 5, 'FY2024-P05', 'May 2024', 'Regular', '2024-05-01', '2024-05-31', 'Q2', 'Open');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZT', 2024, 5, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZT', 2024, 6, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 60, 0, 60, 1);
