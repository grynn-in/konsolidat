-- assert_staging_not_stale: must PASS (konsolidat#246 review). Run 20261004T092413Z-0000aaaa stamped
-- three tables. A second reconcile is running now: it has stamped entities a moment ago and not yet
-- reached the other two. A run whose newest stamp is under watermark_run_settle_seconds (60) old is
-- not judged yet, so the latest settled run is the first one and nothing is LAGGING. Without the
-- settle window this flags 2 (a fresh install's queued reconcile can overlap a dbt test).
-- gate: expect assert_staging_not_stale pass
-- A stack where konsol has not added the column yet (README: a fixture may add one).
ALTER TABLE epm_staging.sync_watermark ADD COLUMN IF NOT EXISTS reconcile_run_id String;
INSERT INTO epm_staging.sync_watermark
  (table_name, synced_at, row_count, source_max_modified, reconcile_run_id)
VALUES
  ('epm_staging.entities', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.ownership_periods', '2026-10-04 09:24:13', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.fiscal_periods', '2026-10-04 09:24:14', 0, '1970-01-01 00:00:00', '20261004T092413Z-0000aaaa'),
  ('epm_staging.entities', now(), 0, '1970-01-01 00:00:00', '29991231T000000Z-0000cccc');
