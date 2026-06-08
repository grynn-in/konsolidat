# Budget Layers — Collaborative Budgeting with Full Audit Trail

## Why Layers?

Most budgeting tools give you one number per cell. If Finance cuts your budget, you lose the original. If the board adjusts it, you lose the Finance version. Nobody knows who changed what, when, or why.

Open EPM stores **every stakeholder's contribution separately** and sums them at query time. The original submission, every adjustment, every override — all preserved, all auditable, all reversible.

## The Four Layers

| Layer | Edited By | Purpose |
|:------|:----------|:--------|
| **base** | Budget Submitter | Department's original submission |
| **challenge** | Budget Controller | Finance team adjustments (typically cuts) |
| **management** | Budget Manager | Executive overrides (strategic additions) |
| **board** | Budget Approver | Board-level final adjustments |

All roles can **view** every layer. Each can only **edit** their own.

**Effective budget = base + challenge + management + board** (always, for every period).

---

## Worked Example

**Scenario**: BUDGET_2025, Entity: USMF, Account: 6100 (Sales Expense), Cost Center: SALES

### 1. Department Submits (base)

The Sales team enters their monthly plan in Frappe Desk — $100k/month:

| | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | P9 | P10 | P11 | P12 | **Annual** |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **base** | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | **1,200,000** |

Workflow state: **Draft** → submitter clicks *Submit for Review* → **Submitted**

### 2. Finance Challenges (challenge)

The Budget Controller reviews and applies a 5% cut across all months:

| | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | P9 | P10 | P11 | P12 | **Annual** |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **base** | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 1,200,000 |
| **challenge** | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | **-60,000** |
| **Subtotal** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **1,140,000** |

### 3. Management Override (management)

The CFO approves additional funding for a Q3 product launch:

| | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | P9 | P10 | P11 | P12 | **Annual** |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **base** | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 1,200,000 |
| **challenge** | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -60,000 |
| **management** | — | — | — | — | — | — | 15,000 | 15,000 | 10,000 | — | — | — | **40,000** |
| **Subtotal** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **110,000** | **110,000** | **105,000** | **95,000** | **95,000** | **95,000** | **1,180,000** |

### 4. Board Adjusts and Approves (board)

The board adds Q4 contingency for year-end push:

| | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | P9 | P10 | P11 | P12 | **Annual** |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **base** | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 100,000 | 1,200,000 |
| **challenge** | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -5,000 | -60,000 |
| **management** | — | — | — | — | — | — | 15,000 | 15,000 | 10,000 | — | — | — | 40,000 |
| **board** | — | — | — | — | — | — | — | — | — | 5,000 | 5,000 | 5,000 | **15,000** |
| | | | | | | | | | | | | | |
| **EFFECTIVE** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **95,000** | **110,000** | **110,000** | **105,000** | **100,000** | **100,000** | **100,000** | **1,195,000** |

The approver clicks **Approve** → ClickHouse sync fires → `dbt build` runs.

---

## What ClickHouse Stores

Every row from every layer is persisted. Nothing is aggregated at write time:

**`gold.budget_monthly_input`**

| scenario_id | data_area_id | fiscal_year | main_account | fiscal_period | amount | layer |
|:---|:---|---:|:---|---:|---:|:---|
| BUDGET_2025 | USMF | 2025 | 6100 | 1 | 100,000 | base |
| BUDGET_2025 | USMF | 2025 | 6100 | 1 | -5,000 | challenge |
| BUDGET_2025 | USMF | 2025 | 6100 | 7 | 100,000 | base |
| BUDGET_2025 | USMF | 2025 | 6100 | 7 | -5,000 | challenge |
| BUDGET_2025 | USMF | 2025 | 6100 | 7 | 15,000 | management |
| BUDGET_2025 | USMF | 2025 | 6100 | 10 | 100,000 | base |
| BUDGET_2025 | USMF | 2025 | 6100 | 10 | -5,000 | challenge |
| BUDGET_2025 | USMF | 2025 | 6100 | 10 | 5,000 | board |
| ... | ... | ... | ... | ... | ... | ... |

This gives you full audit trail: who contributed what, when, and at which layer.

---

## What dbt Produces

The dbt model aggregates layers into a single effective budget per period:

**`gold_spread_budget`** (what EPM() queries)

| scenario_id | data_area_id | fiscal_year | fiscal_period | main_account | period_amount |
|:---|:---|---:|---:|:---|---:|
| BUDGET_2025 | USMF | 2025 | 1 | 6100 | 95,000 |
| BUDGET_2025 | USMF | 2025 | 2 | 6100 | 95,000 |
| BUDGET_2025 | USMF | 2025 | 3 | 6100 | 95,000 |
| BUDGET_2025 | USMF | 2025 | 4 | 6100 | 95,000 |
| BUDGET_2025 | USMF | 2025 | 5 | 6100 | 95,000 |
| BUDGET_2025 | USMF | 2025 | 6 | 6100 | 95,000 |
| BUDGET_2025 | USMF | 2025 | 7 | 6100 | 110,000 |
| BUDGET_2025 | USMF | 2025 | 8 | 6100 | 110,000 |
| BUDGET_2025 | USMF | 2025 | 9 | 6100 | 105,000 |
| BUDGET_2025 | USMF | 2025 | 10 | 6100 | 100,000 |
| BUDGET_2025 | USMF | 2025 | 11 | 6100 | 100,000 |
| BUDGET_2025 | USMF | 2025 | 12 | 6100 | 100,000 |

---

## What Excel Sees via EPM()

### Single Period

| Cell | Formula | Result |
|:-----|:--------|-------:|
| B3 | `=EPM("USMF", 2025, 1, "6100", "period_amount", "budget")` | 95,000 |
| B9 | `=EPM("USMF", 2025, 7, "6100", "period_amount", "budget")` | 110,000 |
| B12 | `=EPM("USMF", 2025, 10, "6100", "period_amount", "budget")` | 100,000 |

### Quarterly & Annual Totals

| Cell | Formula | Result | Calculation |
|:-----|:--------|-------:|:------------|
| C3 | `=EPM("USMF", 2025, "Q1", "6100", "period_amount", "budget")` | 285,000 | 95k + 95k + 95k |
| C5 | `=EPM("USMF", 2025, "Q3", "6100", "period_amount", "budget")` | 325,000 | 110k + 110k + 105k |
| C7 | `=EPM("USMF", 2025, "H2", "6100", "period_amount", "budget")` | 625,000 | Q3 + Q4 |
| D2 | `=EPM("USMF", 2025, "FY", "6100", "period_amount", "budget")` | 1,195,000 | all 12 periods |

### Variance Analysis

Assume actuals for P5 came in at $92,000 against the $95,000 budget:

| Cell | Formula | Result | Meaning |
|:-----|:--------|-------:|:--------|
| E5 | `=EPM("USMF", 2025, 5, "6100", "actual_amount", "variance")` | 92,000 | What was actually spent |
| F5 | `=EPM("USMF", 2025, 5, "6100", "budget_amount", "variance")` | 95,000 | The approved budget |
| G5 | `=EPM("USMF", 2025, 5, "6100", "variance_abs", "variance")` | -3,000 | Under budget by $3k |
| H5 | `=EPM("USMF", 2025, 5, "6100", "variance_pct", "variance")` | -3.16 | 3.16% under budget |
| I5 | `=EPM("USMF", 2025, 5, "6100", "variance_favorable", "variance")` | 1 | Favorable (expense below budget) |

---

## Workflow States

| State | Who Can Act | What Happens |
|:------|:------------|:-------------|
| **Draft** | Budget Submitter edits base layer | Not synced to ClickHouse |
| **Submitted** | Budget Controller reviews, edits challenge layer | Read-only for submitter |
| **Approved** | Budget Approver approves | Syncs all layers to ClickHouse |
| **Rejected** | Returns to Budget Submitter | Back to Draft for correction |

```
Draft ──[Submit for Review]──→ Submitted ──[Approve]──→ Approved ──→ CH Sync ──→ dbt build
                                    │
                                    └──[Reject]──→ Rejected ──[Resubmit]──→ Submitted
```

---

## End-to-End Data Flow

```
FRAPPE DESK                      CLICKHOUSE                         EXCEL
───────────                      ──────────                         ─────

Budget Input doc
 ┌─ base:       +100k/mo  ─┐
 ├─ challenge:  -5k/mo     ├──→  gold.budget_monthly_input
 ├─ management: +40k Q3    │     (48 rows: 12mo x 4 layers)
 └─ board:      +15k Q4    ┘
                                        │
     [Approve]                     dbt build
                                        │
                                        ▼
                                 gold_spread_budget             =EPM("USMF",2025,5,
                                 (12 rows: SUM per period)        "6100","period_amount",
                                        │                         "budget")
                                        ▼                              │
                                 gold_variance_analysis                ▼
                                 (actual vs effective budget)       95,000
```

---

## Forecast Uses the Same Structure

The Budget Input doctype handles both budget and forecast. The `scenario_id` field links to a Scenario Definition where `scenario_type` = `budget` or `forecast`. Everything else — layers, workflow, roles, Excel retrieval — works identically:

| Formula | What It Returns |
|:--------|:----------------|
| `=EPM("USMF", 2025, 5, "6100", "period_amount", "budget")` | Approved budget (all layers summed) |
| `=EPM("USMF", 2025, 5, "6100", "period_amount", "forecast")` | Latest forecast (all layers summed) |
| `=EPM("USMF", 2025, 5, "6100", "actual_amount", "variance")` | Actual from GL |
| `=EPM("USMF", 2025, 5, "6100", "variance_abs", "variance")` | Actual minus budget |

---

## Key Design Points

| Principle | Detail |
|:----------|:-------|
| **Layers are additive** | No separate "final" row — the sum across layers IS the final budget |
| **Only Approved budgets sync** | Draft and Submitted stay in Frappe only — no stale data in ClickHouse |
| **dbt always aggregates** | `gold_spread_budget` returns one `period_amount` per period (sum of all layers) |
| **EPM() returns the aggregate** | Excel users see the effective budget, not individual layers |
| **Full audit trail** | Raw layer data persists in `gold.budget_monthly_input` — query by layer for reporting |
| **Role-based editing** | Each layer locked to its role; System Manager can edit all |
| **Budget = Forecast** | Same doctype, same layers, same workflow — distinguished by scenario_id |
