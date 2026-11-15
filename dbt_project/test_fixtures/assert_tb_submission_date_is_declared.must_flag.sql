-- gate: expect assert_tb_submission_date_is_declared flag 1
-- konsolidat#189 PR3 (konsol#348, A10; PR #360 review, finding 1): the test can fail. silver_gl_entries and
-- this test compute the same join (declared_periods() on (fiscal_year, fiscal_period), reading start_date), so
-- a row the model BUILDS carries the declared date by construction and the plain fixture alone cannot tell a
-- working test from one that cannot fail. Here silver_gl_entries is seeded directly (test mode: nothing is
-- rebuilt) with a submission row dated by the retired calendar-month rule, and the test must name it. This
-- pins the test against a future model change that dates a submission any other way.
--
-- An April-March site: FY2026 P1 is declared 2025-04-01 .. 2025-04-30. The entity's two submission rows for
-- P1 are dated 2026-01-01 (the first day of calendar January, what the retired macro made of "P1"): 1 result,
-- the (entity, period) pair.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open');
INSERT INTO epm_silver.silver_gl_entries
  (recid, data_area_id, accounting_date, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, accounting_currency_amount, credit_amount, debit_amount, posting_type, description, journal_number, journal_category, document_number, document_date)
VALUES
  (-1, 'ZZE1', '2026-01-01', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 'Trial Balance Submission', 'ZZ cash', 'TBS-ZZB1', 'Trial Balance Submission', 'ZZ-TBS-1', '2026-01-01'),
  (-2, 'ZZE1', '2026-01-01', 2026, 1, 'ZZ3000', 'ZZ capital', 'Equity', 1, 0, -100, 100, 0, 'Trial Balance Submission', 'ZZ capital', 'TBS-ZZB1', 'Trial Balance Submission', 'ZZ-TBS-1', '2026-01-01');
