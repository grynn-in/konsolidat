-- gate: build gold_trial_balance_by_partner gold_consolidated_trial_balance assert_equity_historical_rate_is_asof
-- assert_equity_historical_rate_is_asof, April-March fiscal year (konsolidat#171 step 2d, task 5a): must PASS
-- when the historical equity rate is read as-of the DECLARED period end, not the first of calendar month P.
--
-- One GBP entity (ZZE1) in one USD group (ZZGRP); ZZ3000 share capital declares fx_method = 'historical'.
-- The declared calendar is April-March: FY2026 P1 = 2025-04-01..2025-04-30 (build_date_from_year_period(2026, 1)
-- would say 2026-01-01, eight months late). Three tranches into USD under the owning group:
--   1.10 dated 2025-02-01   (before P1)
--   1.20 dated 2025-04-15   (INSIDE declared P1: the rate P1 must apply)
--   1.50 dated 2025-09-01   (after P1, in declared P6: must NOT apply to P1)
-- Read at 2026-01-01 the latest tranche is 1.50, a rate from the future of P1.
--
-- gold_entity_ownership is seeded, not built, with the declared period end as period_date.
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
  ('ZZGRP', 'ZZE1', 'ZZ Entity 1', 'USD');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZGRP', 'ZZE1', 2026, 1, '2025-04-30', 1, 'ZZGRP', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate, to_currency)
VALUES
  ('ZZGRP', 'ZZE1', 'ZZ3000', '2025-02-01', 1.10, 'USD'),
  ('ZZGRP', 'ZZE1', 'ZZ3000', '2025-04-15', 1.20, 'USD'),
  ('ZZGRP', 'ZZE1', 'ZZ3000', '2025-09-01', 1.50, 'USD');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open');
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
  ('USD', 'GBP', 2026, 1, 'Average', 1.28, 'ZZ-GER-USD-2026-01');
INSERT INTO epm_silver.silver_gl_entries
  (recid, data_area_id, accounting_date, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, debit_amount, credit_amount, partner_data_area_id, posting_layer)
VALUES
  (1, 'ZZE1', '2025-04-30', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, '', ''),
  (2, 'ZZE1', '2025-04-30', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 100, '', '');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 100, -100, 1);
