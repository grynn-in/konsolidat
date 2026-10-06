-- assert_every_tb_entity_has_a_currency: must PASS. Every entity with trial-balance or
-- submitted rows resolves a currency.
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl,
   dim_business_unit, dim_cost_center, dim_department, period_credit, period_debit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1);
INSERT INTO epm_bronze.bronze_trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description,
   partner_data_area_id, dim_business_unit, dim_cost_center, dim_department, submission_name, submitted_at,
   claimed_at, claimed_row_count, amount_basis)
VALUES
  ('ZZB2', 'ZZE2', 2026, 1, 'ZZ1000', 100, 0, '', '', '', '', '', 'ZZ-TBS-2', '2026-02-01 00:00:00', '2026-02-01 00:00:00', 1, 'Period movement');
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency, currency_source, governed_currency, erp_currency, in_konsol, in_erp)
VALUES
  ('ZZE1', 'USD', 'konsol', 'USD', '', 1, 0),
  ('ZZE2', 'EUR', 'konsol', 'EUR', '', 1, 0);
