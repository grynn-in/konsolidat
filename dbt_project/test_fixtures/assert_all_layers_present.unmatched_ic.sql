-- assert_all_layers_present: must PASS (konsolidat#238-4). The review's scenario: ZZE1 books the declared IC
-- account ZZ1500 against ZZE2, a member of ZZG that books nothing back on ZZ2500, and the group has no ic_difference_account.
-- gold_ic_reconciliation matches 0, so gold_ic_eliminations has no rows, and the fully consolidated
-- TB rightly has no ic_elimination layer. Whether it should have been eliminated is
-- gold_ic_unmatched's question, not this test's.
INSERT INTO epm_staging.intercompany_accounts (main_account, counterpart_account, description, status)
VALUES ('ZZ1500', 'ZZ2500', 'ZZ intercompany', 'Published');
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_business_unit, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 100.00, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, 100, 100, 0, ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1500', 'ic receivable', 'Asset', 1, 0, 0, '', '', '', -100.00, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, -100, -100, 0, 'ZZE2'),
  ('ZZG', 'ZZE2', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, '', '', '', 0.00, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, 0, 0, 0, '');
ALTER TABLE epm_gold.gold_ic_eliminations ADD COLUMN IF NOT EXISTS rule_id String;
INSERT INTO epm_gold.gold_consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account,
   debit_amount, credit_amount, net_amount, description, status)
VALUES ('ZZG', 'reclassification', 'ZZJ1', 'ZZE1', 2026, 1, 'ZZ1000', 10, 0, 10, 'ZZ reclassification', 'Approved');
INSERT INTO epm_gold.gold_fx_revaluation
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, reporting_currency, accounting_currency,
   adjustment_type, main_account, closing_rate, average_rate, cta_amount)
VALUES ('ZZG', 'ZZE1', 2026, 1, 'USD', 'USD', 'CTA', 'CTA', 1, 1, 0);
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_business_unit, dim_cost_center, dim_department, reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'x', '', '', '', 'USD', 1, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'x', '', '', '', 'USD', 1, 'cta', '');
