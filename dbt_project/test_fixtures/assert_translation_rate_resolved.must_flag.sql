-- assert_translation_rate_resolved: must FAIL with exactly 2 results.
-- ZZZ0: cross-currency row whose translation_rate collapsed to 0 (join miss under join_use_nulls=0).
-- ZZNL: cross-currency row whose translation_rate is NULL (escaped every rate branch).
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZZ0', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'EUR', 'USD', 1, 'full', 0, 0, NULL, 0, 0, 0, 0, ''),
  ('ZZG', 'ZZNL', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, NULL, NULL, NULL, NULL, '');
