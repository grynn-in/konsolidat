-- gate: expect assert_every_translated_currency_has_a_governed_rate flag 1
-- assert_every_translated_currency_has_a_governed_rate (konsol#348 S4 W2, S4-Q1 c): must FLAG exactly
-- one key, 'missing'. A rate that exists only in a budget's Rate Set is no rate for the actuals.
--
-- One EUR entity (ZZE1) in a USD group (ZZG), 100% owned, FY2026 P1. Two Rate Sets: ZZACT (flagged
-- Is Actuals) and ZZBUD (a budget's). EUR->USD FY2026 P1 Closing and Average are approved in ZZBUD
-- ONLY. Before the rate tables carried rate_set the coverage test read every row and found the key
-- covered; the actuals consolidation would have translated at a budget rate. Now the test (and the
-- model's guard, the same governed_rate_gaps()) read the ZZACT set only, so the key is 'missing'.
--
-- Test mode: the gate creates every relation the test reads, empty, and loads these rows.
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZE1', 'EUR');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'USD');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
-- konsol#348 S4-Q7 (a): two Rate Sets; ZZACT is the one flagged Is Actuals.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZBUD', 'ZZ budget 2026', 0);
-- The live rate tables may predate konsol#348's rate_set: add it to the scratch clones first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
-- The only EUR->USD rates for the period, in the budget's set: nothing for the actuals.
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2026, 1, 'Closing', 1.10, 'ZZ-GER-2026-01-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.05, 'ZZ-GER-2026-01-BUD', 'ZZBUD');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, -100, 1);
