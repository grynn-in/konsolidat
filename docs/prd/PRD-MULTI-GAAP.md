# PRD: Multi-GAAP / Dual Reporting

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 6.2 — Analytical Gaps (Multi-GAAP / Dual Reporting)
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app)

## Problem

- Every gold model produces exactly one trial balance. There is no way to report the same entity under both its statutory **local GAAP** books and group **IFRS** at the same time. Multinationals must file local statutory accounts while the parent consolidates under IFRS — today that requires a second pipeline run with hand-edited adjustment seeds.
- Adjustments live in flat seeds (`consolidation_adjustments.csv`, `ic_elimination_rules.csv`) with no notion of *which* accounting standard they belong to. An IFRS-only revaluation (e.g. IFRS 16 lease capitalisation, IAS 19 remeasurement) cannot be applied to one standard and excluded from another.
- Source GL (`stg_gl_entries` → `silver_gl_entries`) is the local-books truth. There is no carrier for GAAP-specific overlays, so `gold_trial_balance` and downstream consolidation (`gold_consolidated_trial_balance`, `gold_fully_consolidated_tb`) implicitly assume a single standard.
- The dimension registry (Phase 2) drives all gold grain via `dim_select()` / `dim_group_by()`, but there is no `reporting_standard` dimension, so the warehouse cannot slice or balance per standard.

## Solution

Introduce a first-class `reporting_standard` dimension (`LOCAL_GAAP`, `IFRS`) registered in the Phase 2 Dimension Registry, carry it through staging → gold, and add a per-standard **GAAP adjustment** layer so each gold trial balance is emitted and balances independently per standard.

## Scope

### 1. `reporting_standard` Dimension (registry-driven)

Register via the Frappe `Dimension` doctype so `dbt_config.py` emits it into `dbt_project.yml` `vars.dimensions`, exactly like `dim_cost_center`:

| Field | Value |
|---|---|
| `dimension_name` | `reporting_standard` |
| `source_column` | `reporting_standard` |
| `label` | "Reporting Standard" |
| `cube_type` | `string` |
| `in_budget` | `false` |
| `allocation_role` | (none) |

Allowed members seeded: `LOCAL_GAAP`, `IFRS`. Local GL carries `reporting_standard = 'LOCAL_GAAP'` (the books-of-record default); IFRS rows are derived = local base + IFRS-only adjustments.

### 2. GAAP Adjustment Rules seed (`konsolidat`)

New seed `gaap_adjustment_rules.csv` — the per-standard analogue of `consolidation_adjustments.csv`, tagged by target standard:

| Field | Type | Description |
|---|---|---|
| `rule_id` | String | Unique rule ID (e.g. `GAAP-IFRS16-001`) |
| `reporting_standard` | String | Target standard: `IFRS` or `LOCAL_GAAP` |
| `data_area_id` | String | Entity, or `GROUP` for group-level |
| `fiscal_year` | UInt16 | Year |
| `fiscal_period` | UInt8 | Period |
| `debit_account` | String | Account to debit |
| `credit_account` | String | Account to credit |
| `amount` | Decimal(18,2) | Adjustment amount (balanced pair) |
| `description` | String | Narrative (e.g. "IFRS 16 ROU asset / lease liability") |

Rules apply **only** to rows of the matching `reporting_standard`; `LOCAL_GAAP` output equals raw GL unless an explicit `LOCAL_GAAP` rule exists.

### 3. Staging & base gold carry the dimension

| Model | Change |
|---|---|
| `stg_gl_entries.sql` (canonical) | Emit `reporting_standard = 'LOCAL_GAAP'` literal column |
| `silver_gl_entries` | Pass `reporting_standard` through (covered by `dim_select_from_source()`) |
| `gold_trial_balance.sql` | Already groups by `{{ dim_select() }}`/`{{ dim_group_by() }}` — no edit; picks up `reporting_standard` automatically once registered |

### 4. New GAAP overlay model

New `gold_gaap_adjustments.sql` (tag `consolidation`): reads `gaap_adjustment_rules` seed, produces one balanced debit/credit row pair per rule with `adjustment_type = 'gaap'` and the rule's `reporting_standard`. Grain matches `gold_consolidation_adjustments` plus the `reporting_standard` column.

### 5. Per-standard output

| Model | Change |
|---|---|
| `gold_consolidated_trial_balance.sql` | Group/translate per `reporting_standard` (already in `dim_*` grain) |
| `gold_fully_consolidated_tb.sql` | Add 5th union layer `gold_gaap_adjustments` (`adjustment_type='gaap'`); all four existing layers (`entity`, `ic_elimination`, `cta`, topside) inherit `reporting_standard` from their grain |

`IFRS` consolidated TB = `LOCAL_GAAP` base + IFRS GAAP overlay + consolidation layers. Consumers filter on the `reporting_standard` dimension via the standard `dim_select()` grain (and the Cube.js layer / `=EPM()` once Phase 2.4 API Generalisation exposes the generic `dimensions` dict).

### 6. Tests (dbt schema tests in `_gold__models.yml`)

| Test | Assertion |
|---|---|
| `assert_local_gaap_equals_raw_gl` | `LOCAL_GAAP` `gold_trial_balance` sums tie to `silver_gl_entries` (no overlay applied) |
| `assert_each_standard_balances` | For each `reporting_standard`, `sum(debit) − sum(credit) = 0` (within 0.01) on `gold_fully_consolidated_tb` |
| `assert_gaap_rule_pairs_balanced` | Each `gaap_adjustment_rules` row pair nets to zero in `gold_gaap_adjustments` |
| `accepted_values(reporting_standard)` | Only `LOCAL_GAAP`, `IFRS` appear in gold output |

## Out of Scope

- Standards beyond `LOCAL_GAAP` and `IFRS` (US GAAP / local statutory variants) — additional members are a seed/registry data change, not new code.
- Country-by-country statutory chart-of-accounts mapping (separate account remapping concern).
- Disclosure-level note reconciliation between standards (this PRD covers the trial-balance numbers, not narrative GAAP-to-GAAP bridges).
- IFRS technical adjustment *content* (IFRS 16/IAS 19 calculation logic) — this PRD delivers the carrier and rule mechanism; specific adjustment values are user-supplied seed data.
- A Frappe UI for authoring GAAP rules — seed CSV for v1; doctype-driven authoring deferred.

## Acceptance Criteria

1. `reporting_standard` appears in `dbt_project.yml` `vars.dimensions` after saving the `Dimension` doctype, with no manual YAML edit.
2. `dbt build` produces `gold_trial_balance` and `gold_fully_consolidated_tb` rows where `reporting_standard` is populated on every row.
3. `gold_gaap_adjustments` is a queryable model; `dbt ls --select tag:consolidation` includes it.
4. Querying `gold_fully_consolidated_tb WHERE reporting_standard='LOCAL_GAAP'` returns numbers equal to raw GL + consolidation layers, with zero GAAP overlay applied.
5. `assert_each_standard_balances` passes — `LOCAL_GAAP` and `IFRS` each net to zero independently.
6. `assert_local_gaap_equals_raw_gl` passes.
7. Adding a new `IFRS` row to `gaap_adjustment_rules.csv` and rebuilding changes only `IFRS` output; `LOCAL_GAAP` totals are unchanged.

## Open Questions

- Should `gold_consolidated_ytd` and the statement models (`gold_balance_sheet`, `gold_pnl_by_period`) default to a single standard, or always require an explicit `reporting_standard` filter? (Proposed: default `IFRS` for group statements, `LOCAL_GAAP` for entity statements.)
- Do CTA (`gold_fx_revaluation`) and IC elimination rules ever differ between standards, or are they standard-agnostic and applied identically to both? (Proposed v1: standard-agnostic; revisit if a customer needs GAAP-specific elimination.)
- Should `gaap_adjustment_rules` migrate to a Frappe doctype (like the Dimension/Measure registries) so controllers author IFRS adjustments in Desk rather than editing CSV?
