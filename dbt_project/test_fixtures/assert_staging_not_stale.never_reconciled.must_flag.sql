-- assert_staging_not_stale: must FLAG exactly 1 (konsolidat#246 review). Run 20261009T214054Z-0000bbbb
-- stamped entities and fiscal_periods. ownership_periods has only its old stamp from before the upgrade
-- (run id ''): every reconcile since has failed on it, so no run has ever stamped it. It is missing
-- from the latest run, so it is LAGGING. This is the ownership_periods case the test exists for;
-- the old rule caught it, and a rule that judged only tables some reconcile had stamped did not.
-- gate: expect assert_staging_not_stale flag 1
-- A stack where konsol has not added the column yet (README: a fixture may add one).
ALTER TABLE epm_staging.sync_watermark ADD COLUMN IF NOT EXISTS reconcile_run_id String;
INSERT INTO epm_staging.sync_watermark
  (table_name, synced_at, row_count, source_max_modified, reconcile_run_id)
VALUES
  ('epm_staging.ownership_periods', '2026-09-30 09:24:13', 0, '1970-01-01 00:00:00', ''),
  ('epm_staging.entities', '2026-10-09 21:40:50', 0, '1970-01-01 00:00:00', '20261009T214054Z-0000bbbb'),
  ('epm_staging.fiscal_periods', '2026-10-09 21:40:52', 0, '1970-01-01 00:00:00', '20261009T214054Z-0000bbbb');
