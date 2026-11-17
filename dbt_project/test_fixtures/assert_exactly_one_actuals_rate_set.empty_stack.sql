-- gate: build gold_ownership_exits gold_consolidated_trial_balance assert_exactly_one_actuals_rate_set
-- gate: expect gold_consolidated_trial_balance built
-- gate: expect assert_exactly_one_actuals_rate_set pass
-- The fresh stack (review of konsolidat#365, 15 Nov 2026): konsol has synced its structure (a chart,
-- an entity, a group, the calendar, a currency) but no trial balance has been submitted and
-- reconcile_all, an RQ job, has not filled epm_staging.rate_sets yet. The first dbt build must go
-- through: the consolidated trial balance builds (empty) and assert_exactly_one_actuals_rate_set
-- PASSES, because with no row in epm_gold.gold_trial_balance nothing is translated and nothing a
-- silent merge of two sets, or no set, could affect. The first TB row brings the count rule in
-- (.none.must_flag, .two.must_flag, .guard_refuses.must_flag).
--
-- epm_gold.gold_trial_balance and epm_staging.rate_sets are named here so the gate creates them,
-- EMPTY; neither is inserted into. The model's rate tables are named so the gate creates them too:
-- epm_staging.group_exchange_rates, epm_staging.historical_equity_rates (ALTERed below to the
-- current shape, as the other build fixtures do, since a live clone may predate the columns).
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZE1', 'EUR');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'EUR');
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
  ('USD', 'US Dollar', '$', 2, 0),
  ('EUR', 'Euro', 'E', 2, 0.04);
-- The live tables may predate konsol#348's rate_set and konsolidat#259's close flag: add them to the
-- scratch clones first, as the other build fixtures do.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS rate_set String;
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
-- No INSERT into epm_gold.gold_trial_balance, epm_gold.gold_trial_balance_by_partner or
-- epm_staging.rate_sets: the stack has no figures and no Rate Set yet.
