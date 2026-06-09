# Data Dictionary Overview

Konsolidat uses a **medallion architecture** with 44 dbt models organized in four layers, plus 11 seed tables for reference data.

## Model Counts

| Layer | Schema | Models | Materialization |
|-------|--------|--------|----------------|
| Staging | `epm_staging` | ~14 | Views |
| Bronze | `epm_bronze` | 14 | Tables |
| Silver | `epm_silver` | 8 | Tables |
| Gold | `epm_gold` | 22 | Tables |
| Seeds | `epm_gold` | 11 | Tables |

## Data Lineage

```mermaid
graph TD
    ERP["<b>ERP Source</b><br/><br/>D365 / SAP / ERPNext<br/>15 OData Entities"]

    ERP --> B1 & B2 & B3 & B4

    B1["<b>GL Entries & Journals</b><br/>bronze_general_journal_*"]
    B2["<b>Accounts & Categories</b><br/>bronze_main_accounts"]
    B3["<b>Entities, FX, Fiscal</b><br/>bronze_legal_entities, rates, calendars"]
    B4["<b>Budget & Consolidation</b><br/>bronze_budget_*, bronze_consolidation_*"]

    B1 & B2 & B3 --> S1
    B2 --> S2
    B3 --> S3
    B4 --> S4

    S1["<b>silver_gl_entries</b><br/>Cleaned GL with dimensions"]
    S2["<b>silver_main_accounts</b><br/>Account types & categories"]
    S3["<b>silver_exchange_rates</b><br/>silver_fiscal_periods"]
    S4["<b>silver_budget_entries</b><br/>Validated budget lines"]

    S1 & S2 & S3 --> G1
    G1 --> G2
    G1 --> G3
    S4 --> G3
    G1 & G3 --> G4

    G1["<b>Trial Balance / P&L / BS / YTD</b><br/>Core financial statements"]
    G2["<b>Consolidation Pipeline</b><br/>Consolidated TB → IC Elim → FX Reval → FCTB"]
    G3["<b>Allocations & Budgets</b><br/>Cost allocation + spread budget"]
    G4["<b>Variance Analysis</b><br/>Actual vs budget with favorable logic"]

    G1 & G2 & G3 & G4 --> API

    API["<b>Frappe API → Cube.js → Excel</b><br/><br/>=EPM() formulas in your spreadsheet"]
```

### Key Lineage Paths

| Path | Flow |
|------|------|
| **Reporting** | GL Entries → silver_gl_entries → gold_trial_balance → P&L, BS, YTD |
| **Consolidation** | Trial Balance + FX Rates → Consolidated TB → IC Elimination → FX Reval → Fully Consolidated TB |
| **Budgeting** | Budget Entries → silver_budget_entries → gold_spread_budget |
| **Variance** | Trial Balance + Spread Budget → gold_variance_analysis |
| **Allocations** | Trial Balance + Allocation Rules (seed) → gold_allocation_results |

## Layer Descriptions

### Bronze
Raw D365 OData data, type-cast to ClickHouse types and renamed to snake_case. No business logic. See [Bronze Models](bronze-models.md).

### Silver
Cleaned, deduplicated, and joined data. Key transformations: GL entries joined with journal headers, exchange rates normalized (D365 rate ÷ 100), account types mapped to readable labels. See [Silver Models](silver-models.md).

### Gold
Business-ready models consumed by the API and Excel reports. Includes trial balance, P&L, balance sheet, consolidation, allocation, budgeting, and variance analysis. See [Gold Models](gold-models.md).

### Seeds
CSV-managed reference data: allocation rules, consolidation groups, budget inputs, spread profiles, IC elimination rules, and scenario definitions. See [Seeds Reference](seeds-reference.md).

## ClickHouse Staging Tables

Write-back tables in `epm_staging` for budget submissions and other user inputs. See [Staging Tables](staging-tables.md).

## Dimension System

All Gold models carry three dimension columns, controlled by `var('dimensions')` in `dbt_project.yml`:

| Column | Source (D365) | In Budget | Allocation Role |
|--------|--------------|-----------|-----------------|
| `dim_cost_center` | `CostCenter` | Yes | `cost_center` |
| `dim_department` | `Department` | Yes | — |
| `dim_business_unit` | `BusinessUnit` | No | — |

Dimensions auto-propagate through models via the `dim_select()`, `dim_group_by()`, `dim_join_on()` family of macros. See [Adding Dimensions](../developer-guide/adding-dimensions.md).
