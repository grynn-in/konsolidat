-- assert_every_tb_entity_has_a_currency: must FAIL with exactly 3 results (konsolidat#249).
-- ZZE9: trial-balance rows, and no row in silver_entity_currencies at all.
-- ZZE8: a submitted batch only (bronze), and no currency row at all.
-- ZZE7: a currency row whose accounting_currency is blank.
-- ZZE1: trial-balance rows and a resolved currency: not flagged.
-- An unmatched LEFT JOIN would read '' for ZZE9 and ZZE8 under join_use_nulls = 0, so a
-- `where currency is null` form would miss both; the NOT IN form must name all three.
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl,
   dim_business_unit, dim_cost_center, dim_department, period_credit, period_debit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1),
  ('ZZE9', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1),
  ('ZZE7', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1);
INSERT INTO epm_bronze.bronze_trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description,
   partner_data_area_id, dim_business_unit, dim_cost_center, dim_department, submission_name, submitted_at,
   claimed_at, claimed_row_count, amount_basis)
VALUES
  ('ZZB8', 'ZZE8', 2026, 1, 'ZZ1000', 100, 0, '', '', '', '', '', 'ZZ-TBS-8', '2026-02-01 00:00:00', '2026-02-01 00:00:00', 1, 'Period movement');
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency, currency_source, governed_currency, erp_currency, in_konsol, in_erp)
VALUES
  ('ZZE1', 'USD', 'konsol', 'USD', '', 1, 0),
  ('ZZE7', '', 'konsol', '', '', 1, 0);
