# Configuration Data (formerly Seeds)

The dbt project no longer has seeds: `dbt_project/seeds/` was deleted in konsolidat #144, #145 and #147, and there is no `dbt seed` step. There is no demo data either.

Reference and configuration data lives in **konsol doctypes**. Saving a record (publishing it, for governed mappings such as Cash Flow Category, Dimension Mapping and Intercompany Account; approving it, for documents that need approval) writes it through to a ClickHouse table, and dbt reads that table as a source. Most tables are in `epm_staging`; a few older ones are in `epm_gold`. konsol owns these tables and rewrites them on every write-through, so edit the doctype, never the table.

## Where each former seed went

| Former seed | konsol doctype | Table dbt reads |
|-------------|----------------|-----------------|
| `consolidation_groups.csv` | **Consolidation Group** (a tree: group nodes, entities, reporting currency) and **Ownership Period** (ownership % and method, with dates) | `epm_gold.consolidation_groups`, `epm_staging.consolidation_hierarchy`, `epm_staging.consolidation_ancestry`, `epm_staging.ownership_periods` |
| `consolidation_adjustments.csv` | **Consolidation Adjustment** (EPM Analyst drafts, EPM Admin approves; only approved lines reach the warehouse) | `epm_staging.consolidation_adjustments` |
| `ic_elimination_rules.csv` | **Intercompany Account** (account pairs; see the [Intercompany Guide](../user-guide/intercompany-guide.md)). **IC Elimination Rule** remains only for unrealised profit on intercompany inventory, with **IC Balance** documents | `epm_staging.intercompany_accounts`; `epm_staging.ic_elimination_rules`, `epm_staging.ic_balances` |
| `allocation_rules.csv` | **Allocation Rule** (with its **Allocation Tier** rows) | `epm_staging.allocation_rules`, `epm_staging.allocation_tiers` |
| `allocation_drivers_headcount.csv`, `allocation_drivers_sqm.csv`, `allocation_drivers_revenue.csv` | **Allocation Driver** (one doctype; `driver_type` says which driver) | `epm_staging.allocation_drivers` |
| `budget_annual_input.csv` | **Budget Annual Input** (app budgets are entered through Budget Cycle, Budget Sheet and Budget Line; see the [Budget Layers Guide](../user-guide/budget-layers.md)) | `epm_gold.budget_annual_input` (Budget Sheet: `epm_gold.budget_monthly_input`) |
| `spread_profiles.csv` | **Spread Profile** | `epm_gold.spread_profiles` |
| `scenario_definitions.csv` | **Scenario** | `epm_gold.scenario_definitions` |
| `entity_fiscal_calendars.csv` | **Entity Fiscal Calendar** | `epm_gold.entity_fiscal_calendars` |
| `currencies.csv` | **ISO Currency** | `epm_gold.currencies` |
| `cash_flow_categories.csv` | **Cash Flow Category** (only Published mappings are applied) | `epm_staging.cash_flow_categories` |
| `dimension_mappings.csv` | **Dimension Mapping** | `epm_staging.dimension_mappings` |
| `reporting_hierarchies.csv` | **Reporting Hierarchy** (see the [Reporting Hierarchies Guide](../user-guide/reporting-hierarchies-guide.md)) | `epm_staging.reporting_hierarchies` |

Exchange rates were never a seed. The group's translation rates are **Group Exchange Rates** in konsol, published to `epm_staging.group_exchange_rates`; see the [Exchange Rates Guide](../user-guide/exchange-rates-guide.md). Historical rates for equity are **Historical Equity Rate** documents (`epm_staging.historical_equity_rates`).

## Why the seeds were removed

A seed materialises into a ClickHouse table, and konsol wrote the same tables from its doctypes. Every `dbt seed` and every `bench migrate` overwrote the other's data: a single `dbt seed` could revert a published ownership change. Keeping one writer, konsol, removed that conflict and put every change behind konsol's permissions, audit trail and approval workflows.
