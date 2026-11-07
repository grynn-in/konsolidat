-- gate: build gold_trial_balance_by_partner gold_consolidated_trial_balance assert_equity_historical_rate_is_asof
-- assert_equity_historical_rate_is_asof (konsol#374, option b; Deepak Pai, 7 Nov 2026): must PASS once a
-- Historical Equity Rate is matched on the consolidating group's reporting currency.
--
-- One GBP entity (ZZE1) owned 100% by a sub-group that presents in EUR (ZZSUB), which is owned 100%
-- by a parent that presents in USD (ZZGRP). Both groups consolidate ZZE1, both translate it (GBP is
-- neither group's currency), and ZZ3000 share capital declares fx_method = 'historical'. Two rates are
-- recorded under the OWNING group ZZSUB for the same entity and account, one per presentation currency:
--   GBP -> USD 1.20 dated 2024-01-01   (what ZZGRP must apply)
--   GBP -> EUR 1.10 dated 2025-06-01   (what ZZSUB must apply)
-- Period FY2026 P1 (period_date 2026-01-01), so both tranches are eligible as-of the period.
--
-- Before konsol#374 the ASOF join keyed (owner_group, entity, account) only, so the two rates were ONE
-- as-of series and the later tranche (EUR 1.10) won at both levels: ZZGRP's USD statements carried a
-- GBP->EUR rate. The test, which resolves the expected rate on the row's reporting currency, flags that
-- row; after the join gains `eo.reporting_currency = hr.to_currency`, each group gets its own rate.
--
-- gold_entity_ownership is seeded, not built (it is not in the selector), so owner_group is ZZSUB at
-- both levels as the tree walk would make it. gold_trial_balance is seeded for the rate guard
-- (pre_hook), and silver_gl_entries for gold_trial_balance_by_partner.
--
-- The live table may predate to_currency: add it to the scratch clone first.
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ share capital', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 0, 1);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZE1', 'GBP');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZGRP', '', 'ZZ Group', 'USD'),
  ('ZZSUB', '', 'ZZ Sub-group', 'EUR'),
  ('ZZSUB', 'ZZE1', 'ZZ Entity 1', 'EUR');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZGRP', 'ZZE1', 2026, 1, '2026-01-31', 2, 'ZZSUB', 1, 0, 1.0, 1.0, 'full'),
  ('ZZSUB', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZSUB', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate, to_currency)
VALUES
  ('ZZSUB', 'ZZE1', 'ZZ3000', '2024-01-01', 1.20, 'USD'),
  ('ZZSUB', 'ZZE1', 'ZZ3000', '2025-06-01', 1.10, 'EUR');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
-- usd_log10: USD is 0 by definition; the others carry a real non-zero value (macros/fx_magnitude.sql).
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('GBP', 'Pound sterling', 'L', 2, -0.10),
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'GBP', 2026, 1, 'Closing', 1.30, 'ZZ-GER-USD-2026-01'),
  ('USD', 'GBP', 2026, 1, 'Average', 1.28, 'ZZ-GER-USD-2026-01'),
  ('EUR', 'GBP', 2026, 1, 'Closing', 1.15, 'ZZ-GER-EUR-2026-01'),
  ('EUR', 'GBP', 2026, 1, 'Average', 1.14, 'ZZ-GER-EUR-2026-01');
INSERT INTO epm_silver.silver_gl_entries
  (recid, data_area_id, accounting_date, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, debit_amount, credit_amount, partner_data_area_id, posting_layer)
VALUES
  (1, 'ZZE1', '2026-01-31', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, '', ''),
  (2, 'ZZE1', '2026-01-31', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 100, '', '');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 100, -100, 1);
