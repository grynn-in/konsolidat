-- assert_staging_not_stale: must PASS. epm_raw.budget_entries is a write-through table (konsol Budget Entry
-- Line, konsol#348 S2): reconcile_all stamps it on sync_watermark like the epm_staging and epm_gold tables.
-- Here it holds the 2 rows the watermark says the sync wrote, so nothing is EMPTIED. Found live on 15 Nov
-- 2026: the test read row counts from epm_staging and epm_gold only, so with any approved budget line every
-- build ended ERROR=1 ("EMPTIED: the sync wrote rows, the table has none") although the table held them.
-- gate: expect assert_staging_not_stale pass
-- A stack where konsol has not added the column yet (README: a fixture may add one).
ALTER TABLE epm_staging.sync_watermark ADD COLUMN IF NOT EXISTS reconcile_run_id String;
INSERT INTO epm_staging.sync_watermark
  (table_name, synced_at, row_count, source_max_modified, reconcile_run_id)
VALUES
  ('epm_raw.budget_entries', '2026-11-15 18:00:00', 2, '1970-01-01 00:00:00', '20261115T180000Z-0000cccc');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 400, 'USD', 'Period movement');
