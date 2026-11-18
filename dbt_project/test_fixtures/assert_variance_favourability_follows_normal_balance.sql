-- assert_variance_favourability_follows_normal_balance: must PASS. Hand-computed rows on signed amounts (debit
-- positive), three states (konsol#348 S6 WB1, S6-Q4 a; BUD-7-a; konsolidat#214):
--   ZZ4000 revenue (chart: Credit), actual -1,200 against budget -1,000: more revenue, 'favourable'.
--   ZZ5000 costs (chart: Debit), actual 1,200 against budget 1,000: more cost, 'unfavourable'.
--   ZZ6000 costs (chart: Debit), actual 900 against budget 1,000: less cost, 'favourable'.
--   ZZ7000 revenue (chart: Credit), no budget: budget zero ("Unbudgeted is unfavourable", 22 Sep 2026), so
--   -50 against 0 is more revenue, 'favourable'.
--   ZZ6100 costs (chart: Debit), no budget: budget zero, 30 against 0 is more cost, 'unfavourable'.
--   ZZ1000 cash (balance sheet, is_pnl 0), actual 500 against budget 400: no direction, 'not_applicable'.
--   ZZ8000 other (chart: normal balance not declared), actual 100 against budget 200: no direction, 'not_applicable'.
--   ZZ9000 rent (chart: Debit), actual 700 against budget 700: zero variance, 'not_applicable' ("On budget" on
--   the statement; the warehouse column does not distinguish it).
--   ZZ4100 fees (chart: Credit), actual -800 against budget -1,000: less revenue, 'unfavourable'.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, normal_balance)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 'Debit'),
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
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 1, '', '', 'USD', -1200, -1000, -200, 20, 'favourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ5000', 'ZZ costs', 'Expense', 1, '', '', 'USD', 1200, 1000, 200, 20, 'unfavourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ6000', 'ZZ other costs', 'Expense', 1, '', '', 'USD', 900, 1000, -100, -10, 'favourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ7000', 'ZZ other revenue', 'Revenue', 1, '', '', 'USD', -50, NULL, -50, NULL, 'favourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ6100', 'ZZ unbudgeted costs', 'Expense', 1, '', '', 'USD', 30, NULL, 30, NULL, 'unfavourable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 0, '', '', 'USD', 500, 400, 100, 25, 'not_applicable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ8000', 'ZZ undeclared', 'Profit and loss', 1, '', '', 'USD', 100, 200, -100, -50, 'not_applicable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ9000', 'ZZ rent', 'Expense', 1, '', '', 'USD', 700, 700, 0, 0, 'not_applicable', 'ZZ_PLAN_2026'),
  ('ZZE1', 2026, 1, 'ZZ4100', 'ZZ fees', 'Revenue', 1, '', '', 'USD', -800, -1000, 200, -20, 'unfavourable', 'ZZ_PLAN_2026');
