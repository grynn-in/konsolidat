-- gate: expect assert_group_equals_translated_times_share_for_proportional flag 1
-- assert_group_equals_translated_times_share_for_proportional: must FAIL with exactly 1 result: group_amount 1,000 on a proportional row at 0.5 (expected 500) (konsol#117 pair 3, IFRS 11.20).
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZJ', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 1000.00, 'USD', 'USD', 0.5, 'proportional', 1, 1, NULL, 1, 1000, 1000, -500, '');
