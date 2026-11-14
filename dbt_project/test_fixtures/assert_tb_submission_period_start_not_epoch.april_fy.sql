-- gate: build +assert_gl_period_start_is_declared +assert_tb_submission_period_start_not_epoch
-- gate: expect assert_tb_submission_period_start_not_epoch pass
-- gate: expect assert_gl_period_start_is_declared pass
-- konsolidat#171 step 2d, task 5d. A TB-only site (no entity calendar, no ERP calendar) with an April-March
-- fiscal year declared in konsol: FY2026 P1 = 2025-04-01..2025-04-30. A TB movement in FY2026 P1 must be
-- dated 2025-04-01 in silver_gl_entries. The old fallback (calendar month of the year and period) said
-- 2026-01-01: not the epoch, so only assert_gl_period_start_is_declared sees it (red on the old model).
-- Names for the gate to create (comments count): epm_gold.entity_fiscal_calendars, epm_staging.fiscal_periods.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ1000', 150, 0, '', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ3000', 0, 150, '', 'ZZ-TBS-1', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZOP', 2026, 1, 2, now(), 'Period-end balance');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open');
