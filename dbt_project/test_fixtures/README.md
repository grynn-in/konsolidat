# dbt test fixtures

A fixture is a plain ClickHouse SQL file of `INSERT INTO epm_<layer>.<table> (...) VALUES (...);`
statements (`;`-terminated, `--` comments allowed) that seeds the rows one singular test in
`dbt_project/tests/` is checked against. Name it after the test: `<test_name>.sql` holds rows
the test must PASS on; `<test_name>.must_flag.sql` holds rows the test must still flag.

## Rules

- Every entity, group and account code starts with `ZZ` (`ZZG`, `ZZE1`, `ZZ1000`). Real
  customer names or codes never appear here: this repository is public.
- Use an explicit column list in every INSERT so a fixture keeps working when a column is added.
- dbt ignores this folder: `test-paths` in `dbt_project.yml` is `["tests"]`, so nothing in
  here runs as a test. The fixtures are only read by the gate script below.

## Running one

The gate script lives outside the repository for now (a maintainer's scratch checkout). It takes
three arguments; it prints `fixture <table>: N rows` per table, then dbt's `PASS` / `FAIL` + `Got N results` lines:

    gate-dbt-test.sh <worktree> <test_name> <fixture.sql>

It creates every table the fixture names in a scratch schema (`zzg_<layer>`) with the live table's
DDL, loads the fixture, runs the one test and drops the schema; the live `epm_*` tables are never
read or written. `fixture … 0 rows` means an INSERT did not run.
