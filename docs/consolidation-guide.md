# Consolidation Guide

## Overview

Open EPM consolidates multiple D365 legal entities into a group view with:
- Currency translation (local → group reporting currency)
- Ownership adjustment (minority interest)
- Intercompany elimination

## Setting Up Consolidation Groups

Edit `dbt_project/seeds/consolidation_groups.csv`:

```csv
consolidation_group,data_area_id,entity_name,ownership_pct,reporting_currency,consolidation_method
GROUP_CORP,USMF,Contoso US,100.00,USD,full
GROUP_CORP,DEMF,Contoso DE,100.00,USD,full
GROUP_CORP,GBMF,Contoso UK,80.00,USD,full
```

| Field | Description |
|-------|-------------|
| `consolidation_group` | Group identifier |
| `data_area_id` | D365 legal entity code |
| `ownership_pct` | Ownership percentage (0-100) |
| `reporting_currency` | Group reporting currency |
| `consolidation_method` | `full` (100% consolidation) or `equity` |

## Currency Translation

Translation uses exchange rates from D365 (`silver_exchange_rates`):

| Account Type | Rate Used |
|-------------|-----------|
| Balance Sheet | Closing rate (latest available for period) |
| P&L | Average rate (simplified: uses period-start rate) |
| Equity | Historical rate (simplified: uses closing rate) |

Group amount = Local amount × Exchange rate × Ownership %

## Intercompany Elimination

Edit `dbt_project/seeds/ic_elimination_rules.csv`:

```csv
rule_id,rule_name,debit_account,credit_account,debit_entity_pattern,credit_entity_pattern
IC_001,IC Receivable/Payable,1300,2100,*,*
IC_002,IC Revenue/COGS,4000,5000,*,*
```

The engine:
1. Finds balances in debit_account and credit_account across different entities
2. Creates offsetting entries (debit elimination + credit elimination = 0)
3. Uses the lesser of the two balances (conservative approach)

## CTA (Currency Translation Adjustment)

The `gold_fx_revaluation` model calculates CTA entries to keep the balance sheet balanced after currency translation. CTA is booked to equity.

## Viewing Consolidated Reports

In Excel, connect to `v_consolidated_report` via Cube SQL API. Available dimensions:
- Consolidation Group
- Legal Entity (for drill-down)
- Fiscal Year / Period
- Account

## Validation

The test `assert_ic_elimination_nets_zero.sql` verifies that all IC eliminations net to zero (debit + credit eliminations = 0).

Consolidated group total = Sum of entity totals × ownership + IC eliminations + CTA.
