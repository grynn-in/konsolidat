-- assert_entity_has_one_amount_basis: must FAIL with exactly 1 result (konsolidat#199).
-- One entity, ZZOP, with two claimed batches that declare different bases:
--   ZZM1 (FY2026 P1) 'Period-end balance'  and  ZZM2 (FY2026 P2) 'Year-to-date movement'.
-- Each batch is balanced and has a known basis, so the per-batch tests pass; only the
-- entity-level mix is wrong.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZM1', 'ZZOP', 2026, 1, 'ZZ1000', 150, 0, '', 'ZZ-TBS-M1', now(), ''),
  ('ZZM1', 'ZZOP', 2026, 1, 'ZZ3000', 0, 150, '', 'ZZ-TBS-M1', now(), ''),
  ('ZZM2', 'ZZOP', 2026, 2, 'ZZ1000', 170, 0, '', 'ZZ-TBS-M2', now(), ''),
  ('ZZM2', 'ZZOP', 2026, 2, 'ZZ3000', 0, 170, '', 'ZZ-TBS-M2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZM1', 'ZZ-TBS-M1', 'ZZOP', 2026, 1, 2, now(), 'Period-end balance'),
  ('ZZM2', 'ZZ-TBS-M2', 'ZZOP', 2026, 2, 2, now(), 'Year-to-date movement');
