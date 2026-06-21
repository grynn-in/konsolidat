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
- Group (`is_group=1`): aggregates children only
- Cannot set `data_area_id` — legal structure uses `Consolidation Group`

### 3. `reporting_hierarchies` seed (`konsolidat`)

Flattened tree rows generated from Published headers + members:

`hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status`

### 4. dbt models (`konsolidat`)

| Model | Tag | Role |
|-------|-----|------|
| `gold_reporting_hierarchy` | `domain:reporting` | Published hierarchy nodes |
| `gold_reporting_hierarchy_closure` | `domain:reporting` | Ancestor ↔ descendant bridge |
| `gold_tb_at_hierarchy_node` | `domain:reporting` | TB rolled up to any node |
| `gold_unassigned_hierarchy_members` | `domain:reporting` | GL values missing from default hierarchy |

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
3. Sum at group node = sum of child leaves (`assert_hierarchy_rollup_ties`)
4. `gold_unassigned_hierarchy_members` empty when all GL BUs are in hierarchy
5. Publish blocked when linked Dimension is not Published
6. Consultants can complete setup without editing dbt/SQL