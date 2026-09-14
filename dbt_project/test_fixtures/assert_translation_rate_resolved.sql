-- assert_translation_rate_resolved: must PASS.
-- One cross-currency row (CAD -> USD) whose approved closing rate is exactly 1.0.
-- Near-parity pairs are quoted to 3 decimals, so 1.000 is a legitimate approved
-- rate, not a sign of a missing quote (the model has no parity fallback; a
-- missing rate stops the build before this test runs).
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZCA', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'CAD', 'USD', 1, 'full', 1.0, 1.0, NULL, 1.0, 100, 100, 0, '');
