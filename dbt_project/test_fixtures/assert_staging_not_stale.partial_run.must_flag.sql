-- assert_staging_not_stale: must FLAG exactly 4 (konsolidat#246). Run 20261004T092413Z-0000aaaa stamped five
-- tables. The later run 20261009T214054Z-0000bbbb was killed after its first table: it is still the latest run
-- (it started last), so the four tables it never reached are LAGGING. One of them, fiscal_periods,
-- had a write-through after the kill: still LAGGING, because the rule asks whether the reconcile
-- reached the table, not whether the table is recent.
-- gate: expect assert_staging_not_stale flag 4
-- A stack where konsol has not added the column yet (README: a fixture may add one).
ALTER TABLE epm_staging.sync_watermark ADD COLUMN IF NOT EXISTS reconcile_run_id String;
INSERT INTO epm_staging.sync_watermark
  (table_name, synced_at, row_count, source_max_modified, reconcile_run_id)
VALUES
  ('epm_staging.entities', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.ownership_periods', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.fiscal_periods', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.currencies', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.cash_flow_categories', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.entities', '2026-10-09 21:40:50', 0, '1970-01-01 00:00:00', '20261009T214054Z-0000bbbb'),
  ('epm_staging.fiscal_periods', '2026-10-09 22:05:00', 0, '1970-01-01 00:00:00', '');
