-- assert_all_layers_present: must FAIL with exactly 1 result: ZZG / cta (konsolidat#238-1).
-- ZZG's entities carry two functional currencies (ZZE1 USD, ZZE2 EUR), and the fully
-- consolidated TB has no cta row. No partner rows and no topside line.
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, 100, 100, 0, ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1500', 'ic receivable', 'Asset', 1, 0, 0, '', '', '', -100.00, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, -100, -100, 0, ''),
  ('ZZG', 'ZZE2', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.2, NULL, 1.2, 100, 100, 0, ''),
  ('ZZG', 'ZZE2', 2026, 1, 'ZZ1500', 'ic receivable', 'Asset', 1, 0, 0, '', '', '', -100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.2, NULL, 1.2, -100, -100, 0, '');
INSERT INTO epm_staging.intercompany_accounts (main_account, counterpart_account, description, status)
VALUES ('ZZ1500', '', 'ZZ intercompany', 'Published');
INSERT INTO epm_gold.gold_consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account,
   debit_amount, credit_amount, net_amount, description, status)
VALUES
  ('ZZG', 'reclassification', 'ZZJ-reclassification', 'ZZE1', 2026, 1, 'ZZ1000', 10, 0, 10, 'ZZ reclassification', 'Approved');
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_business_unit, dim_cost_center, dim_department, reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'x', '', '', '', 'USD', 1, 'entity', '');
