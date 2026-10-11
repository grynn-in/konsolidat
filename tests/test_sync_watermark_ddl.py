"""konsolidat#246 (option #246-1; Deepak Pai, 11 Oct 2026): the sync watermark
carries the reconcile run that stamped each row, and two repos create it.

konsol's _WATERMARK_DDL creates epm_staging.sync_watermark at the first stamp,
and dbt_project.yml's on-run-start creates it where this project runs first.
Whichever runs first wins, so the two texts must agree, and the sort key
cannot change after the table exists except through the one ALTER below.
konsol's _WATERMARK_UPGRADE and the sync_watermark_upgrade() macro both issue
that ALTER on a table created before the column; konsol's
tests/test_reconcile_run_id.py pins the same strings.

reconcile_run_id is in the sorting key: keyed on table_name alone,
ReplacingMergeTree replaced a table's run row with its next write-through on
merge. No DEFAULT clause: ClickHouse refuses to add a column with a default
expression to the sorting key (measured on 24.8).

Plain unittest, no third-party imports:
`python -m unittest -v tests.test_sync_watermark_ddl` (.github/workflows/dbt-checks.yml).
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DBT_PROJECT = os.path.join(PROJECT_ROOT, "dbt_project", "dbt_project.yml")
MACRO = os.path.join(PROJECT_ROOT, "dbt_project", "macros", "sync_watermark.sql")
TEST = os.path.join(PROJECT_ROOT, "dbt_project", "tests", "assert_staging_not_stale.sql")
SOURCES = os.path.join(PROJECT_ROOT, "dbt_project", "models", "staging", "_staging__sources.yml")
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "dbt-checks.yml")

# konsol's _WATERMARK_DDL and _WATERMARK_UPGRADE, verbatim.
KONSOL_DDL = (
    "CREATE TABLE IF NOT EXISTS epm_staging.sync_watermark ("
    "table_name String, "
    "synced_at DateTime, "
    "row_count UInt64, "
    "source_max_modified DateTime, "
    "reconcile_run_id String"
    ") ENGINE = ReplacingMergeTree(synced_at) ORDER BY (table_name, reconcile_run_id)"
)
KONSOL_UPGRADE_TAIL = (
    " ADD COLUMN IF NOT EXISTS reconcile_run_id String,"
    " MODIFY ORDER BY (table_name, reconcile_run_id)"
)


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _normalise(sql):
    sql = re.sub(r"\s+", " ", sql.strip())
    return re.sub(r"\s*([(),])\s*", r"\1", sql)


class SyncWatermarkDDL(unittest.TestCase):

    def test_on_run_start_creates_the_watermark_with_konsols_shape(self):
        yml = _read(DBT_PROJECT)
        m = re.search(r"CREATE TABLE IF NOT EXISTS epm_staging\.sync_watermark \(.*?\)\s*"
                      r"ENGINE = [^\n]*", yml, flags=re.S)
        self.assertTrue(m, "on-run-start no longer creates epm_staging.sync_watermark")
        self.assertEqual(_normalise(m.group(0)), _normalise(KONSOL_DDL))

    def test_on_run_start_upgrades_an_older_watermark(self):
        self.assertIn('"{{ sync_watermark_upgrade() }}"', _read(DBT_PROJECT))
        macro = _read(MACRO)
        # The ALTER text, reassembled from the string pieces of the macro's
        # last return().
        pieces = "".join(re.findall(r'"([^"]*)"', macro.split("return(\n")[-1]))
        self.assertIn(KONSOL_UPGRADE_TAIL, pieces)
        self.assertNotIn("DEFAULT", pieces)

    def test_the_upgrade_is_asked_first(self):
        """A no-op ALTER still moves metadata_modification_time, the test's
        no-run-yet grace clock: the macro must look before it alters."""
        macro = _read(MACRO)
        # the same question konsol asks: is the column in the sorting key?
        self.assertIn("select sorting_key from system.tables", macro)
        self.assertIn("'reconcile_run_id' in keys[0]", macro)

    def test_lagging_reads_the_run_not_the_newest_stamp(self):
        sql = _read(TEST)
        self.assertIn("reconcile_run_id", sql)
        self.assertNotIn("newest_sync", sql, "the newest-stamp comparison is #246's defect")
        self.assertIn("NO_RECONCILE_RUN", sql)
        self.assertIn("metadata_modification_time", sql)

    def test_the_column_is_documented_on_the_source(self):
        self.assertIn("reconcile_run_id", _read(SOURCES))

    def test_ci_runs_this_test_and_watches_its_inputs(self):
        wf = _read(WORKFLOW)
        self.assertIn("python -m unittest -v tests.test_sync_watermark_ddl", wf)
        self.assertEqual(wf.count("- 'tests/test_sync_watermark_ddl.py'"), 2,
                         "list this test under both the push and pull_request path filters")


if __name__ == "__main__":
    unittest.main()
