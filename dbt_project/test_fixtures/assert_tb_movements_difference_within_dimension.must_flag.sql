-- konsol#255 row 7a-2: a trial balance on a DIFFERENCING basis whose account is
-- split across two dimension values.
--
-- silver_tb_movements.dimensions.sql (row 7a-1) is the same shape on 'Period
-- movement' — the one basis that does not difference, which is why it passes.
-- This fixture is that fixture's differencing twin, on its own entity ZZDY so
-- the two can never be loaded together and collide on
-- assert_entity_has_one_amount_basis.
--
-- Basis 'Year-to-date movement'. One entity ZZDY, FY2026 periods 1 and 2. Both
-- accounts are split across TWO dimension values in the same
-- (entity, fiscal_year, fiscal_period, main_account, partner):
--
--   period 1 (YTD)   ZZ5000  CC10 / DEPT-OPS    300 Dr
--                    ZZ5000  CC20 / DEPT-SALES  300 Dr
--                    ZZ1000  CC10 / DEPT-OPS    300 Cr
--                    ZZ1000  CC20 / DEPT-SALES  300 Cr     (batch balances 600/600)
--   period 2 (YTD)   ZZ5000  CC10 / DEPT-OPS    500 Dr
--                    ZZ5000  CC20 / DEPT-SALES  500 Dr
--                    ZZ1000  CC10 / DEPT-OPS    500 Cr
--                    ZZ1000  CC20 / DEPT-SALES  500 Cr     (batch balances 1000/1000)
--
-- The true movements are 300 / 300 / -300 / -300 in period 1 and
-- 200 / 200 / -200 / -200 in period 2. The un-widened lagInFrame partition
-- walks both slices of an account as ONE series, so whichever slice the window
-- orders second is differenced against the first and comes out 0.
--
-- The two slices of each account carry EQUAL amounts on purpose. Nothing orders
-- two rows of the same period (the window's `order by` is fiscal_year,
-- fiscal_period), so which slice is differenced against which is arbitrary —
-- with equal amounts the wrongness is the same either way, and so is the
-- fixture's evidence. The second account mirrors the first, so each period's
-- error cancels across accounts and the entity-period still sums to zero:
-- assert_tb_movements_balance passes on this data, and
-- assert_tb_movements_cumulate_to_source passes because its running sums are
-- keyed on the same un-widened (entity, account, partner) as the defect.
-- assert_tb_movements_difference_within_dimension is the one that must flag.
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
  ('ZZDY1', 'ZZDY', 2026, 1, 'ZZ5000', 300, 0, 'Rent', 'ZZ-DIM-YTD-1', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDY1', 'ZZDY', 2026, 1, 'ZZ5000', 300, 0, 'Rent', 'ZZ-DIM-YTD-1', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDY1', 'ZZDY', 2026, 1, 'ZZ1000', 0, 300, 'Cash', 'ZZ-DIM-YTD-1', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDY1', 'ZZDY', 2026, 1, 'ZZ1000', 0, 300, 'Cash', 'ZZ-DIM-YTD-1', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDY2', 'ZZDY', 2026, 2, 'ZZ5000', 500, 0, 'Rent', 'ZZ-DIM-YTD-2', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDY2', 'ZZDY', 2026, 2, 'ZZ5000', 500, 0, 'Rent', 'ZZ-DIM-YTD-2', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDY2', 'ZZDY', 2026, 2, 'ZZ1000', 0, 500, 'Cash', 'ZZ-DIM-YTD-2', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDY2', 'ZZDY', 2026, 2, 'ZZ1000', 0, 500, 'Cash', 'ZZ-DIM-YTD-2', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZDY1', 'ZZ-DIM-YTD-1', 'ZZDY', 2026, 1, 4, now(), 'Year-to-date movement'),
  ('ZZDY2', 'ZZ-DIM-YTD-2', 'ZZDY', 2026, 2, 4, now(), 'Year-to-date movement');
