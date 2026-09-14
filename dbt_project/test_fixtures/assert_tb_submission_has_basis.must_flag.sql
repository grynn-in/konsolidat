-- assert_tb_submission_has_basis: must FAIL with exactly 2 results (konsolidat#199).
-- ZZB1: claim with an empty amount_basis (an undeclared batch, e.g. claimed before the column existed).
-- ZZB2: claim with 'Balances', which is not one of the three declared bases.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ1000', 150, 0, '', 'ZZ-TBS-1', now(), ''),
  ('ZZB1', 'ZZOP', 2026, 1, 'ZZ3000', 0, 150, '', 'ZZ-TBS-1', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ1000', 170, 0, '', 'ZZ-TBS-2', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 2, 'ZZ3000', 0, 170, '', 'ZZ-TBS-2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZOP', 2026, 1, 2, now(), ''),
  ('ZZB2', 'ZZ-TBS-2', 'ZZOP', 2026, 2, 2, now(), 'Balances');
