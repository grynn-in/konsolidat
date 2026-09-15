-- ZZZM: a period whose file repeats the previous period's balances, so every movement is 0.
-- Its P&L rows still carry the average rate (1.1 != closing 1.2), but nothing was translated,
-- so a CTA of 0 is correct and must NOT be flagged (konsolidat#195 follow-up, live build 15 Sep).
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZZM', 2026, 2, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 0.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.2, 0, 0, 0, ''),
  ('ZZG', 'ZZZM', 2026, 2, 'ZZ4000', 'revenue', 'Revenue', 0, 1, 0, '', '', '', 0.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 1.1, 0, 0, 0, '');
INSERT INTO epm_gold.gold_fx_revaluation
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, reporting_currency, accounting_currency,
   adjustment_type, main_account, closing_rate, average_rate, cta_amount)
VALUES
  ('ZZG', 'ZZZM', 2026, 2, 'USD', 'EUR', 'CTA', 'CTA', 1.2, 1.1, 0);
