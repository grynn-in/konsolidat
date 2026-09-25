-- konsol#255: a submitted trial balance that carries DECLARED DIMENSION VALUES.
--
-- One entity ZZDM, FY2026 periods 1 and 2, basis 'Period movement'. The point of
-- the fixture is the SPLIT ACCOUNT: ZZ5000 appears TWICE in the same
-- (entity, fiscal_year, fiscal_period, main_account, partner) with two different
-- dim_cost_center / dim_department values, which is exactly the shape the
-- pre-#255 grain of silver_tb_movements cannot tell apart.
--
--   period 1   ZZ5000  CC10 / DEPT-OPS    300 Dr
--              ZZ5000  CC20 / DEPT-SALES  200 Dr
--              ZZ1000  '' / ''            500 Cr      (balanced)
--   period 2   ZZ5000  CC10 / DEPT-OPS    100 Dr
--              ZZ5000  CC20 / DEPT-SALES  150 Dr
--              ZZ1000  '' / ''            250 Cr      (balanced)
--
-- The basis is 'Period movement' ON PURPOSE. At the 7a-1 commit the dimensions
-- travel on the row but the differencing partitions are NOT widened, and a
-- period-movement file is the one basis that does not difference — so
-- assert_tb_movements_balance and assert_tb_movements_cumulate_to_source pass
-- here while the values are provably present. konsol#255 row 7a-2 reuses this
-- fixture with a differencing basis to make the un-widened partition fail.
--
-- The live tables may predate these columns: add them to the scratch clone
-- first (same guard the other fixtures use for amount_basis).
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_business_unit String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_business_unit, dim_cost_center, dim_department)
VALUES
  ('ZZDM1', 'ZZDM', 2026, 1, 'ZZ5000', 300, 0, 'Rent', 'ZZ-DIM-TBS-1', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDM1', 'ZZDM', 2026, 1, 'ZZ5000', 200, 0, 'Rent', 'ZZ-DIM-TBS-1', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDM1', 'ZZDM', 2026, 1, 'ZZ1000', 0, 500, 'Cash', 'ZZ-DIM-TBS-1', now(), '', '', '', ''),
  ('ZZDM2', 'ZZDM', 2026, 2, 'ZZ5000', 100, 0, 'Rent', 'ZZ-DIM-TBS-2', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDM2', 'ZZDM', 2026, 2, 'ZZ5000', 150, 0, 'Rent', 'ZZ-DIM-TBS-2', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDM2', 'ZZDM', 2026, 2, 'ZZ1000', 0, 250, 'Cash', 'ZZ-DIM-TBS-2', now(), '', '', '', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZDM1', 'ZZ-DIM-TBS-1', 'ZZDM', 2026, 1, 3, now(), 'Period movement'),
  ('ZZDM2', 'ZZ-DIM-TBS-2', 'ZZDM', 2026, 2, 3, now(), 'Period movement');
