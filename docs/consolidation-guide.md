# Consolidation Guide

## Overview

Konsolidat consolidates multiple D365 legal entities into a group view with:
- Currency translation (local → group reporting currency)
- Ownership adjustment (minority interest)
- Intercompany elimination

The current, fuller guide is the [Consolidation Guide](user-guide/consolidation-guide.md).

## Setting Up Consolidation Groups

Build the group structure in konsol's **Consolidation Group** tree: group nodes (each with its Reporting Currency) and the entities under them. Set each entity's ownership percentage and consolidation method, with the dates they apply, on an **Ownership Period**. There are no dbt seeds.

## Currency Translation

Translation uses the group's governed **Group Exchange Rates** from konsol (one approved Closing and one Average rate per period), never the ERP's rate tables:

| Account Type | Rate Used |
|-------------|-----------|
| Balance Sheet | Closing rate |
| P&L | Average rate |
| Equity | Historical rate where a Historical Equity Rate exists, else closing rate |

Group amount = Local amount × Exchange rate × Ownership %

See the [Exchange Rates Guide](user-guide/exchange-rates-guide.md).

## Intercompany Elimination

Flag intercompany accounts and their counterparts as **Intercompany Account** pairs in konsol; each trial balance row on those accounts names its partner entity. Consolidation pairs each entity's balance with its partner's, eliminates the matched amount, and books any difference to the group's intercompany difference account. See the [Intercompany Guide](user-guide/intercompany-guide.md).

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
