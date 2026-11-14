-- assert_staging_not_stale: must PASS (konsolidat#246, option #246-1). The measured false positive:
-- a full reconcile stamps all 27 write-through tables with one run id, then one Reporting Hierarchy
-- publish (a write-through, run id '') stamps reporting_hierarchies 89h later. The old rule
-- (lag behind the newest stamp > 24h) flagged the 26 untouched tables; every table is in the
-- latest run, so nothing is LAGGING.
-- gate: expect assert_staging_not_stale pass
-- A stack where konsol has not added the column yet (README: a fixture may add one).
ALTER TABLE epm_staging.sync_watermark ADD COLUMN IF NOT EXISTS reconcile_run_id String;
INSERT INTO epm_staging.sync_watermark
  (table_name, synced_at, row_count, source_max_modified, reconcile_run_id)
VALUES
  ('epm_staging.consolidation_hierarchy', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.group_exchange_rates', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.entities', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.ic_balances', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.consolidation_groups', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.fiscal_periods', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.ownership_periods', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.historical_equity_rates', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.consolidation_ancestry', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.consolidation_adjustments', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.currencies', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.reporting_hierarchies', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.business_combinations', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.dimension_mappings', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.budget_annual_input', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.business_combination_acquired_balances', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.ic_elimination_rules', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.entity_fiscal_calendars', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.business_disposals', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.business_combination_costs', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.cash_flow_categories', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.business_disposal_proceeds', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.scenario_definitions', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.spread_profiles', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.business_combination_consideration', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.intercompany_accounts', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.main_accounts', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.reporting_hierarchies', '2026-10-08 02:24:13', 0, '1970-01-01 00:00:00', '');
