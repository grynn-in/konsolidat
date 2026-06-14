# PRD: Dimension Harmonization

**Status:** Implemented (konsolidat #38, konsol #18)
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP (cross-connector)
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app)

## Problem

Each ERP has its own dimension system, and after Phase 3 connectors land the canonical staging models will carry raw, ERP-local dimension values that do not line up across legal entities:

- D365 F&O emits financial dimension values from `LedgerDimensionValuesJson` (e.g. cost center `CC001`); SAP uses cost/profit center codes; D365 BC uses Dimension Set Entries; ERPNext uses Cost Center names.
- The canonical adapter contract (`canonical-staging-schema.md`) defines `dim_cost_center`, `dim_department`, `dim_business_unit` as passthrough strings — each adapter's `dim_select_from_source()` casts its own `source_column` into them, but there is **no crosswalk**. A D365 `CC001` and an ERPNext `Sales - Germany` that represent the same management cost center stay distinct values.
- Consolidated gold models (`gold_trial_balance`, allocations, variance) group by `{{ dim_group_by() }}`. With unharmonized values, the same economic dimension fragments across LEs, so group-level slicing, IC matching by dimension, and allocation driver joins are wrong or impossible.
- Phase 2 delivered the `Dimension` registry doctype (`name`, `source_column`, `label`, `cube_type`, `in_budget`, `allocation_role`) and the `dim_select_from_source()` macro — but `source_column` is single-valued and D365-only. There is no place to record, per ERP, that several source values map to one canonical value.

## Solution

Add a **dimension crosswalk layer**: a `Dimension Mapping` doctype + dbt seed keyed by `(dimension, erp_source, source_value) -> canonical_value`, applied by a new `dim_harmonize()` macro inside each per-ERP adapter so canonical staging models emit harmonized values, with unmapped values passed through verbatim and surfaced for review.

## Scope

### 1. `Dimension Mapping` doctype (`konsol`)

New doctype in module `EPM`, autoname `field:mapping_key` (or hash), reusing the lifecycle pattern of `Dimension` (Draft/Published, `apply_and_rebuild` on Publish via `schema_lifecycle`).

| Field | Type | Notes |
|-------|------|-------|
| `dimension` | Link → `Dimension` | which canonical dimension (e.g. `dim_cost_center`) |
| `erp_source` | Select | `d365_fo`/`d365_bc`/`sap_s4`/`sap_ecc`/`sap_b1`/`erpnext` — matches `erp_source` column values |
| `source_value` | Data | raw value as it appears in that ERP (e.g. `CC001`) |
| `canonical_value` | Data | harmonized target value (e.g. `CC-EMEA-SALES`) |
| `canonical_label` | Data | display label for the canonical value |
| `status` | Select | `Draft`/`Published`/`Inactive` |

On Publish: regenerate the `dimension_mappings` seed CSV and run `dbt seed` + tag-scoped `dbt build` through the existing `apply_and_rebuild()` path.

### 2. `dimension_mappings` seed (`konsolidat`)

New seed `seeds/dimension_mappings.csv` (alongside `allocation_rules.csv`, `consolidation_groups.csv`):

| Column | Example |
|--------|---------|
| `dimension` | `dim_cost_center` |
| `erp_source` | `erpnext` |
| `source_value` | `Sales - Germany` |
| `canonical_value` | `CC-EMEA-SALES` |
| `canonical_label` | `EMEA Sales` |

Generated from published `Dimension Mapping` docs by `dbt_config.py` (same mechanism that writes `vars.dimensions`/`vars.base_measures`). Hand-editable for bulk loads.

### 3. `dim_harmonize()` macro (`konsolidat`)

New macro in `macros/dimension_helpers.sql`. Replaces the current per-adapter `dim_select_from_source()` pass with a harmonizing variant:

- Signature: `{{ dim_harmonize(erp_source, prefix='') }}` — called inside each `stg_<erp>__*` adapter (GL entries, budget entries).
- For each dimension in `var('dimensions')`: left-join the dimension's raw source value against `ref('dimension_mappings')` on `(dimension = d.name, erp_source = <erp>, source_value = <raw>)` and emit `coalesce(canonical_value, <raw>) as d.name`.
- Unmapped source values pass through unchanged (no silent NULLs), so onboarding a new value is non-blocking.
- Implemented as a single left join per adapter against the seed pivoted/filtered by `erp_source`, not N joins, to keep adapter SQL flat.

### 4. Reference adapter wiring (`konsolidat`)

`stg_d365_fo__gl_entries.sql` and `stg_d365_fo__budget_entries.sql` switch from emitting raw dimension columns to `{{ dim_harmonize('d365_fo') }}`. This is the reference; each new Phase 3 connector adapter does the same with its own `erp_source` key. Canonical models (`stg_gl_entries`, `stg_budget_entries`) need no change — they still `UNION ALL` adapter output.

### 5. Unmapped-value visibility

| Artifact | Purpose |
|----------|---------|
| `gold_unmapped_dimension_values.sql` | distinct `(erp_source, dimension, source_value)` present in `stg_gl_entries` with no published mapping — drives a "needs harmonization" review queue |
| Frappe list/report on `Dimension Mapping` | surfaces the above so an EPM Admin can author missing crosswalk rows |

## Out of Scope

- Auto-suggesting / fuzzy-matching mappings (LLM or string-similarity) — mappings are authored manually.
- Harmonizing the `account` / chart-of-accounts dimension — main-account mapping is a separate concern (use existing account category seeds).
- Hierarchy/rollup of canonical dimension values (parent-child) — this PRD delivers flat value-to-value crosswalk only.
- Per-LE overrides where the same `(erp_source, source_value)` maps differently by entity — keyed on ERP source only for v1.
- New connector adapters themselves (D365 BC, SAP, ERPNext) — covered by their own PRDs; this depends on them landing.

## Acceptance Criteria

1. `dbt seed --select dimension_mappings` loads the crosswalk table without error.
2. A `dim_cost_center` mapping `(d365_fo, CC001 -> CC-EMEA-SALES)` published in Frappe writes a row to `dimension_mappings.csv` and, after rebuild, `stg_gl_entries` emits `CC-EMEA-SALES` for those rows.
3. A `dim_cost_center` value present in source with **no** mapping appears unchanged in `stg_gl_entries` (passthrough), not NULL/empty.
4. `gold_trial_balance` grouped by `dim_cost_center` returns one consolidated row per canonical value across LEs on different `erp_source` values.
5. `dbt build` passes all existing tests with zero regressions; a new test `test_dimension_mappings_unique.sql` asserts uniqueness of `(dimension, erp_source, source_value)` among published rows.
6. `gold_unmapped_dimension_values` returns exactly the distinct source values lacking a published mapping.
7. Publishing/Unpublishing a `Dimension Mapping` triggers a scoped rebuild via `apply_and_rebuild()` and is gated by `check_epm_admin()`.
8. Structural test in `test_dimension_mapping.py` confirms the doctype fields, autoname, and EPM Admin permissions.

## Open Questions

- Should `dim_harmonize()` join the seed per-dimension (simple, N joins) or pivot the seed to one row per source-key (flat, one join)? Default to the join-per-dimension form unless adapter SQL becomes unwieldy.
- Do we need a `default_canonical_value` fallback per dimension for ERPs that don't carry that dimension at all, or is empty-string passthrough sufficient?
- Should unmapped values block a high-risk consolidation build (preflight gate) or only warn? Leaning warn-only to avoid blocking close.
