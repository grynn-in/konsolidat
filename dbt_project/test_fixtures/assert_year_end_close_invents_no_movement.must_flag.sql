-- konsol#255 row 14: a 'Period-end balance' entity that crosses a year end AND
-- splits balance-sheet accounts across declared dimension values.
--
-- silver_tb_movements.year_end_close.sql is the same shape with no dimensions
-- anywhere; this is its dimensioned twin, on its own entity ZZDK and its own
-- chart ZZKCOA so the two can never collide on assert_entity_has_one_amount_basis
-- or on the "exactly one retained-earnings account" rule.
--
--   FY2024 P12 (period-end balances)
--     ZZ1000  CC10 / DEPT-OPS      60 Dr      ZZ1000  CC20 / DEPT-SALES   40 Dr
--     ZZ2000  CC10 / DEPT-OPS      60 Cr      ZZ2000  CC20 / DEPT-SALES   40 Cr
--     ZZ1010  '' / ''              50 Dr
--     ZZ4000  '' / ''              80 Cr      ZZ5000  '' / ''             30 Dr
--     (Dr 180 / Cr 180; the year's result is a profit of 50)
--
--   FY2025 P1 (period-end balances, P&L reset, result moved to ZZ3100)
--     ZZ1000  CC10 / DEPT-OPS      60 Dr      ZZ1000  CC20 / DEPT-SALES   40 Dr
--     ZZ2000  CC10 / DEPT-OPS      60 Cr      ZZ2000  CC20 / DEPT-SALES   40 Cr
--     ZZ1010  '' / ''              50 Dr      ZZ3100  '' / ''             50 Cr
--     (Dr 150 / Cr 150; NOTHING moved on ZZ1000 or ZZ2000 between the two files)
--
-- The entity never claims FY2024 P13, and the calendar declares it 'Closing', so
-- the model synthesises the close there.
--
-- What a correct close posts at FY2024 P13: ZZ4000 +80, ZZ5000 -30, ZZ3100 -50,
-- and NOTHING on ZZ1000, ZZ1010 or ZZ2000 — those balances are carried, so they
-- difference to 0 and are dropped. ZZ1000's cumulative movement through FY2025 P1
-- is then 100, the balance both files state.
--
-- MEASURED at row 14, and the finding: the close row was computed on the
-- UN-WIDENED key (its whole 100 summed back across both dimension values) but
-- carried BLANK dimension values, so row 7b's widened lagInFrame differenced it
-- against the blank SLICE of ZZ1000 — which does not exist, so 0. The close
-- emitted
--     2024 13  ZZ1000  ''  source 100  movement +100  year_end_close
--     2024 13  ZZ2000  ''  source -100 movement -100  year_end_close
-- out of nothing, and ZZ1000 cumulated to 200 against a stated balance of 100.
-- ZZ1010 (blank-dimensioned, same shape otherwise) differenced to 0 and was
-- dropped, exactly as it should — the split was the whole trigger.
--
-- MEASURED at row 17, after the close was put on the same widened key: FY2024
-- P13 carries ZZ3100 -50, ZZ4000 +80, ZZ5000 -30 and NOTHING ELSE; ZZ1000
-- cumulates to 60 + 40 = 100 and ZZ2000 to -100, the balances both files state;
-- FY2025 P1 has no movement on any key. All 28 nodes pass.
--
-- Why this fixture needed a test of its own. The two invented rows were equal
-- and opposite BY CONSTRUCTION of the source file (every split asset slice has
-- a matching split liability slice), so the entity-period still summed to zero
-- and assert_tb_movements_balance could not see it.
-- assert_tb_movements_cumulate_to_source runs its running sums on the full key
-- and each invented row was the only row of its blank slice, so its running sum
-- equalled its own source figure — green.
-- assert_tb_movements_difference_within_dimension excludes 'year_end_close' rows
-- by design. All three were measured PASS on this fixture while it was red, and
-- assert_year_end_close_invents_no_movement was the only one that flagged, with
-- 2 rows. That is why it exists, and why it is the one to keep watching.
--
-- The live tables may predate these columns: add them to the scratch clone first
-- (same guard the other fixtures use for amount_basis).
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_business_unit String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZKCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ1010', 'ZZ restricted cash', 'ZZKCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'CASH', 'Published', 0),
  ('ZZ2000', 'ZZ short-term debt', 'ZZKCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'DEBT', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZKCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4000', 'ZZ revenue', 'ZZKCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5000', 'ZZ cost of sales', 'ZZKCOA', '', 0, 'Expense', 'Profit and Loss', 'Cost of Sales', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'COGS', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2024, 12, 'FY2024-P12', 'Dec 2024', 'Regular', '2024-12-01', '2024-12-31', 'Q4', 'Open'),
  (2024, 13, 'FY2024-P13', 'FY2024 closing', 'Closing', '2024-12-31', '2024-12-31', 'Q4', 'Open'),
  (2025, 1, 'FY2025-P01', 'Jan 2025', 'Regular', '2025-01-01', '2025-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_business_unit, dim_cost_center, dim_department)
VALUES
  ('ZZDK1', 'ZZDK', 2024, 12, 'ZZ1000', 60, 0, 'Cash', 'ZZ-DIMCLOSE-1', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDK1', 'ZZDK', 2024, 12, 'ZZ1000', 40, 0, 'Cash', 'ZZ-DIMCLOSE-1', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDK1', 'ZZDK', 2024, 12, 'ZZ2000', 0, 60, 'Short-term debt', 'ZZ-DIMCLOSE-1', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDK1', 'ZZDK', 2024, 12, 'ZZ2000', 0, 40, 'Short-term debt', 'ZZ-DIMCLOSE-1', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDK1', 'ZZDK', 2024, 12, 'ZZ1010', 50, 0, 'Restricted cash', 'ZZ-DIMCLOSE-1', now(), '', '', '', ''),
  ('ZZDK1', 'ZZDK', 2024, 12, 'ZZ4000', 0, 80, 'Sales', 'ZZ-DIMCLOSE-1', now(), '', '', '', ''),
  ('ZZDK1', 'ZZDK', 2024, 12, 'ZZ5000', 30, 0, 'Cost of sales', 'ZZ-DIMCLOSE-1', now(), '', '', '', ''),
  ('ZZDK2', 'ZZDK', 2025, 1, 'ZZ1000', 60, 0, 'Cash', 'ZZ-DIMCLOSE-2', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDK2', 'ZZDK', 2025, 1, 'ZZ1000', 40, 0, 'Cash', 'ZZ-DIMCLOSE-2', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDK2', 'ZZDK', 2025, 1, 'ZZ2000', 0, 60, 'Short-term debt', 'ZZ-DIMCLOSE-2', now(), '', 'BU-NORTH', 'CC10', 'DEPT-OPS'),
  ('ZZDK2', 'ZZDK', 2025, 1, 'ZZ2000', 0, 40, 'Short-term debt', 'ZZ-DIMCLOSE-2', now(), '', 'BU-NORTH', 'CC20', 'DEPT-SALES'),
  ('ZZDK2', 'ZZDK', 2025, 1, 'ZZ1010', 50, 0, 'Restricted cash', 'ZZ-DIMCLOSE-2', now(), '', '', '', ''),
  ('ZZDK2', 'ZZDK', 2025, 1, 'ZZ3100', 0, 50, 'Retained earnings', 'ZZ-DIMCLOSE-2', now(), '', '', '', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZDK1', 'ZZ-DIMCLOSE-1', 'ZZDK', 2024, 12, 7, now(), 'Period-end balance'),
  ('ZZDK2', 'ZZ-DIMCLOSE-2', 'ZZDK', 2025, 1, 6, now(), 'Period-end balance');
