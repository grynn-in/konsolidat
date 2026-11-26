-- gate: expect assert_period_close_ytd_spine flag 2
-- Period-close family (konsolidat#<this issue>), check (b): the standing must_flag fixture for the YTD spine. It seeds
-- the claimed batches (bronze_trial_balance_submissions) and silver_tb_movements' OUTPUT directly and runs the test alone,
-- so the model's own spine is not involved: the rows are what a broken spine would emit.
-- ZZE1 files 'Year-to-date movement', FY2026:
--   P1  cash ZZ1000 100 Dr | loan ZZ2000 100 Cr
--   P2  cash ZZ1000 150 Dr | revenue ZZ4000 150 Cr          (the loan has vanished; revenue is new)
-- Right movements in P2: cash +50, loan +100 (the reversal), revenue -150 (from zero).
-- Seeded movements in P2: cash +50; NO loan row (the spine missed the vanished key); revenue -50 (differenced against a
-- phantom earlier figure of -100).
-- Expected: FAIL 2 -- ZZ2000 P2 vanished_key_not_reversed (+100), ZZ4000 P2 new_key_not_from_zero (-100). Cash passes.
INSERT INTO epm_bronze.bronze_trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, partner_data_area_id, claimed_at, amount_basis)
VALUES
  ('ZZS1', 'ZZE1', 2026, 1, 'ZZ1000', 100, 0, '', now(), 'Year-to-date movement'),
  ('ZZS1', 'ZZE1', 2026, 1, 'ZZ2000', 0, 100, '', now(), 'Year-to-date movement'),
  ('ZZS2', 'ZZE1', 2026, 2, 'ZZ1000', 150, 0, '', now(), 'Year-to-date movement'),
  ('ZZS2', 'ZZE1', 2026, 2, 'ZZ4000', 0, 150, '', now(), 'Year-to-date movement');
INSERT INTO epm_silver.silver_tb_movements (data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id, amount_basis, movement_kind, source_net_amount, movement_amount) VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', '', 'Year-to-date movement', 'activity', 100, 100),
  ('ZZE1', 2026, 1, 'ZZ2000', '', 'Year-to-date movement', 'activity', -100, -100),
  ('ZZE1', 2026, 2, 'ZZ1000', '', 'Year-to-date movement', 'activity', 150, 50),
  ('ZZE1', 2026, 2, 'ZZ4000', '', 'Year-to-date movement', 'activity', -150, -50);
