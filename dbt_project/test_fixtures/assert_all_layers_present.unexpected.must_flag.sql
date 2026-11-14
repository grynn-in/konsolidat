-- gate: expect assert_all_layers_present flag 1
-- assert_all_layers_present: must FAIL with exactly 1 result: unexpected_layer ZZG topside (konsolidat#238-4).
-- The fully consolidated TB carries a topside layer for ZZG, but gold_consolidation_adjustments
-- holds only a reclassification line: a topside layer with no source.
-- konsol#117 pair 2 K2: the test also reads gold_nci_attribution_journal, a model table a live stack gets from its first dbt run.
-- No-op where it exists; seeded empty here: no group has an nci_attribution layer unless a fixture inserts one.
CREATE TABLE IF NOT EXISTS epm_gold.gold_nci_attribution_journal (consolidation_group String, data_area_id String, fiscal_year UInt16, fiscal_period UInt16, main_account String, account_name String, reporting_currency String, amount Float64, adjustment_type String, journal_id String, account_role String) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, 0, 100.00, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, 100, 100, 0, ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1500', 'ic receivable', 'Asset', 1, 0, 0, -100.00, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, -100, -100, 0, 'ZZE2');
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
   reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'x', 'USD', 1, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'x', 'USD', 1, 'cta', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'x', 'USD', 1, 'topside', '');
