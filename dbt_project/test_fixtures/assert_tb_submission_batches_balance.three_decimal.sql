-- gate: build +assert_tb_submission_batches_balance +assert_tb_movements_balance +assert_tb_movements_cumulate_to_source
-- gate: expect assert_tb_submission_batches_balance pass
-- gate: expect assert_tb_movements_balance pass
-- gate: expect assert_tb_movements_cumulate_to_source pass
-- #256: a balanced trial balance in a three-decimal currency (BHD) must reach the
-- warehouse exactly, so every balance test PASSES on it.
-- One ZZ entity, FY2026 P1, basis 'Period movement'. Five lines of Dr 0.004 and one
-- line of Cr 0.020: balanced to the fils (0.001 BHD).
-- Before #256 bronze rounded each line to 2 places: the five debits became 0.00 and
-- the credit 0.02, so this balanced batch arrived 0.02 out of balance and
-- assert_tb_submission_batches_balance flagged it (1 row). At amount_scale() (4
-- places) every amount lands as submitted.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1001', 0.004, 0, 'Petty cash 1', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1002', 0.004, 0, 'Petty cash 2', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1003', 0.004, 0, 'Petty cash 3', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1004', 0.004, 0, 'Petty cash 4', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ1005', 0.004, 0, 'Petty cash 5', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZBH', 2026, 1, 'ZZ3000', 0, 0.020, 'Share capital', 'ZZ-TBS-1', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZBH', 2026, 1, 6, now(), 'Period movement');
