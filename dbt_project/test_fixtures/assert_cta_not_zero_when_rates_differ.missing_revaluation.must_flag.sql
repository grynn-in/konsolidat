-- assert_cta_not_zero_when_rates_differ: must FAIL with exactly 1 result (konsolidat#249).
--
-- ZZMS: two translation rates were used (closing 1.2, average 1.1), and gold_fx_revaluation
--       has NO row for it at all. The test reaches it through a LEFT JOIN, and under
--       join_use_nulls = 0 the unmatched fx.cta_amount is 0, not NULL: coalesce(.., 0) = 0
--       holds either way, so ZZMS must be flagged. This is the join-default path the
--       existing must_flag fixture (a row present with cta_amount 0) does not exercise.
-- ZZOK: the same two rates with a real CTA row (-10): not flagged.
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZMS', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.2, 120, 120, 0, ''),
  ('ZZG', 'ZZMS', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 0, 1, 0, '', '', '', -100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.1, -110, -110, 0, ''),
  ('ZZG', 'ZZOK', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.2, 120, 120, 0, ''),
  ('ZZG', 'ZZOK', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 0, 1, 0, '', '', '', -100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.1, -110, -110, 0, '');
INSERT INTO epm_gold.gold_fx_revaluation
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, reporting_currency, accounting_currency,
   adjustment_type, main_account, closing_rate, average_rate, cta_amount)
VALUES
  ('ZZG', 'ZZOK', 2026, 1, 'USD', 'EUR', 'CTA', 'CTA', 1.2, 1.1, -10);
