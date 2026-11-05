-- gate: build +assert_tb_submission_batches_balance
-- gate: expect assert_tb_submission_batches_balance flag 1
-- #256: an UNbalanced trial balance in a three-decimal currency (BHD) must be flagged.
-- One ZZ entity, FY2026 P1. Five lines of Dr 0.004 (0.020) against one line of
-- Cr 0.003: out of balance by 0.017 BHD, above the 0.01 tolerance.
-- Before #256 bronze rounded each line to 2 places: every amount became 0.00, the
-- batch arrived balanced, and the test passed it (0 rows). At amount_scale() the
-- 0.017 reaches the test and it is flagged (1 row).
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1001', 0.004, 0, 'Petty cash 1', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1002', 0.004, 0, 'Petty cash 2', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1003', 0.004, 0, 'Petty cash 3', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1004', 0.004, 0, 'Petty cash 4', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1005', 0.004, 0, 'Petty cash 5', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ3000', 0, 0.003, 'Share capital', 'ZZ-TBS-1', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZBH', 2026, 1, 6, now(), 'Period movement');
