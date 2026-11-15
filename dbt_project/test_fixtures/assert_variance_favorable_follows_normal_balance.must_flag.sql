-- gate: expect assert_variance_favorable_follows_normal_balance flag 2
-- assert_variance_favorable_follows_normal_balance: must FLAG 2. The same hand-computed rows as the PASS fixture,
-- with two flags the wrong way round, as the retired rule set them: ZZ4000 revenue -1,200 against -1,000 (more
-- revenue) marked 0, and ZZ5000 costs 1,200 against 1,000 (more cost) marked 1. The other rows are right and must
-- not be named. The live variance table may predate `currency` (B8): add it to the scratch clone first.
ALTER TABLE epm_gold.gold_variance_analysis ADD COLUMN IF NOT EXISTS currency String;
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, normal_balance)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 'Debit'),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 'Credit'),
  ('ZZ5000', 'ZZ costs', 'Expense', 'Expense', 1, 0, 'Debit'),
  ('ZZ6000', 'ZZ other costs', 'Expense', 'Expense', 1, 0, 'Debit'),
  ('ZZ7000', 'ZZ other revenue', 'Revenue', 'Revenue', 1, 0, 'Credit'),
  ('ZZ8000', 'ZZ undeclared', 'Profit and loss', 'Profit and loss', 1, 0, '');
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, currency, actual_amount, budget_amount, variance_abs, variance_pct, variance_favorable,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 1, '', '', 'USD', -1200, -1000, -200, 20, 0, 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ5000', 'ZZ costs', 'Expense', 1, '', '', 'USD', 1200, 1000, 200, 20, 1, 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ6000', 'ZZ other costs', 'Expense', 1, '', '', 'USD', 900, 1000, -100, -10, 1, 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ7000', 'ZZ other revenue', 'Revenue', 1, '', '', 'USD', -50, NULL, -50, NULL, 0, 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 0, '', '', 'USD', 500, 400, 100, 25, 0, 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ8000', 'ZZ undeclared', 'Profit and loss', 1, '', '', 'USD', 100, 200, -100, -50, 0, 'ZZ_PLAN_2026');
