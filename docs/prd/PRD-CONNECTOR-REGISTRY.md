# PRD: Connector Registry (Frappe)

**Status:** Implemented (konsol #15)
**Date:** 2026-06-13
**Phase:** Phase 3 — Multi-ERP (registry)
**Repos:** `konsol` (Frappe app — new doctype + dbt var generation), `konsolidat` (dbt `erp_sources` var, per-ERP adapters)

## Problem

Multi-ERP plumbing exists but nothing registers *which* ERP instances are actually live, who they serve, or how they map to canonical dimensions:

- `erp_sources` in `dbt_project.yml` is hand-edited (`canonical-staging-schema.md` §`erp_sources Variable`). There is no Frappe-managed source of truth, so the list drifts from reality and adding an ERP is a manual YAML edit.
- `EPM Settings` holds a **single** `airbyte_connection_id`. A 50–500 legal-entity deployment spanning D365 F&O, D365 BC, SAP, and ERPNext needs **many** connections, each scoped to a set of legal entities — there is nowhere to store them.
- Dimension harmonization (roadmap Phase 3) needs per-connector dimension mappings (SAP/ERPNext "each connector provides its own dimension mapping"), but `dim_select_from_source()` only knows the global `Dimension` registry, not which `source_column` a given ERP uses.
- `Pipeline Build Request` preflight reads one global `last_airbyte_sync_status` from `EPM Settings`; it cannot tell whether a *specific* connector synced, so it cannot block a build whose entities have stale data.

## Solution

Add a Frappe `Connector` doctype (module `Pipeline`) that registers each ERP connector instance — ERP type, legal entities served, Airbyte connection id, dimension-mapping rows, and sync status — and on save regenerates `dbt_project.yml` `vars.erp_sources` (mirroring how `Dimension`/`Measure` drive vars via `dbt_config.regenerate_vars()`). This becomes the single source of truth that drives which adapters run and feeds connector-aware preflight into Build Governance.

## Scope

### 1. `Connector` doctype (`konsol`, module `Pipeline`)

Naming follows existing pipeline doctypes (`Pipeline Run`, `Pipeline Build Request`). `autoname: CONN-.#####`.

| Field | Type | Notes |
|---|---|---|
| `connector_name` | Data (reqd) | Display name, e.g. "SAP S/4HANA — DACH" |
| `erp_type` | Select (reqd) | `d365_fo`\n`d365_bc`\n`sap_s4`\n`sap_ecc`\n`sap_b1`\n`erpnext` — matches `erp_source` enum in canonical schema |
| `enabled` | Check | If 0, excluded from `erp_sources`; adapter does not run |
| `airbyte_connection_id` | Data | Per-connector Airbyte connection (overrides `EPM Settings`) |
| `airbyte_source` | Data (read_only) | e.g. "Airbyte SAP OData" (informational, from roadmap connector table) |
| `dbt_adapter_prefix` | Data (read_only) | e.g. `stg_d365_fo` — derived from `erp_type` |
| `legal_entities` | Table → `Connector Legal Entity` | Which `entity_id`s this connector serves |
| `dimension_mappings` | Table → `Connector Dimension Map` | Per-ERP source_column for each canonical dimension |
| `last_sync_at` | Datetime (read_only) | Per-connector, set by webhook |
| `last_sync_status` | Select (read_only) | `\nSuccess\nFailed\nPartial\nRunning` (mirrors `EPM Settings`) |
| `last_sync_rows` | Int (read_only) | Rows from last sync |

### 2. Child tables

**`Connector Legal Entity`** (`istable: 1`)

| Field | Type | Notes |
|---|---|---|
| `entity_id` | Data (reqd) | Maps to canonical `stg_legal_entities.entity_id` / `stg_gl_entries.entity_id` |
| `entity_name` | Data | Display only |

**`Connector Dimension Map`** (`istable: 1`)

| Field | Type | Notes |
|---|---|---|
| `dimension` | Link → `Dimension` (reqd) | Canonical dimension (`dim_cost_center`, `dim_department`, …) |
| `source_column` | Data (reqd) | This ERP's raw column name feeding that dimension |

### 3. dbt var generation (`dbt_config.py`)

- Add `_build_erp_sources_vars()` returning `[erp_type for c in Connector if c.enabled]`, deduped, stable-ordered.
- `regenerate_vars()` adds `new_vars["erp_sources"] = [...]` alongside existing `dimensions` / `base_measures` / fiscal vars.
- `Connector.on_update` / `on_trash` call `regenerate_vars()` so canonical models UNION exactly the enabled adapters (per `canonical-staging-schema.md` step "Add the ERP key to `erp_sources`").

### 4. Per-connector sync status + preflight (Build Governance tie-in)

- Extend the Airbyte webhook (`airbyte_sync_complete()`) to resolve `airbyte_connection_id` → `Connector` and update that connector's `last_sync_*` (falling back to `EPM Settings` if unmatched).
- `Pipeline Build Request` preflight: for raw-dependent scopes (`actuals`, `scenarios`, `consolidation`), block if **any enabled** connector serving the build's entities has `last_sync_status` in (`Failed`, `Running`) or null — surfaced in the existing `preflight_result` field.

### 5. Roles & permissions

Reuse Build Governance EPM roles: `System Manager` + `EPM Admin` full CRUD; `EPM Analyst` read/create; `EPM User` read.

## Out of Scope

- Writing the actual per-ERP adapter SQL (D365 BC, SAP, ERPNext) — covered by PRDs 32–36.
- Building/configuring Airbyte connections themselves — registry only **references** an existing `airbyte_connection_id`.
- ClickHouse sharding by `entity_id` and incremental CDC extraction (roadmap "Scale Architecture", separate work).
- Runtime dimension *value* harmonization (mapping CC001↔1000) — registry stores column mappings only; value crosswalks are Dimension Harmonization scope.
- Consuming `dimension_mappings` inside `dim_select_from_source()` — registry persists the mapping; macro changes land with Dimension Harmonization.

## Acceptance Criteria

1. Creating an enabled `Connector` with `erp_type=sap_s4` and saving regenerates `dbt_project.yml` so `vars.erp_sources` contains `sap_s4`; disabling it removes `sap_s4` on next save.
2. `vars.erp_sources` produced by `regenerate_vars()` contains exactly the distinct `erp_type` values of enabled connectors, in stable order, with no duplicates.
3. A `Connector` with two `Connector Legal Entity` rows persists both `entity_id`s and they round-trip via `frappe.get_doc`.
4. Webhook `airbyte_sync_complete()` for a known `airbyte_connection_id` updates that `Connector.last_sync_status`/`last_sync_at`/`last_sync_rows`, not `EPM Settings`.
5. A `Pipeline Build Request` with scope `actuals` is blocked at preflight when an enabled connector serving a target entity has `last_sync_status=Failed`; `preflight_result` names the failing connector.
6. `Connector Dimension Map` rejects save without both `dimension` and `source_column` (reqd validation).
7. `erp_type` Select options are exactly the six `erp_source` values in `canonical-staging-schema.md`.
8. Structural tests in `test_connector_registry.py` pass (doctype exists, child tables linked, `erp_sources` generation, permission matrix).

## Open Questions

- Should two enabled connectors of the **same** `erp_type` (e.g. two SAP S/4 tenants) collapse to one `erp_source` for dbt while remaining distinct registry rows? (Leaning yes — `erp_source` is per-ERP-product, not per-tenant.)
- Should overlapping `entity_id`s across connectors be a hard validation error or a warning? (Same entity from two ERPs is a real conflict for consolidation.)
- Does per-connector preflight need an entity→connector index, or is a full scan of enabled connectors acceptable at expected counts (<50 connectors)?
