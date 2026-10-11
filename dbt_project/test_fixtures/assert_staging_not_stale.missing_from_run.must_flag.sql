-- assert_staging_not_stale: must FLAG exactly 1 (konsolidat#246). Run 20261004T092413Z-0000aaaa stamped four
-- tables; the later run 20261009T214054Z-0000bbbb stamped three of them and skipped ownership_periods (its
-- doctype failed to sync, so reconcile_all logged it and went on). That table is LAGGING.
-- gate: expect assert_staging_not_stale flag 1
-- A stack where konsol has not added the column yet (README: a fixture may add one).
ALTER TABLE epm_staging.sync_watermark ADD COLUMN IF NOT EXISTS reconcile_run_id String;
INSERT INTO epm_staging.sync_watermark
  (table_name, synced_at, row_count, source_max_modified, reconcile_run_id)
VALUES
  ('epm_staging.entities', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.ownership_periods', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.fiscal_periods', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_gold.currencies', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.entities', '2026-10-09 21:40:50', 0, '1970-01-01 00:00:00', '20261009T214054Z-0000bbbb'),
  ('epm_staging.fiscal_periods', '2026-10-09 21:40:52', 0, '1970-01-01 00:00:00', '20261009T214054Z-0000bbbb'),
  ('epm_gold.currencies', '2026-10-09 21:40:54', 0, '1970-01-01 00:00:00', '20261009T214054Z-0000bbbb');
