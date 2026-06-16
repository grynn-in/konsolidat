# PRD: Allocated Layer

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

### 4. Macro changes — scenario-aware source

**allocation_engine_multistep.sql**:

Current pool CTE reads:
```sql
FROM {{ ref('gold_trial_balance') }}
```

Change to:
```sql
{% if rule.source_scenario == 'ACTUAL' %}
  FROM {{ ref('gold_trial_balance') }}
{% else %}
  FROM {{ ref('gold_scenario_trial_balance') }}
  WHERE scenario_id = '{{ rule.source_scenario }}'
{% endif %}
```

The `source_scenario` value comes from the allocation_rules seed/table. Add
the column to the seed CSV and the Frappe doctype sync.

Same change applies to `allocation_engine_reciprocal.sql` and
`allocation_engine_tiered.sql`.

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

## Non-goals

- **Product costing / COGS** — the allocated layer is entity-grain, not
  product-grain. Product cost allocation is a separate concern.
- **Automated scheduling** — allocation runs are manual (triggered by finance).
  Scheduled runs are a future enhancement.
- **Multi-currency** — allocations use reporting currency. FX translation
  happens upstream in gold.
