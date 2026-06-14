# PRD: Close Assertion Suite — Reconciliation Gate

**Status:** Not Started
**Date:** 2026-06-14
**Phase:** Phase 6 — Analytical Gaps & Enhancements (§6.10)
**Repos:** `konsolidat` (dbt test config + store-failures), `konsol` (Frappe doctypes, build tie-in, sign-off gate, dashboard)

## Problem

The pipeline already *computes* whether a close reconciles, but a controller can't *see* it in the app, and nothing stops an unreconciled close from being signed off:

- `dbt_project/tests/` holds **60 `assert_*` singular tests** — `assert_end_to_end_bs_balances`, `assert_trial_balance_balances`, `assert_silver_gl_debit_credit_balance`, `assert_ic_elimination_nets_zero`, `assert_ic_reconciliation_matched`, `assert_cta_zero_for_same_currency`, `assert_equity_method_single_line`, `assert_nci_movement_reconciles`, `assert_waterfall_reconciles`, `assert_ytd_p12_equals_annual`, the allocation `assert_*` family, etc. Each is written to **return the offending rows** (e.g. each `(consolidation_group, fiscal_year, fiscal_period)` whose balance-sheet net `> 1.00`).
- These run as part of `dbt build` (including the governed `Pipeline Build Request` path), but a failure today only **fails the build** — the result is a non-zero exit code in a log, not a per-assertion status a finance user can read.
- dbt is **not** run with `--store-failures`, so the failing rows are computed and then **thrown away** — the "which row broke, and why" information exists for milliseconds and is never persisted.
- There is **no close sign-off gate**: `Pipeline Build Request` governs *builds*, but nothing ties assertion results to close approval, and there is no in-app reconciliation view (`gold_ic_reconciliation` exists as data, but no surfaced pass/fail board).

## Solution

Persist dbt assertion results per close and surface them as a **green/red reconciliation gate** in `konsol`: tag the `assert_*` tests, run them with `--store-failures` from a `Pipeline Build Request`, parse each test's pass/fail + failing rows into a `Close Assertion Run` (one child row per assertion), and gate close sign-off on an all-green run (with an audited override). Green = the numbers reconcile; red = the exact rows that broke, and why.

## Scope

### 1. dbt: make assertions storable + selectable (`konsolidat`)

- Add a `close_assertion` tag (and a category tag) to the 60 `assert_*` tests via `dbt_project.yml` `tests:` config + per-test `{{ config(tags=[...]) }}`, so the suite can be run as a unit: `dbt test --select tag:close_assertion --store-failures`.
- Enable `store_failures: true` for the suite so each failing assertion writes its offending rows to a results relation (`<schema>_dbt_test__audit.<test_name>`).
- Standardise each assertion's output columns to carry close context — `consolidation_group, fiscal_year, fiscal_period` plus a short `reason`/measured-value column — so the stored rows are self-describing. (Most already emit the grain; this normalises the laggards.)
- Group tests into **categories** for the dashboard: `trial_balance`, `fx_cta`, `intercompany`, `equity_nci`, `ownership_hierarchy`, `allocation`, `budget_spread`, `variance`.

### 2. `Close Assertion Run` doctype (`konsol`, module `Pipeline`)

`autoname: CAR-.#####`.

| Field | Type | Notes |
|---|---|---|
| `consolidation_group` | Data | Close being asserted |
| `fiscal_year` / `fiscal_period` | Int | Close period |
| `pipeline_build_request` | Link → `Pipeline Build Request` | Build that produced these results |
| `status` | Select | `Running` / `Green` / `Red` (red if any assertion failed) |
| `total` / `passed` / `failed` | Int (read_only) | Suite tallies |
| `run_at` | Datetime (read_only) | |
| `results` | Table → `Close Assertion Result` | One row per assertion |

**`Close Assertion Result`** (`istable: 1`)

| Field | Type | Notes |
|---|---|---|
| `assertion` | Data | Test name, e.g. `assert_end_to_end_bs_balances` |
| `category` | Data | From the test's category tag |
| `result` | Select | `pass` / `fail` |
| `failed_rows` | Int | Count from the stored-failures relation |
| `sample_failures` | Code/JSON (read_only) | First N offending rows (the "which row, and why") |

### 3. Run + capture (`konsol`)

- Extend the governed build (`run_governed_build`) so a `close`-scoped Pipeline Build Request runs `dbt build`/`dbt test --select tag:close_assertion --store-failures` and, on completion, creates a `Close Assertion Run`.
- Parse `run_results.json` (per-test status + failures count) and query each failed test's `dbt_test__audit` relation for `sample_failures`; write one `Close Assertion Result` per assertion. Run `status` = `Red` if any `fail`.

### 4. Sign-off gate (`konsol`)

- A close cannot be approved while its latest `Close Assertion Run` is `Red` or missing — enforced in the budget/consolidation approval chain (§6.5). Block at approval with the failing assertions named.
- Explicit **override**: an EPM Admin may sign off Red with a mandatory reason, recorded on the run (audited). Reuses Build Governance roles.

### 5. Dashboard (`konsol`)

- Per-close-period green/red board (one tile per category, drill to assertions); red assertion → its `sample_failures`. A Frappe Report/Number Card over `Close Assertion Result`.

## Out of Scope

- Authoring new assertions — this productises the **existing 60**; new checks land with their feature PRDs.
- Auto-remediation of failures (only detect + surface + gate).
- Scheduling/orchestration of the close itself (Phase 7 close runbook); this is the assertion gate within it.
- Cross-period/trend analytics on assertion history (future enhancement).

## Acceptance Criteria

1. `dbt test --select tag:close_assertion --store-failures` runs exactly the `assert_*` suite and persists failing rows to the audit relations.
2. A `close`-scoped Pipeline Build Request produces a `Close Assertion Run` with one `Close Assertion Result` per assertion; `status=Green` iff every result is `pass`.
3. A deliberately broken close (e.g. an unbalanced topside journal) yields `status=Red`, the failing assertion (`assert_topside_journal_balanced`) is marked `fail`, and `sample_failures` shows the offending `(group, year, period)` rows.
4. Close approval is blocked while the latest run is Red/missing; the block message names the failing assertions.
5. An EPM Admin can override a Red sign-off with a recorded reason; the override is audited and visible on the run.
6. The dashboard shows green/red per category for a period and drills a red assertion into its failing rows.
7. `dbt build` passes the existing suite with zero regressions; on an all-reconciling close the run is `Green` with `failed=0`.
8. Structural tests (`test_close_assertion_suite.py`) confirm the doctypes, the build tie-in, and the approval-gate guard.

## Open Questions

- **Failure-row volume:** cap `sample_failures` at N (e.g. 50) per assertion and store a count, or link to the full audit relation? Leaning capped sample + count.
- **Tolerances:** assertions hard-code thresholds (e.g. BS net `> 1.00`). Make per-assertion tolerance configurable (a `Close Assertion Config` doctype) or keep in dbt? Leaning dbt for v1.
- **Materiality severity:** should some assertions be *warnings* (don't block sign-off) vs *errors* (block)? Add a severity per assertion, or treat all `close_assertion` as blocking?
- **Storage backend:** dbt-clickhouse `--store-failures` writes to ClickHouse; confirm the audit-relation naming and that `konsol` can read it via the existing `clickhouse.py` client.
- **Period scoping:** dbt tests run over all periods in the gold tables; do we filter the suite to the close period via a `var`, or assert globally and report per-period? Leaning a `close_period` var for scoped runs.
