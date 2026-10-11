-- assert_staging_not_stale: must PASS (konsolidat#246). A site no reconcile has stamped a run id on
-- yet: konsol has just added the column, and the 27 rows are the old stamps, two of them 60h newer
-- than the rest (the live watermark on 11 Oct 2026). Nothing can be LAGGING without a run, and
-- NO_RECONCILE_RUN waits watermark_lag_hours from the column's arrival (this table is minutes old).
-- The old rule flagged 25 rows here.
-- gate: expect assert_staging_not_stale pass
-- A stack where konsol has not added the column yet (README: a fixture may add one).
ALTER TABLE epm_staging.sync_watermark ADD COLUMN IF NOT EXISTS reconcile_run_id String;
INSERT INTO epm_staging.sync_watermark
  (table_name, synced_at, row_count, source_max_modified, reconcile_run_id)
VALUES
  ('epm_staging.consolidation_hierarchy', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.group_exchange_rates', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.entities', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.ic_balances', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_gold.consolidation_groups', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.fiscal_periods', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.ownership_periods', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.historical_equity_rates', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.consolidation_ancestry', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.consolidation_adjustments', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_gold.currencies', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.reporting_hierarchies', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.business_combinations', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.dimension_mappings', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_gold.budget_annual_input', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.business_combination_acquired_balances', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.ic_elimination_rules', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_gold.entity_fiscal_calendars', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.business_disposals', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.business_combination_costs', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.cash_flow_categories', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.business_disposal_proceeds', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_gold.scenario_definitions', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_gold.spread_profiles', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.business_combination_consideration', '2026-10-07 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.intercompany_accounts', '2026-10-09 21:40:54', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.main_accounts', '2026-10-09 21:40:54', 0, '1970-01-01 00:00:00', '');
