# Features

Konsolidat delivers full-cycle Enterprise Performance Management through a modular, open-source stack.

## Excel-Native Reporting

Five VBA worksheet functions query financial data directly from ClickHouse via the Frappe API. No SQL, no code — just formulas.

```
=EPM("USMF", 2024, "Q1", "401100")                    → Actuals — net amount
=EPM_BUDGET("USMF", 2025, "FY", "6100")               → Budget — full year
=EPM_VARIANCE("USMF", 2025, 5, "6100")                → Variance — actual vs budget
=EPM_DEBIT("USMF", 2024, 5, "1300")                   → Period debits
=EPM_CREDIT("USMF", 2024, 5, "1300")                  → Period credits
```

- **Period aggregation** — `Q1`–`Q4`, `H1`/`H2`, `FY` roll up across months
- **Batch refresh** — `Ctrl+Shift+R` sends all formulas in a single HTTP request
- **Session auth** — Frappe login, credentials stored per-workbook
- **Dimension filters** — Optional cost center, department, business unit parameters

See the [Excel VBA Guide](user-guide/excel-vba-guide.md) for full formula reference.

## Multi-Entity Consolidation

Full IFRS/GAAP consolidation pipeline, entirely in dbt SQL:

| Step | What happens |
|------|-------------|
| **Currency translation** | Balance sheet at closing rate, P&L at average rate |
| **CTA calculation** | Automatic Currency Translation Adjustment posting |
| **NCI split** | Group vs non-controlling interest based on ownership % |
| **IC elimination** | Rule-based intercompany receivable/payable and revenue/COGS netting |
| **Top-side adjustments** | Manual consolidation journal entries via seed CSV |
| **Consolidated TB** | 4-layer union: entity + IC eliminations + CTA + topside |

See the [Consolidation Guide](user-guide/consolidation-guide.md) for details.

## Driver-Based Cost Allocations

Multi-step cascading allocation engine with three built-in allocation types:

1. **Step 1** — IT costs allocated by headcount
2. **Step 2** — Facility costs allocated by square meters (includes Step 1 cascade)
3. **Step 3** — Management fees allocated by revenue (includes Step 1+2 cascade)

Allocation rules, drivers, and cost center mappings are all defined in CSV seeds — no code changes needed.

See the [Allocation Guide](user-guide/allocation-guide.md) for configuration.

## Budgeting & Variance Analysis

- **Annual input** — Budget line items defined in CSV, one row per entity/account/year
- **Spread profiles** — `EVEN` (equal monthly), `SEASONAL_RETAIL` (weighted), or custom profiles
- **12-period spreading** — Automatic monthly breakdown from annual totals
- **5 variance measures** — actual, budget, variance_abs, variance_pct, variance_favorable
- **Favorable logic** — Revenue: favorable when actual > budget. Expense: favorable when actual < budget.

See the [Budgeting Guide](user-guide/budgeting-guide.md) and [Variance Analysis Guide](user-guide/variance-analysis-guide.md).

## Medallion Data Architecture

Four-layer data pipeline from source to reporting:

| Layer | Schema | Models | Purpose |
|-------|--------|--------|---------|
| **Raw** | `epm_bronze` (Airbyte) | — | OData entities as-is from D365 |
| **Staging** | `epm_staging` | Views | Field renames, joins, JSON parsing |
| **Bronze** | `epm_bronze` | 14 tables | Type-cast, snake_case, dimension mapping |
| **Silver** | `epm_silver` | 8 tables | Deduplicated, standardized trial balance |
| **Gold** | `epm_gold` | 22 tables | Business logic: consolidation, allocations, variance |

See the [Data Dictionary](data-dictionary/data-dictionary-overview.md) for model-level documentation.

## REST API

Three API endpoints exposed through Frappe/Konsol:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `epm_value` | GET | Single financial value query |
| `epm_batch` | POST | Batch query (used by Excel `Ctrl+Shift+R`) |
| `health` | GET | ClickHouse connection + model freshness check |

Session-based authentication via Frappe login. See the [API Reference](api-reference/api-overview.md).

## Excel Task Pane

Office.js add-in for pipeline orchestration directly from Excel:

- **Login** with Frappe credentials
- **View** latest pipeline run status
- **Trigger** Airbyte sync + dbt build from a sidebar panel

See the [Excel Task Pane Guide](user-guide/excel-taskpane-guide.md).

## Configurable Dimensions

dbt project variables define dimensions that auto-propagate through all Gold models:

```yaml
vars:
  dimensions:
    - name: dim_cost_center
      source_column: CostCenter
      allocation_role: cost_center
    - name: dim_department
      source_column: Department
    - name: dim_business_unit
      source_column: BusinessUnit
```

Add a new dimension by adding an entry — macros handle the rest. See [Adding Dimensions](developer-guide/adding-dimensions.md).

## Component Stack

| Component | Purpose | Default Port |
|-----------|---------|-------------|
| **ClickHouse** | Columnar analytical warehouse | 8123 (HTTP), 9000 (native) |
| **Airbyte** | D365 OData extraction (via abctl) | 8000 |
| **dbt Core** | SQL transformations (44 models, 26 tests) | CLI |
| **Frappe (Konsol)** | API layer, auth, pipeline control, settings | 8069 |
| **Excel VBA** | `=EPM()` formulas for financial reporting | — |
| **Excel Task Pane** | Pipeline orchestration (Office.js) | — |
