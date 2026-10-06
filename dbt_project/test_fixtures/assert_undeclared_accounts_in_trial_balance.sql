-- assert_undeclared_accounts_in_trial_balance: must PASS. Every posted account is declared.
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl,
   dim_business_unit, dim_cost_center, dim_department, period_credit, period_debit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'share capital', 'Equity', 1, 0, '', '', '', 100, 0, -100, 1);
INSERT INTO epm_silver.silver_main_accounts (main_account_id, account_name, chart_of_accounts, is_balance_sheet)
VALUES ('ZZ1000', 'cash', 'ZZCOA', 1), ('ZZ3000', 'share capital', 'ZZCOA', 1);
