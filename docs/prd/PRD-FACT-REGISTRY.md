# PRD: Fact Registry

**Status:** Implemented (konsol #14)
**Date:** 2026-06-13
**Phase:** Phase 2.3 — Dynamic Schema (Facts)
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app)

## Problem

The `Fact Table` doctype already exists (`konsol/epm/doctype/fact_table/`) and `api.py` resolves queries through it by `scenario_key`, but the registry is incomplete and the surrounding generation is one-directional:

- `Fact Table` has no `grain` or `refresh_frequency`, and no notion of *required* dimensions/measures — `fact_dimensions` is advisory only and `measures` is a free-text JSON array, so a fact can be saved that references a dimension that does not exist on its ClickHouse table.
- `schema_apply.py::_apply_clickhouse_columns()` only adds **dimension** columns to existing fact tables. There is no path that **creates** a fact table or its dbt source on registration — a new statistical/sub-ledger fact still requires hand-writing CREATE TABLE DDL plus a `sources:` block.
- Statistical drivers live as three hardcoded seeds (`seeds/allocation_drivers_headcount.csv`, `_sqm.csv`, `_revenue.csv`) plus the unified `epm_staging.allocation_drivers` source. They cannot be queried via `=EPM()` and are not period-grained facts in the warehouse sense.
- Core financial facts (`gold_trial_balance`, `gold_allocation_results`, budget input) are implicitly understood but not registered as facts with declared grain, so there is no single catalog an engineer or the API can introspect.

## Solution

Complete the `Fact Table` registry: add `grain`/`refresh_frequency`/required-artifact validation, pre-seed core + statistical + sub-ledger facts, and extend `schema_apply.py` so that registering a fact generates its ClickHouse staging table DDL and its dbt `sources:` entry — making "add a fact table" a Frappe Desk operation, not a 6-file code change.

## Scope

### 1. `Fact Table` doctype fields (additions)

Existing fields stay (`fact_name`, `label`, `source_type`, `clickhouse_table`, `dbt_model`, `scenario_key`, `has_scenario_id`, `reroute_*`). **`measures` is converted from a free-text JSON array to a child table** (`fact_measures`) for symmetry with `fact_dimensions` (decided 2026-06-13). Add:

| Field | Type | Purpose |
|---|---|---|
| `grain` | Small Text | Human description of one row, e.g. "one row per account × period × entity × cost_center" |
| `refresh_frequency` | Select | `On Extract` / `Daily` / `Monthly` / `On Demand` — drives PBR scheduling later |
| `generates_source` | Check | If set, `schema_apply` creates a CREATE TABLE + dbt source for write-back facts (statistical/sub-ledger). Off for derived gold facts. |
| `extra_columns` | Code (JSON) | Fact-local detail columns for sub-ledger facts (e.g. `invoice_id`, `due_date`, `aging_bucket`) that are **not** shared analytical dimensions — `[{"name","ch_type"}]`. Kept out of the global `Dimension` registry by design. |
| `status` | Select | `Draft` / `Published` / `Inactive` (mirror `Dimension`/`Measure` lifecycle) |

Child tables (per-row `required` checkbox on **both**, for symmetry):

| Child table | Row fields |
|---|---|
| `fact_dimensions` | `dimension` (Link → Dimension), `required` (Check) |
| `fact_measures` | `measure` (Link → Measure), `required` (Check) |

`validate()` (extend `fact_table.py`): every `fact_measures.measure` must match a Published `Measure.measure_name`; every `fact_dimensions.dimension` must be a Published `Dimension`; `clickhouse_table` must match `_SAFE_TABLE_NAME` (`schema.table`); each `extra_columns[].name` must pass `_SAFE_IDENTIFIER`.

### 2. Pre-seeded facts (`install.py`)

| `fact_name` | `source_type` | `scenario_key` | `clickhouse_table` / `dbt_model` | Grain |
|---|---|---|---|---|
| `gl_journal_entries` | ERP GL | `actuals` | `epm_gold.gold_trial_balance` | account × period × entity × dims |
| `budget_input` | Budget | `budget` | `epm_gold.gold_scenario_trial_balance` | scenario cell |
| `allocation_results` | ERP GL | `allocation` | `epm_gold.gold_allocation_results` | allocated account × cost_center × period |
| `headcount` | Statistical | `headcount` | `epm_staging.fact_headcount` | cost_center × period |
| `area_sqm` | Statistical | `area_sqm` | `epm_staging.fact_area_sqm` | cost_center × period |
| `revenue_by_product` | Statistical | `revenue_by_product` | `epm_staging.fact_revenue_by_product` | product × cost_center × period |
| `accounts_payable` | Sub-ledger | `ap` | `epm_staging.fact_accounts_payable` | invoice line |
| `fixed_assets` | Sub-ledger | `fixed_assets` | `epm_staging.fact_fixed_assets` | asset |
| `accounts_receivable` | Sub-ledger | `ar` | `epm_staging.fact_accounts_receivable` | invoice line × aging bucket |

Core/derived facts (`generates_source = 0`) point at existing gold tables. Statistical + sub-ledger facts (`generates_source = 1`) are write-back facts under the `epm_staging` source schema.

### 3. On-save / apply generation (`schema_apply.py`)

Add `_apply_fact_tables()` to `apply_schema()`, run after `_apply_clickhouse_columns()`. For each Published `Fact Table` with `generates_source = 1`:

| Step | Action |
|---|---|
| ClickHouse DDL | `CREATE TABLE IF NOT EXISTS {clickhouse_table} (...)` — columns from `fact_dimensions` (typed via existing `_CH_TYPE_MAP`) + a `Float64` per measure + `fiscal_year UInt16`, `fiscal_period UInt8`, `data_area_id String`, `updated_at DateTime` — `ENGINE = MergeTree ORDER BY (data_area_id, fiscal_year, fiscal_period)` |
| dbt source | Upsert a `tables:` entry under `sources: epm_staging` in `models/staging/_staging__sources.yml` (mirror existing `allocation_drivers` entry: `name`, `description`, `loaded_at_field: updated_at`) |
| Identifier safety | Reuse `_SAFE_IDENTIFIER` / `_SAFE_TABLE_NAME`; skip + `frappe.log_error` on mismatch (same pattern as existing column DDL) |

Return additions in `apply_schema` summary: `facts_created`, `sources_written`. Generation is idempotent (`IF NOT EXISTS`, upsert by name).

### 4. `allocation_drivers` migration

Statistical facts replace the seed-driven drivers:

- New facts `fact_headcount`, `fact_area_sqm`, `fact_revenue_by_product` carry a `driver_value Float64` measure, matching the seed columns (`data_area_id, cost_center, driver_value, fiscal_year, fiscal_period`).
- A `stg_allocation_drivers` view UNIONs the three statistical fact sources with a `driver_type` literal, producing the same shape `resolve_allocation_driver.sql` / `epm_staging.allocation_drivers` consume today — so the allocation engine is unchanged.
- Seeds `allocation_drivers_*.csv` are retained as bootstrap/demo data only; production reads from the facts.

### 5. API integration (`api.py`)

- `_get_fact_by_scenario()` already loads the fact by `scenario_key`; no signature change. Add a `_get_fact_dimensions`/`_get_allowed_measures` guard so a `dimensions` filter for a dimension not in the fact's `fact_dimensions` returns a clear error instead of a ClickHouse failure.
- Statistical/sub-ledger facts become queryable via the same `scenario`/`fact` resolution path once registered (e.g. `=EPM(..., fact="headcount")`), unblocking Phase 2.4's `fact` parameter.

## Out of Scope

- The generic `dimensions={}` and `measure`/`fact` parameter rework in `=EPM()` — that is **Phase 2.4 (API Generalisation)**; this PRD only ensures registered facts are resolvable.
- Fact-specific source extraction macros (GL vs budget vs statistical) — **Phase 2.5**.
- Airbyte / ERP ingestion connectors that would populate sub-ledger facts (AP/AR/Fixed Assets) — **Phase 3**; this PRD registers the facts and creates empty tables only.
- Cash flow models that will consume AP/AR/Fixed-Asset facts — **Phase 6.1**.
- Cube.js schema generation for new facts.

## Acceptance Criteria

1. `Fact Table` doctype exposes `grain`, `refresh_frequency`, `required_measures`, `generates_source`, `status`; saving a fact with a `measures` entry absent from the Published `Measure` registry throws.
2. Saving a fact whose `fact_dimensions` references a non-Published `Dimension` throws.
3. `install.py` seeds the 9 facts in the table above; `frappe.get_all("Fact Table")` returns exactly those 9 after a clean install.
4. `apply_schema()` on a Published `generates_source=1` fact creates its `epm_staging.fact_*` ClickHouse table (verifiable via `SHOW TABLES`) and returns it in `summary["facts_created"]`.
5. After apply, `_staging__sources.yml` contains a `tables:` entry for each generated fact; `dbt parse` succeeds and `dbt source freshness --select source:epm_staging.fact_headcount` resolves.
6. Re-running `apply_schema()` adds nothing new (idempotent): `facts_created` and `sources_written` are empty on the second run.
7. `stg_allocation_drivers` returns the same row count/shape from facts as the legacy seeds for the USMF 2024-P1 fixture; existing allocation dbt tests still pass.
8. `=EPM("USMF", 2024, "P1", fact="headcount", dimensions={"cost_center":"SALES"})` resolves through `_get_fact_by_scenario("headcount")` and returns the headcount value (no hardcoded scenario branch).
9. New structural tests in `test_fact_registry.py` pass: validation rejects bad measures/dimensions, generation produces expected DDL string, summary keys present.

## Resolved Decisions (2026-06-13)

- **Required flags:** symmetric per-row `required` checkbox on both `fact_dimensions` and `fact_measures`; `measures` becomes a child table (no separate `required_measures` JSON).
- **Sub-ledger detail columns:** `extra_columns` JSON on `Fact Table` for fact-local detail (invoice_id, due_date, aging_bucket) — kept out of the global `Dimension` registry, which is reserved for shared analytical dimensions.
- **Teardown:** inactivating a fact **never** drops its ClickHouse table (mirrors the dimension flow that never drops columns). Inactive stops dbt sources/queries; physical `DROP TABLE` is a deliberate manual admin action.
