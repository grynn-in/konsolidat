-- gate: expect assert_budget_entries_one_row_per_line flag 1
-- konsol#348 PR3 (A12; PR #360 review, finding 5): the test can fail. silver_budget_entries is seeded directly
-- (test mode: nothing is rebuilt) with recid 1 on two rows, the shape a fanned-out date spine leaves, and one
-- well-formed line (recid 2). Exactly 1 result: recid 1.
--
-- The live table may predate the column's name (the model wrote it as `btl.recid` until PR #360): add it to the
-- scratch clone first.
ALTER TABLE epm_silver.silver_budget_entries ADD COLUMN IF NOT EXISTS recid Int64;
INSERT INTO epm_silver.silver_budget_entries
  (recid, data_area_id, transaction_date, fiscal_year, fiscal_period, main_account, accounting_currency_amount, transaction_currency_amount, transaction_currency, budget_model_id, budget_transaction_code, budget_status, register_date, include_in_cash_flow)
VALUES
  (1, 'ZZE1', '2026-01-15', 2026, 1, 'ZZ4000', 1000, 1000, 'USD', 'ZZ_PLAN_2026', 'ZZ-BRE-10', 'Approved', '2026-01-10', 0),
  (1, 'ZZE1', '2026-01-15', 2026, 1, 'ZZ4000', 1000, 1000, 'USD', 'ZZ_PLAN_2026', 'ZZ-BRE-10', 'Approved', '2026-01-10', 0),
  (2, 'ZZE1', '2026-02-10', 2026, 2, 'ZZ4000', 500, 500, 'USD', 'ZZ_PLAN_2026', 'ZZ-BRE-10', 'Approved', '2026-01-10', 0);
