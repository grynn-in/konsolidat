-- gate: build silver_budget_entries assert_budget_entries_one_row_per_line
-- gate: expect assert_budget_entries_one_row_per_line pass
-- konsol#348 PR3 (A12; PR #360 review, finding 5): must PASS once silver_budget_entries groups the declared
-- calendar per (fiscal_year, fiscal_period) before spinning its dates out. The calendar declares FY2026 P1 on
-- TWO identical rows (loaded twice). One ERP budget line (recid 1) is dated 2026-01-15, inside P1. Red on the
-- ungrouped spine: 2026-01-15 appears twice, the line comes out twice, and the test flags recid 1 (FAIL 1).
--
-- The bronze budget tables are seeded (the selector does not rebuild them); the register entry is Approved so
-- the line passes the model's status filter.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open');
INSERT INTO epm_bronze.bronze_budget_register_entries
  (recid, data_area_id, budget_model_id, budget_transaction_code, reason_comment, budget_status, document_date)
VALUES
  (10, 'ZZE1', 'ZZ_PLAN_2026', 'ZZ-BRE-10', '', 'Approved', '2026-01-10');
INSERT INTO epm_bronze.bronze_budget_transaction_lines
  (recid, budget_register_entry_recid, transaction_date, main_account, accounting_currency_amount, transaction_currency_amount, transaction_currency, dim_cost_center, dim_department, include_in_cash_flow)
VALUES
  (1, 10, '2026-01-15', 'ZZ4000', 1000, 1000, 'USD', 'ZZ_CC1', 'ZZ_D1', 0);
