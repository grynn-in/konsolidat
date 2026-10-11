# dbt test fixtures

A fixture is a plain ClickHouse SQL file of `INSERT INTO epm_<layer>.<table> (...) VALUES (...);`
statements (`;`-terminated, `--` comments allowed) that seeds the rows one singular test in
`dbt_project/tests/` is checked against. Name it after the test: `<test_name>.sql` holds rows
the test must PASS on; `<test_name>.must_flag.sql` holds rows the test must still flag.

## Rules

- Every entity, group and account code starts with `ZZ` (`ZZG`, `ZZE1`, `ZZ1000`). Real
  customer names or codes never appear here: this repository is public.
- Use an explicit column list in every INSERT so a fixture keeps working when a column is added.
- A fixture may open with `ALTER TABLE epm_<layer>.<table> ADD COLUMN IF NOT EXISTS …;` statements
  (run first, in order) when it needs a column the live DDL does not have yet.
- A consolidation fixture may `CREATE TABLE IF NOT EXISTS epm_staging.<table> (<body>) …;` the deal
  tables konsol owns (`business_combinations`, `business_combination_consideration`,
  `business_combination_acquired_balances`, `business_combination_costs`, `business_disposals`,
  `business_disposal_proceeds`) before inserting into them: the gate creates a table from the live
  DDL only when it exists live, and konsol's tables are not there until konsol deploys them. Use the
  exact bodies from `clickhouse/init-db.sql` (pinned by `tests/test_deal_tables_ddl.py`); the gate
  rewrites `epm_` to `zzg_`. The deal rows themselves follow the `ZZ` rule (`ZZG`, `ZZS`,
  `BC-ZZG-ZZS-<date>`). `deal_tables_empty.sql` holds the six CREATEs with no rows, for `build-live`.
- dbt ignores this folder: `test-paths` in `dbt_project.yml` is `["tests"]`, so nothing in
  here runs as a test. The fixtures are only read by the gate script below.

## What a fixture declares

The gate reads optional `-- gate:` lines anywhere in the file:

    -- gate: build <dbt selector ...>      dbt build --indirect-selection cautious --select <selector>
    -- gate: expect <test> pass|flag [N]   judge this test; N is the exact result count when it flags
    -- gate: expect <model> built          the model must build (the rule is the model's own guard)
    -- gate: refuse <model> <text>         the build must ERROR on <model>, with <text> in the log

With no `build` line the gate runs `dbt test --select <test>` on the seeded rows. With no
`expect` line the test is the file name up to its first dot, and it must flag for
`.must_flag.` and pass otherwise. The file name is the contract: a plain fixture that
expects a flag, or a `.must_flag.` fixture that expects none, is refused before anything
runs. In build mode an ERROR on any model or test fails the fixture unless `refuse` names it.
Other tests a build selects are printed, not judged: several deal fixtures document an
intended FAIL of a neighbouring guard.

## Running the gate

`scripts/fixture_gate.py` (konsolidat#266; Deepak Pai, 11 Oct 2026, option G-1). CI runs every
fixture in the `fixture-gate` job of `.github/workflows/dbt-checks.yml`:

    python scripts/fixture_gate.py --all --prepare-ci        # CI, on a throwaway ClickHouse
    python scripts/fixture_gate.py <fixture.sql> [...]       # some fixtures, any stack

Per fixture it creates every table the file names (comments included) in scratch schemas
(`zzg_<layer>`), every declared dbt source, and in test mode every relation the test reads,
all empty and with the DDL of the matching `epm_*` table. It rewrites `epm_` to `zzg_`, loads
the fixture, prints `fixture <table>: N rows` per table, runs dbt on a copy of the project
whose schemas are rewritten the same way, judges `target/run_results.json` and drops the
scratch schemas. `fixture … 0 rows` means an INSERT did not run. The `epm_*` tables are only
read, for their DDL.

Where the DDL comes from: on a live stack, its own tables. In CI there is no live stack, so
`--prepare-ci` (which refuses unless `CI=true` or `--yes-destroy-this-warehouse`) first
applies `clickhouse/init-db.sql` and `raw-schema.sql`, then runs `dbt run` for the whole
project at the real dimensions. The model tables a fixture seeds (`gold_trial_balance`,
`silver_entity_currencies`, ...) are declared nowhere in `clickhouse/*.sql`; they exist only
once dbt builds them, with the columns the model's SQL gives them.

The earlier `build-live` mode (clone every live source with its rows, then build) is not in
the committed script: it read live rows, which CI cannot have. `deal_tables_empty.sql`
now runs as an ordinary build fixture: `+gold_fully_consolidated_tb` must build on the six
empty deal tables and `assert_end_to_end_bs_balances` must pass.
