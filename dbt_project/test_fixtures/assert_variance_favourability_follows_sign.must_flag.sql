-- gate: expect assert_variance_favourability_follows_sign flag 6
-- assert_variance_favourability_follows_sign: must FLAG 6 (konsol#562 E + ii, Deepak Pai, 18 Nov 2026). The
-- same hand-computed rows as the PASS fixture, with six states wrong:
--   ZZ8000 (P&L, blank normal balance, 100 against 200) stored 'not_applicable', as the old gate read it;
--   ZZ9000 rent 700 against 700 stored 'not_applicable' where it is 'on_budget';
--   ZZ6100 unbudgeted costs 30 stored 'not_applicable' (no budget is budget zero, 22 Sep 2026);
--   ZZ4000 revenue -1,200 against -1,000 (more revenue) stored 'unfavourable';
--   ZZ5000 costs 1,200 against 1,000 (more cost) stored 'favourable';
--   ZZ1100 deposits, a balance-sheet account in the chart (is_pnl 0) that the model row mislabels is_pnl 1
--   and marks 'unfavourable' (PR #374 review m4): a test that read the model's own is_pnl would miss it.
-- The other rows are right and must not be named.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, normal_balance)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 'Debit'),
  ('ZZ1100', 'ZZ deposits', 'Asset', 'Asset', 0, 1, 'Debit'),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 'Credit'),
  ('ZZ4100', 'ZZ fees', 'Revenue', 'Revenue', 1, 0, 'Credit'),
  ('ZZ5000', 'ZZ costs', 'Expense', 'Expense', 1, 0, 'Debit'),
  ('ZZ6000', 'ZZ other costs', 'Expense', 'Expense', 1, 0, 'Debit'),
  ('ZZ6100', 'ZZ unbudgeted costs', 'Expense', 'Expense', 1, 0, 'Debit'),
  ('ZZ7000', 'ZZ other revenue', 'Revenue', 'Revenue', 1, 0, 'Credit'),
  ('ZZ8000', 'ZZ undeclared', 'Profit and loss', 'Profit and loss', 1, 0, ''),
  ('ZZ9000', 'ZZ rent', 'Expense', 'Expense', 1, 0, 'Debit');
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, currency, actual_amount, budget_amount, variance_abs, variance_pct, variance_favourability,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 1, '', '', 'USD', -1200, -1000, -200, 20, 'unfavourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ5000', 'ZZ costs', 'Expense', 1, '', '', 'USD', 1200, 1000, 200, 20, 'favourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ6000', 'ZZ other costs', 'Expense', 1, '', '', 'USD', 900, 1000, -100, -10, 'favourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ7000', 'ZZ other revenue', 'Revenue', 1, '', '', 'USD', -50, NULL, -50, NULL, 'favourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ6100', 'ZZ unbudgeted costs', 'Expense', 1, '', '', 'USD', 30, NULL, 30, NULL, 'not_applicable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 0, '', '', 'USD', 500, 400, 100, 25, 'not_applicable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ8000', 'ZZ undeclared', 'Profit and loss', 1, '', '', 'USD', 100, 200, -100, -50, 'not_applicable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ9000', 'ZZ rent', 'Expense', 1, '', '', 'USD', 700, 700, 0, 0, 'not_applicable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ4100', 'ZZ fees', 'Revenue', 1, '', '', 'USD', -800, -1000, 200, -20, 'unfavourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ1100', 'ZZ deposits', 'Asset', 1, '', '', 'USD', 500, 400, 100, 25, 'unfavourable', 'ZZ_PLAN_2026');
