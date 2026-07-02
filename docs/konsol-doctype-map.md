# Konsol — DocType Map

All **42 konsol doctypes** (excluding core Frappe), organized into 5 functional stacks along the EPM data flow. Stacks 1–2 are *configuration/governance* (Frappe is the source of truth; saves regenerate dbt vars + ClickHouse DDL). Stacks 3–5 are *financial logic* (budgeting, cost allocation, group consolidation) that dbt computes in ClickHouse off that registry. Updated doctype names as of 2026-07 (PRD-01–11).

```
ERP SOURCES (D365 F&O / ERPNext)
   │ Airbyte → epm_raw
   ▼
1. DATA PIPELINE ──► 2. EPM MODEL/REGISTRY ──► 3. BUDGET ──┐
                                            └► 4. ALLOCATION ┴► 5. CONSOLIDATION ──► OUTPUTS
                                                                                     (Excel add-in / API / Cube.js)
```

## Stacks + key sections

```
   ●DOC   ◦child-table   ⚙Single   👻Virtual(read-only proxy)

═══════════════ 1. DATA PIPELINE ═══════════════════════ module: pipeline ══
● Connector
    ├ Extract Credentials   ├ Extract Options   ├ Write-Back Credentials
    ├ Airbyte Provisioning  ├ Legal Entities    ├ Dimension Mappings
    └ Sync Status
    ◦ Connector Legal Entity        ◦ Connector Dimension Map
● Connector Health
    └ Last Error
● Pipeline Run
    ├ Extract (Airbyte)  ├ Transform (dbt)  ├ Steps  ├ Log  └ Error Details
    ◦ Run Step
● Build Approval
    ├ People  ├ Airbyte Sync Info  ├ Timing  └ Build Output
● Build Scope
● Build Model
⚙ EPM Settings
    ├ ClickHouse Connection   ├ Airbyte Connection
    ├ D365 F&O Budget Write-Back (Legacy)   ├ Airbyte Sync Status
    ├ dbt Configuration       └ Access Control

═══════════════ 2. EPM MODEL / REGISTRY ═════════════════════ module: epm ══
● Dimension                 └ Lifecycle
● Dimension Mapping         └ Lifecycle
● Measure                   └ Lifecycle
● Dataset
    ├ Measures & Dimensions  ├ Generation & Grain
    ├ Measure Reroute        └ Lifecycle
    ◦ Dataset Measure            ◦ Dataset Dimension
● Fiscal Period
● Scenario Definition
● Reporting Hierarchy       └ Lifecycle
● Reporting Hierarchy Member

═══════════════ 3. BUDGET ═══════════════════════════════════ module: epm ══
● Budget Cycle
● Budget Sheet
    ├ Lines  └ D365 Write-Back
    ◦ Budget Line
● Spread Profile
👻 Budget Cost Center
👻 Main Account Category

═══════════════ 4. ALLOCATION ════════════════════════ module: allocation ══
● Allocation Rule
    ├ Allocation Method (PRD-17/18)  ├ Allocation Tiers (PRD-20)  └ Details
    ◦ Allocation Tier
● Allocation Driver
● Allocation Run            └ Reversal

═══════════════ 5. CONSOLIDATION ══════════════════ module: consolidation ══
● Consolidation Group       └ Settings
● Ownership Period
    ├ Acquisition (PRD-11)  └ Disposal (PRD-12)
● Historical Equity Rate
● IC Balance
● IC Elimination Rule
    ├ Entity Patterns  ├ Unrealized Profit (PRD-15)  └ Details
● Consolidation Adjustment
    ├ Amounts  ├ Details  └ Workflow (PRD-16)
● Period Close
    ├ Summary  ├ Sign-off  ├ Timing  ├ Assertions  └ Log
    ◦ Assertion Result
```

Doctypes shown with only a name have no labeled section breaks (flat field lists).

## Reference table

| Doctype | Module | Kind | Purpose |
|---|---|---|---|
| Connector | pipeline | DOC | Registry of live ERP connector instances; source of truth for which ERPs feed the warehouse |
| Connector Legal Entity | pipeline | child | Legal entity_ids the connector serves |
| Connector Dimension Map | pipeline | child | Per-ERP dimension → column mappings |
| Connector Health | pipeline | DOC | Derived per-connector sync-health snapshot |
| Pipeline Run | pipeline | DOC | Creates + enqueues a background pipeline (Airbyte+dbt) job |
| Run Step | pipeline | child | Steps within a pipeline/build run |
| Build Approval | pipeline | DOC | Governed dbt build workflow (Draft → Approved → Built) |
| Build Scope | pipeline | DOC | Build-Governance domains (single source of truth) |
| Build Model | pipeline | DOC | Maps each gold dbt model to a Build Scope |
| EPM Settings | pipeline | Single | Global config: ClickHouse, Airbyte, dbt path, access control |
| Dimension | epm | DOC | EPM dimension config (metadata → dbt vars + ClickHouse DDL) |
| Dimension Mapping | epm | DOC | Crosswalk from raw ERP dimension value → canonical value |
| Measure | epm | DOC | EPM measure config (expressions) |
| Dataset | epm | DOC | Registry of ClickHouse fact tables for dynamic schema |
| Dataset Measure | epm | child | Allowed measure for a dataset |
| Dataset Dimension | epm | child | Dimension for a dataset |
| Fiscal Period | epm | DOC | Fiscal calendar config → dbt_project.yml vars |
| Scenario Definition | epm | DOC | Budget / forecast / other scenarios |
| Reporting Hierarchy | epm | DOC | Management reporting trees on canonical dimensions |
| Reporting Hierarchy Member | epm | DOC | Nodes in a reporting tree |
| Budget Cycle | epm | DOC | Single lock gate for a scenario × fiscal year |
| Budget Sheet | epm | DOC | One entity × layer of wide budget lines |
| Budget Line | epm | child | Wide budget row per (main_account, dimensions) |
| Spread Profile | epm | DOC | Allocation weights for top-down budget entry |
| Budget Cost Center | epm | Virtual | Read-only budget permission-target proxy |
| Main Account Category | epm | Virtual | Read-only budget permission-target proxy |
| Allocation Rule | allocation | DOC | Cost allocation rules → ClickHouse (N-step engine) |
| Allocation Tier | allocation | child | Tiered allocation rate bands |
| Allocation Driver | allocation | DOC | Driver values → ClickHouse |
| Allocation Run | allocation | DOC | Run metadata for traceability / reversibility |
| Consolidation Group | consolidation | DOC | Entity groupings, multi-level hierarchy |
| Ownership Period | consolidation | DOC | Temporal ownership (acquisition / disposal) |
| Historical Equity Rate | consolidation | DOC | IAS 21 historical FX rates for equity accounts |
| IC Balance | consolidation | DOC | Intercompany sales/inventory balances (entity pairs) |
| IC Elimination Rule | consolidation | DOC | Intercompany elimination rules |
| Consolidation Adjustment | consolidation | DOC | Topside journals with status workflow |
| Period Close | consolidation | DOC | Runs the dbt close-assertion suite, records each result |
| Assertion Result | consolidation | child | One close-assertion outcome |

_Counts: Pipeline 10 · EPM Model 10 · Budget 7 · Allocation 4 · Consolidation 8 = 42 (PRD-08: retired Budget Input; PRD-09 renamed Fact Table → Dataset; PRD-04/05/06/07 renamed Build Domain/Model/Close Run/Build Approval; PRD-01-03 renamed Pipeline hierarchy). Generated from konsol @ 6596534._
