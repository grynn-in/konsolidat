# Data Dictionary Overview

Open EPM uses a **medallion architecture** with 44 dbt models organized in four layers, plus 11 seed tables for reference data.

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
    subgraph "D365 F&O (OData)"
        OD[15 OData Entities]
    end

    subgraph "Bronze Layer (14 models)"
        B_GL[bronze_general_journal_account_entries]
        B_JE[bronze_general_journal_entries]
        B_MA[bronze_main_accounts]
        B_MC[bronze_main_account_categories]
        B_LE[bronze_legal_entities]
        B_FC[bronze_fiscal_calendars]
        B_FY[bronze_fiscal_calendar_years]
        B_FD[bronze_financial_dimensions]
        B_FV[bronze_financial_dimension_values]
        B_ER[bronze_exchange_rate_currency_pairs]
        B_ET[bronze_exchange_rate_types]
        B_BR[bronze_budget_register_entries]
        B_BT[bronze_budget_transaction_lines]
        B_CG[bronze_consolidation_account_groups]
        B_TB[bronze_trial_balance_snapshot]
    end

    subgraph "Silver Layer (8 models)"
        S_GL[silver_gl_entries]
        S_MA[silver_main_accounts]
        S_LE[silver_legal_entities]
        S_FP[silver_fiscal_periods]
        S_FD[silver_financial_dimensions]
        S_ER[silver_exchange_rates]
        S_BE[silver_budget_entries]
        S_TB[silver_trial_balance]
    end

    subgraph "Gold Layer (22 models)"
        G_TB[gold_trial_balance]
        G_PNL[gold_pnl_by_period]
        G_BS[gold_balance_sheet]
        G_ALLOC[gold_allocation_results]
        G_CTB[gold_consolidated_trial_balance]
        G_IC[gold_ic_eliminations]
        G_FX[gold_fx_revaluation]
        G_FCTB[gold_fully_consolidated_tb]
        G_VAR[gold_variance_analysis]
        G_BUD[gold_spread_budget]
        G_YTD[gold_ytd_trial_balance]
    end

    OD --> B_GL & B_JE & B_MA & B_LE & B_FC & B_ER & B_BR & B_BT

    B_GL & B_JE --> S_GL
    B_MA & B_MC --> S_MA
    B_LE --> S_LE
    B_FC & B_FY --> S_FP
    B_FD & B_FV --> S_FD
    B_ER & B_ET --> S_ER
    B_BR & B_BT --> S_BE
    B_TB --> S_TB

    S_GL & S_MA & S_FP --> G_TB
    G_TB --> G_PNL & G_BS & G_YTD & G_ALLOC
    G_TB & S_ER --> G_CTB
    G_CTB --> G_IC & G_FX
    G_CTB & G_IC & G_FX --> G_FCTB
    G_TB & G_BUD --> G_VAR
    S_BE --> G_BUD
```

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
