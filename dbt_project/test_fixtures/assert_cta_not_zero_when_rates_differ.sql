-- Fixture for assert_cta_not_zero_when_rates_differ: the test must PASS on these rows.
--
-- ZZBS: balance-sheet-only entity (EUR -> USD, closing 1.2, average 1.1). Every row
--       translated at the closing rate, so CTA is 0 by construction. Must NOT be flagged
--       even though closing and average rates differ (konsolidat#195).
-- ZZOK: balance-sheet row at closing (1.2) plus a P&L row at average (1.1); the residual
--       CTA is -10, so the test has nothing to flag.
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZBS', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.2, 120, 120, 0, ''),
  ('ZZG', 'ZZBS', 2026, 1, 'ZZ2000', 'payables', 'Liability', 1, 0, 0, '', '', '', -100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.2, -120, -120, 0, ''),
  ('ZZG', 'ZZOK', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.2, 120, 120, 0, ''),
  ('ZZG', 'ZZOK', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 0, 1, 0, '', '', '', -100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.1, -110, -110, 0, '');
INSERT INTO epm_gold.gold_fx_revaluation
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, reporting_currency, accounting_currency,
   adjustment_type, main_account, closing_rate, average_rate, cta_amount)
VALUES
  ('ZZG', 'ZZBS', 2026, 1, 'USD', 'EUR', 'CTA', 'CTA', 1.2, 1.1, 0),
  ('ZZG', 'ZZOK', 2026, 1, 'USD', 'EUR', 'CTA', 'CTA', 1.2, 1.1, -10);
