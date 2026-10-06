-- assert_year_end_close_carries_no_cta (konsolidat#259): must FLAG (warn), before and after the fix.
--
-- Seeds gold_consolidated_trial_balance and gold_fx_revaluation as the pre-#259 translation
-- produced them, and runs the test alone:
--   gate-x.sh <wt> dbt_project/test_fixtures/assert_year_end_close_carries_no_cta.must_flag.sql \
--     "assert_year_end_close_carries_no_cta"
--
-- EUR entities in ZZG (USD); FY2025 P12 (average 1.10, closing 1.20), P13 Closing (P12's rates).
-- Each has revenue -100 at P12 (-110 translated) and cash +100.
--   ZZE1 synthesized close (posting_layer 'Year-end close'): reversal +110, RE at closing -120
--        -> P13 CTA +10. NAMED (year_end_close).
--   ZZE3 ERP-posted close (the same rows, no 'Year-end close' layer): P13 CTA +10.
--        NAMED (erp_posted_close).
--   ZZE4 synthesized close translated as #259-1 wants: reversal +110, RE -110 -> CTA 0. Not named.
-- Expected: WARN 2.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', 'Q4', 'Open');
INSERT INTO epm_silver.silver_gl_entries
  (recid, data_area_id, accounting_date, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, debit_amount, credit_amount, partner_data_area_id, posting_layer)
VALUES
  (1, 'ZZE1', '2025-12-31', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 100, 0, '', 'Year-end close'),
  (2, 'ZZE1', '2025-12-31', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 100, '', 'Year-end close'),
  (3, 'ZZE3', '2025-12-31', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 100, 0, '', ''),
  (4, 'ZZE3', '2025-12-31', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 100, '', ''),
  (5, 'ZZE4', '2025-12-31', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 100, 0, '', 'Year-end close'),
  (6, 'ZZE4', '2025-12-31', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 100, '', 'Year-end close');
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, local_amount, accounting_currency, reporting_currency, ownership_pct,
   consolidation_method, closing_rate, average_rate, historical_equity_rate, translation_rate, translated_amount,
   group_amount, nci_amount, partner_data_area_id, uses_historical_rate)
VALUES
  ('ZZG', 'ZZE1', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 0, 100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.20, 120, 120, 0, '', 0),
  ('ZZG', 'ZZE1', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, -100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.10, -110, -110, 0, '', 0),
  ('ZZG', 'ZZE1', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.10, 110, 110, 0, '', 0),
  ('ZZG', 'ZZE1', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 1, -100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.20, -120, -120, 0, '', 0),
  ('ZZG', 'ZZE3', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 0, 100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.20, 120, 120, 0, '', 0),
  ('ZZG', 'ZZE3', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, -100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.10, -110, -110, 0, '', 0),
  ('ZZG', 'ZZE3', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.10, 110, 110, 0, '', 0),
  ('ZZG', 'ZZE3', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 1, -100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.20, -120, -120, 0, '', 0),
  ('ZZG', 'ZZE4', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 0, 100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.20, 120, 120, 0, '', 0),
  ('ZZG', 'ZZE4', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, -100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.10, -110, -110, 0, '', 0),
  ('ZZG', 'ZZE4', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.10, 110, 110, 0, '', 0),
  ('ZZG', 'ZZE4', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 1, -100, 'EUR', 'USD', 1, 'full', 1.20, 1.10, NULL, 1.10, -110, -110, 0, '', 0);
INSERT INTO epm_gold.gold_fx_revaluation
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, reporting_currency, accounting_currency, adjustment_type, main_account, closing_rate, average_rate, cta_amount)
VALUES
  ('ZZG', 'ZZE1', 2025, 12, 'USD', 'EUR', 'CTA', 'CTA', 1.20, 1.10, -10),
  ('ZZG', 'ZZE1', 2025, 13, 'USD', 'EUR', 'CTA', 'CTA', 1.20, 1.10, 10),
  ('ZZG', 'ZZE3', 2025, 12, 'USD', 'EUR', 'CTA', 'CTA', 1.20, 1.10, -10),
  ('ZZG', 'ZZE3', 2025, 13, 'USD', 'EUR', 'CTA', 'CTA', 1.20, 1.10, 10),
  ('ZZG', 'ZZE4', 2025, 12, 'USD', 'EUR', 'CTA', 'CTA', 1.20, 1.10, -10),
  ('ZZG', 'ZZE4', 2025, 13, 'USD', 'EUR', 'CTA', 'CTA', 1.20, 1.10, 0);
