-- silver_tb_movements, basis 'Period movement': assert_tb_movements_balance and
-- assert_tb_movements_cumulate_to_source must PASS (konsolidat#199).
-- One ZZ entity, FY2026 periods 1-3, each batch a balanced set of period movements:
--   ZZ1000 (asset)      150 Dr |  20 Dr |  30 Dr
--   ZZ2000 (liability)   50 Cr |  20 Dr |  absent (no movement: no row is produced for P3)
--   ZZ3000 (equity)     100 Cr |  40 Cr |  30 Cr
-- Expected movements: the source rows as they are; P3 carries no ZZ2000 row.
-- The live control table may predate the column: add it to the scratch clone first.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ1000', 150, 0, 'Cash', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ2000', 0, 50, 'Loan', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-1', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ1000', 20, 0, 'Cash', 'ZZ-TBS-2', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ2000', 20, 0, 'Loan', 'ZZ-TBS-2', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ3000', 0, 40, 'Share capital', 'ZZ-TBS-2', now(), ''),
  ('ZZB3', 'ZZOP', 2026, 3, 'ZZ1000', 30, 0, 'Cash', 'ZZ-TBS-3', now(), ''),
  ('ZZB3', 'ZZOP', 2026, 3, 'ZZ3000', 0, 30, 'Share capital', 'ZZ-TBS-3', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZOP', 2026, 1, 3, now(), 'Period movement'),
  ('ZZB2', 'ZZ-TBS-2', 'ZZOP', 2026, 2, 3, now(), 'Period movement'),
  ('ZZB3', 'ZZ-TBS-3', 'ZZOP', 2026, 3, 2, now(), 'Period movement');
