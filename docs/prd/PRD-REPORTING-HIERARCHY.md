# PRD: Reporting Hierarchy

**Status:** In Progress  
**Date:** 2026-06-21  
**Phase:** Phase 3 — Management reporting  
**Repos:** `konsolidat` (dbt/data stack), `konsol` (Frappe app)

## Problem

Finance teams report on **management hierarchies** (BU → Division → Region) that differ from the **legal-entity consolidation tree**. Consultants deploying Konsolidat lack deep warehouse architecture skills; without a governed product path they:

- Put BUs in `Consolidation Group` (wrong semantics — triggers FX/IC/NCI)
- Fork dbt gold models per client
- Skip `Dimension Mapping` and get fragmented rollups

Dimension Harmonization (PRD-DIMENSION-HARMONIZATION) delivers flat canonical values only — no parent/child rollups.

## Solution

Add **Reporting Hierarchy**: a Frappe-managed tree of dimension members with publish lifecycle, seed sync, scoped PBR (`reporting`), and generic dbt rollup models.

### Config pipeline (enforced order)

```
Dimension (axis on GL)
  → Dimension Mapping (ERP codes → canonical leaf values)
  → Reporting Hierarchy (parent/child rollups on canonical values)
  → Publish → PBR (scope: reporting)
```

## Scope

### 1. `Reporting Hierarchy` doctype (`konsol` — header)

| Field | Type | Notes |
|-------|------|-------|
| `hierarchy_name` | Data | Unique key, e.g. `MGMT_2026` |
| `dimension` | Link → `Dimension` | One axis per hierarchy |
| `label` | Data | Display name |
| `effective_from` / `effective_to` | Date | Reorg versioning |
| `is_default` | Check | Default tree for this dimension |
| `status` | Select | Draft / Published / Inactive |

Publish regenerates `reporting_hierarchies.csv` and requests PBR `reporting`.

### 2. `Reporting Hierarchy Member` doctype (`konsol` — tree, `is_tree=1`)

| Field | Type | Notes |
|-------|------|-------|
| `reporting_hierarchy` | Link → header | Required |
| `parent_member` | Link self | NSM parent |
| `member_code` | Data | Canonical value (required for leaves) |
| `member_label` | Data | Display |
| `is_group` | Check | `1` = rollup-only node |

Validation:

- Header `dimension` must be Published before header Publish
- Leaf (`is_group=0`): `member_code` required; unique within hierarchy
- Group (`is_group=1`): aggregates children only; `member_code` (auto from the label when blank) is also unique within hierarchy, since formulas and the closure find a node by its code
- Cannot set `data_area_id` — legal structure uses `Consolidation Group`

### 3. `reporting_hierarchies` seed (`konsolidat`)

Flattened tree rows generated from Published headers + members:

`hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to`

`effective_from` / `effective_to` (String) are the header's dates. `member_effective_from` / `member_effective_to` (`Date32`, default `1900-01-01` / `2299-12-31`, where `2299-12-31` means open) are the window of one member **tranche** (see 3a).

### 3a. Dated members: tranches (konsol#220)

A member row is one **tranche** of a code: the code's label, parent and group flag for the dates `member_effective_from` .. `member_effective_to`. Nobody edits a node's history in place. A change adds a second row for the same code:

- **Rename:** tranche 1 has label "Alpha" and runs to 2024-12-31; tranche 2 has label "Alpha New" and runs from 2025-01-01 to open. Same code, same parent.
- **Move:** a leaf sits under `E` until 2024-12-31, then under `B` from 2025-01-01. Same code, different `parent_member_code`.
- **End (disposal, closure):** the only tranche has a closed `member_effective_to`. No row covers later dates, so the node does not exist after that date.

Rules that konsol enforces: tranches of one code never overlap, and a child's window must lie inside the windows of its parent code's tranches. A member with no dates is one tranche running from `1900-01-01` to `2299-12-31`.

**Closure window.** `gold_reporting_hierarchy_closure` gives every ancestor ↔ descendant link a `valid_from` / `valid_to` (its last two columns). The base row takes the member tranche's window. Each recursive step joins the parent code's tranche(s) whose window overlaps the current one, and narrows the window to the intersection (`greatest` of the starts, `least` of the ends). `ancestor_label`, `ancestor_is_group` and `ancestor_level` come from that parent tranche. A link holds only inside its window. So a moved leaf rolls to `E` inside `E`'s window and to `B` after the move, never to both at once.

**Resolved per period.** Every node model resolves the tree separately for each trial-balance period. It takes the period's `end_date` from `epm_staging.fiscal_periods` (the last day of the month when the period is not listed). It uses only the leaf tranche whose `member_effective_from` .. `member_effective_to` covers that date, and only the closure links whose `valid_from` .. `valid_to` covers it. Each period therefore rolls up the tree **as it was in that period, with that period's labels**. FY2018 shows the old parent and the old name; FY2025 shows the new ones; an ended node has no rows after its end date. This applies to `gold_tb_at_hierarchy_node`, `gold_budget_at_hierarchy_node`, `gold_variance_at_hierarchy_node` and `gold_unassigned_hierarchy_members`, as well as the tests `assert_hierarchy_rollup_ties` and `assert_variance_node_single_budget`.

### 4. dbt models (`konsolidat`)

| Model | Tag | Role |
|-------|-----|------|
| `gold_reporting_hierarchy` | `domain:reporting` | Published hierarchy member tranches (with `member_effective_from` / `member_effective_to`) |
| `gold_reporting_hierarchy_closure` | `domain:reporting` | Ancestor ↔ descendant bridge; each link has a `valid_from` / `valid_to` window |
| `gold_tb_at_hierarchy_node` | `domain:reporting` | TB rolled up to any node, on the tree as it was in each period |
| `gold_budget_at_hierarchy_node` | `domain:reporting` | Budget rolled up to any node, on the tree as it was in each period |
| `gold_variance_at_hierarchy_node` | `domain:reporting` | Variance rolled up to any node, on the tree as it was in each period |
| `gold_unassigned_hierarchy_members` | `domain:reporting` | GL values with no leaf tranche of the default hierarchy covering the period (per `fiscal_year`, `fiscal_period`) |

### 5. Build governance

- New Build Domain: `reporting` (`requires_raw_data=1`)
- PBR scope `reporting` → `dbt build --select +tag:domain:reporting`
- Publish uses `request_governed_rebuild(scope="reporting")`

### 6. API

- `get_reporting_hierarchy_tree(hierarchy_name)` — nested JSON for Excel/reports

## Out of Scope (v1)

- Multiple parents per node (matrix) — use alternate hierarchy or allocations
- Per-legal-entity different trees on same dimension
- Auto-suggest members from GL
- Excel import UI (v1.1)

## Acceptance Criteria

1. Demo fixture hierarchy on `dim_business_unit` loads and publishes
2. `dbt build --select +tag:domain:reporting` passes on demo data
3. Sum at group node = sum of the leaves under it in the same period, per account (`assert_hierarchy_rollup_ties`, via the closure links valid at the period's end date)
4. `gold_unassigned_hierarchy_members` has no row for a period when every GL BU in that period is covered by a leaf tranche of the default hierarchy
5. Publish blocked when linked Dimension is not Published
6. Consultants can complete setup without editing dbt/SQL