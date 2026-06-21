# PRD: Allocated Layer

**Status:** Design — proposed
**Date:** 2026-06-16
**Phase:** Phase 6 — Analytical Gaps (Allocation Enhancements)
**Repos:** `konsolidat` (dbt models/macros, `clickhouse/init-db.sql`, Cube schema), `konsol` (Allocation Rule / Allocation Run doctypes)
**Addendum:** [PRD-ALLOCATED-LAYER-ADDENDUM.md](PRD-ALLOCATED-LAYER-ADDENDUM.md) — grain spec, FCTB boundary, run semantics, build order (2026-06-21)

## Problem

Allocation results currently live in `epm_gold` alongside source-of-truth data
(GL actuals, bottom-up budgets). This creates three problems:

1. **No clean separation** — you can't query "actuals before allocations" vs
   "fully loaded" without filtering on allocation_rule_id presence.
2. **No budget allocation** — the engine only reads from `gold_trial_balance`
   (actuals). There's no way to allocate top-down budget targets from HQ to
   local entities.
3. **No envelope reconciliation** — after HQ pushes a budget target down,
   there's nothing comparing the top-down target to the bottom-up detail.

## Solution

Introduce `epm_allocated` as a new schema/layer that holds **all** allocation
output — both actuals and budget/forecast. Gold stays clean.

```
epm_gold (source of truth)          epm_allocated (management overlay)
├── gold_trial_balance              ├── alloc_results
├── gold_spread_budget              ├── alloc_audit_trail
├── gold_scenario_trial_balance     ├── alloc_fully_loaded_tb
└── ...                             └── alloc_budget_reconciliation
```

## Layer contract

| Property | epm_gold | epm_allocated |
|----------|----------|---------------|
| Source | GL, budgets, scenarios | Allocation engine output |
| Grain | account x entity x period | rule x source x target x period x scenario |
| Mutability | Append-only (dbt rebuild) | Wipe-and-reload per allocation run |
| Scenario | Implicit (ACTUAL) or explicit | Always explicit via scenario_id |
| Audit | None (fact data) | Full: run_id, run_by, run_at, reversal |

## Changes

### 1. New ClickHouse schema

Add to `clickhouse/init-db.sql`:

```sql
CREATE DATABASE IF NOT EXISTS epm_allocated;
```

### 2. Allocation Rule — add source_scenario field

**Doctype change** (Allocation Rule):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| source_scenario | Select | ACTUAL | ACTUAL, BUDGET, FORECAST |

**Behavior**: Determines which source the engine reads from.
- `ACTUAL` → `gold_trial_balance`
- `BUDGET` → `gold_scenario_trial_balance WHERE scenario_id = 'BUDGET'`
- `FORECAST` → `gold_scenario_trial_balance WHERE scenario_id = 'FORECAST'`

> **Note (FORECAST is contingent):** `gold_scenario_trial_balance` emits only `ACTUAL` and `BUDGET`
> branches today; `FORECAST` rows exist only once forecast write-back data lands in `epm_staging`.
> Ship `ACTUAL`/`BUDGET` in v1 and treat `FORECAST` as enabled-when-data-exists (see Open Questions).

### 3. dbt models — new `allocated` folder

Move allocation models from `models/gold/` to `models/allocated/` and add
scenario support.

```
dbt_project/models/allocated/
├── alloc_results.sql              -- core allocation output (all scenarios)
├── alloc_audit_trail.sql          -- run traceability
├── alloc_fully_loaded_tb.sql      -- gold TB + allocated amounts joined
└── alloc_budget_reconciliation.sql -- top-down target vs bottom-up detail
```

**alloc_results.sql** — replaces `gold_allocation_results.sql`

Add `scenario_id` column to output. The multistep macro reads source based on
rule's `source_scenario`:

```
scenario_id | allocation_rule_id | source_account | target_cost_center | allocated_amount
ACTUAL      | ALLOC_001          | 7100           | BU-INDIA           | 300000
BUDGET      | ALLOC_001          | 7100           | BU-INDIA           | 320000
```

**alloc_fully_loaded_tb.sql** — new model

```sql
-- Actuals: gold TB + allocated actuals
SELECT *, 'base' as amount_type FROM gold_trial_balance
UNION ALL
SELECT *, 'allocated' as amount_type FROM alloc_results WHERE scenario_id = 'ACTUAL'

-- Same pattern for budget scenario
```

Enables reporting with/without allocations by filtering on `amount_type`.

**alloc_budget_reconciliation.sql** — new model

```sql
-- Per entity per year: top-down target vs bottom-up budget
SELECT
    r.data_area_id,
    r.fiscal_year,
    r.target_cost_center   AS entity,
    SUM(r.allocated_amount) AS topdown_target,
    COALESCE(b.bottomup_total, 0) AS bottomup_total,
    SUM(r.allocated_amount) - COALESCE(b.bottomup_total, 0) AS gap
FROM alloc_results r
LEFT JOIN (
    SELECT data_area_id, fiscal_year, SUM(period_amount) AS bottomup_total
    FROM gold_spread_budget
    GROUP BY data_area_id, fiscal_year
) b ON r.data_area_id = b.data_area_id AND r.fiscal_year = b.fiscal_year
WHERE r.scenario_id = 'BUDGET'
GROUP BY 1, 2, 3
```

> **Grain note:** this is an **annual** reconciliation — the top-down side sums `allocated_amount` over
> all periods/targets per entity-year, against the entity-year bottom-up total. It assumes the alloc
> "entity" (`target_cost_center`) aligns with `gold_spread_budget`'s entity dimension; confirm that
> mapping (see Open Questions). A period-level reconciliation, if needed, is a separate model.

### 4. Macro changes — scenario-aware source

The allocation engine is **set-based SQL** — rules are joined via `cross join stepN_rule as r`, and the
trial balance is the `tb_base` CTE consumed by every step. So the source is made scenario-aware by changing
`tb_base` itself (and joining each rule on `scenario_id`), **not** by a per-rule Jinja conditional.

**allocation_engine_multistep.sql:**

Today `tb_base` reads actuals only:
```sql
... from {{ ref('gold_trial_balance') }}
```

Change `tb_base` to read the scenario-keyed trial balance, carrying `scenario_id`, and join each rule to
its `source_scenario`:
```sql
with tb_base as (
    select scenario_id, data_area_id, fiscal_year, fiscal_period,
           main_account, amount
    from {{ ref('gold_scenario_trial_balance') }}
)
-- ... each step's pool then joins its rule on the matching scenario:
... cross join stepN_rule as r
where pool.scenario_id = r.source_scenario
```

This works because `gold_scenario_trial_balance` already unions **all three** scenarios in one model —
`ACTUAL` (from `gold_trial_balance`), `BUDGET` (from `silver_budget_entries`), and write-back scenarios
incl. `FORECAST` (from `epm_staging.budget_input`) — so a single source covers every `source_scenario`
with **no double-count** (ACTUAL is not added twice). `source_scenario` comes from the `allocation_rules`
seed/table — add the column to the seed CSV and the Frappe doctype sync.

Same change applies to `allocation_engine_reciprocal.sql` and `allocation_engine_tiered.sql`.

### 5. dbt_project.yml

```yaml
models:
  open_epm:
    allocated:
      +schema: epm_allocated
      +tags: ['allocated', 'domain:consolidation']
      alloc_results:
        +materialized: table
      alloc_audit_trail:
        +materialized: table
      alloc_fully_loaded_tb:
        +materialized: table
      alloc_budget_reconciliation:
        +materialized: table
```

### 6. Cube.js views

**cube/schema/allocation_results.yml** — update table reference:
```yaml
sql_table: epm_allocated.alloc_results
```

Add `scenario_id` dimension.

**cube/schema/alloc_budget_reconciliation.yml** — new:
```yaml
cubes:
  - name: budget_reconciliation
    sql_table: epm_allocated.alloc_budget_reconciliation
    dimensions:
      - name: data_area_id
        sql: data_area_id
        type: string
      - name: entity
        sql: entity
        type: string
      - name: fiscal_year
        sql: fiscal_year
        type: number
    measures:
      - name: topdown_target
        sql: topdown_target
        type: sum
      - name: bottomup_total
        sql: bottomup_total
        type: sum
      - name: gap
        sql: gap
        type: sum
```

**cube/views/v_fully_loaded_tb.yml** — new:

Exposes the fully loaded trial balance (base + allocated) to Excel.

### 7. Frappe doctype changes

**Allocation Rule** — add field:
- `source_scenario` (Select: ACTUAL / BUDGET / FORECAST, default ACTUAL)
- Sync to ClickHouse: add column to `epm_staging.allocation_rules`

**Allocation Run** — add field:
- `scenario_id` (Data, read-only) — auto-populated from the rules executed
  in that run. If a run mixes scenarios, use the dominant one or require
  single-scenario runs.

### 8. Migration of existing data

Both `alloc_results` and `alloc_audit_trail` **relocate existing gold models** (`gold_allocation_results`,
`gold_allocation_audit_trail`) into `epm_allocated` and add `scenario_id` — they are not net-new audit
infrastructure. (The "Audit: None → Full" row in the Layer contract refers to gold *fact* data, not the
pre-existing allocation audit trail.)

- `gold_allocation_results` → keep as deprecated alias (view over
  `epm_allocated.alloc_results WHERE scenario_id = 'ACTUAL'`) for one
  release cycle, then drop.
- `gold_allocation_audit_trail` → same pattern.

## Workflow

### Actuals allocation (current workflow, new layer)

1. GL data lands in `epm_gold.gold_trial_balance`
2. Finance runs allocation → results go to `epm_allocated.alloc_results`
   with `scenario_id = 'ACTUAL'`
3. `alloc_fully_loaded_tb` shows entity P&L with allocated overhead
4. Excel queries Cube.js for fully loaded or base-only view

### Budget allocation (new workflow)

1. CFO enters group-level budget in `gold_spread_budget` (or directly as
   a scenario in `gold_scenario_trial_balance`)
2. Creates allocation rules with `source_scenario = 'BUDGET'`
3. Runs allocation → results go to `epm_allocated.alloc_results` with
   `scenario_id = 'BUDGET'`
4. Local entities see their top-down targets via Cube.js
5. Local entities enter bottom-up budgets via Budget Input
6. `alloc_budget_reconciliation` shows the gap: top-down vs bottom-up
7. Iterate until gap is zero (or accepted)

## Scope and sequencing

| PR | Contents | Size |
|----|----------|------|
| 1 | `epm_allocated` schema + move `alloc_results` and `alloc_audit_trail` to new layer + `scenario_id` column + deprecation views in gold | Medium |
| 2 | `source_scenario` on Allocation Rule doctype + macro changes for scenario-aware source | Small |
| 3 | `alloc_fully_loaded_tb` model + Cube.js view | Small |
| 4 | `alloc_budget_reconciliation` model + Cube.js view | Small |
| 5 | Workflow governance (run validation, target-vs-detail warnings) | Medium |

PRs 1-2 are the foundation. PRs 3-4 are independent reporting models.
PR 5 is optional guardrails.

## Out of Scope

- **Product costing / COGS** — the allocated layer is entity-grain, not
  product-grain. Product cost allocation is a separate concern.
- **Automated scheduling** — allocation runs are manual (triggered by finance).
  Scheduled runs are a future enhancement.
- **Multi-currency** — allocations use reporting currency. FX translation
  happens upstream in gold.

## Acceptance Criteria

1. `epm_allocated` database exists (created by `clickhouse/init-db.sql`) and `dbt ls --select tag:allocated`
   returns the 4 models (`alloc_results`, `alloc_audit_trail`, `alloc_fully_loaded_tb`,
   `alloc_budget_reconciliation`).
2. `alloc_results` carries a `scenario_id` column; an `ACTUAL`-sourced rule and a `BUDGET`-sourced rule on
   the same source produce rows distinguished only by `scenario_id`.
3. The gold deprecation aliases (`gold_allocation_results`, `gold_allocation_audit_trail`) return rows
   **identical** to the pre-migration models for `scenario_id = 'ACTUAL'` (no regression for existing
   consumers).
4. `alloc_fully_loaded_tb` filtered to `amount_type = 'base'` equals `gold_trial_balance`; including
   `'allocated'` adds allocated overhead with no double-count.
5. For a balanced test fixture (top-down target == bottom-up detail), `alloc_budget_reconciliation.gap`
   sums to **zero** per entity-year.
6. `source_scenario` on Allocation Rule syncs to `epm_staging.allocation_rules`, and the engine reads its
   base from it — verified across the multistep, reciprocal, and tiered macros.
7. Existing actuals-allocation output is unchanged after the move to `epm_allocated` (regression gate).

## Open Questions

1. **Mixed-scenario runs.** §7 leaves "if a run mixes scenarios, use the dominant one or require
   single-scenario runs" unresolved — which is it? Determines `Allocation Run.scenario_id` semantics.
2. **FORECAST source.** `gold_scenario_trial_balance` carries `ACTUAL`/`BUDGET` plus any write-back
   scenarios from `epm_staging.budget_input`; `FORECAST` flows automatically once forecast write-back rows
   exist. Open only on timing: ship `ACTUAL`/`BUDGET` in v1, enable `FORECAST` when that data lands?
3. **Reconciliation grain / entity alignment.** Confirm `target_cost_center` (alloc "entity") aligns with
   `gold_spread_budget`'s entity dimension, and that an annual (period-collapsed) reconciliation is the
   intended grain.

> **Resolved:** §4 macro shape — the engine is set-based, so `tb_base` reads the scenario-keyed
> `gold_scenario_trial_balance` and each rule joins on `scenario_id` (single source, no double-count).
> Folded into §4 above.
