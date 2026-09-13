# FX Translation (Closing vs Average Rate)

> **Superseded for the rate source (konsolidat#93 / konsol#103, 13 Sep 2026).**
> Translation no longer reads `silver_exchange_rates` or falls back to
> `Default` or 1.0. `gold_consolidated_trial_balance` takes one approved
> Closing and one Average rate per fiscal period, from each currency into the
> group's reporting currency, from `epm_staging.group_exchange_rates` (konsol's
> Group Exchange Rate). A missing rate stops the build. The ERP feed only
> pre-fills drafts in konsol. The account-type rule below (closing for the
> balance sheet, average for the P&L, historical for equity tranches) is
> unchanged.
>
> **The contract (decided 13 Sep 2026):** `epm_staging.group_exchange_rates.rate`
> is the true rate (units of `to_currency` per 1 `from_currency`), published by
> konsol, the single source of FX rates. The warehouse never scales or inverts
> it: finance enters any "quoted per" factor in konsol, and konsol divides it
> out before publishing. `silver_exchange_rates` holds the ERP quotes, which
> feed only konsol's pre-fill. A rate more than 10x from the currencies'
> reference magnitudes (`usd_log10`) stops the build before anything is
> replaced.
>
> **A missing rate stops the whole run.** Every key a run translates must have an
> approved Closing and Average rate, so a newly submitted trial balance in a
> foreign currency blocks full builds until its period's Closing and Average
> rates into the group currency are approved in konsol. The build's error
> lists every such key, konsol's home shows the missing rates, and
> `scripts/sql/fx_governed_rate_gaps.sql` lists them from ClickHouse directly
> (`deploy.sh` runs it before step 5).

## Problem
`gold_consolidated_trial_balance` uses a single closing rate for all accounts. IFRS/US GAAP require:
- **Balance sheet accounts** → closing (spot) rate at period end
- **P&L accounts** → average rate for the period
- **Equity accounts** → historical rate at transaction date

## Scope
Enhance `gold_consolidated_trial_balance.sql` and `silver_exchange_rates` to support rate type selection.

## Requirements

### R1: Exchange rate type lookup
- Silver exchange rates must expose `exchange_rate_type` (D365 stores: Default, Closing, Average, Historical)
- If a specific rate type is not available, fall back to Default

### R2: Rate selection by account type
- `is_balance_sheet = 1` → use rate type `Closing` (fall back to latest Default)
- `is_pnl = 1` → use rate type `Average` (fall back to latest Default)
- Neither (equity-like) → use rate type `Historical` (fall back to latest Default)

### R3: Translated columns
- `closing_rate` — the closing rate used (always populated for audit)
- `average_rate` — the average rate used (always populated for audit)
- `translation_rate` — the rate actually applied (closing or average depending on account type)
- `translated_amount` = `local_amount × translation_rate`
- `group_amount` = `translated_amount × ownership_pct`

### R4: Backward compatibility
- Output schema adds columns; existing columns keep same semantics
- Cube YAML for `consolidated_trial_balance` must expose new rate columns

## Acceptance Tests (dbt singular tests)

| Test | Assertion |
|------|-----------|
| `assert_bs_uses_closing_rate` | All rows where `is_balance_sheet=1` have `translation_rate = closing_rate` |
| `assert_pnl_uses_average_rate` | All rows where `is_pnl=1` have `translation_rate = average_rate` |
| `assert_translated_amount_formula` | `translated_amount = local_amount × translation_rate` within 0.01 |
| `assert_group_amount_formula` | `group_amount = translated_amount × ownership_pct` within 0.01 |

## Out of Scope
- Remeasurement vs translation (single functional currency assumed)

> **Update (PRD-10):** Temporal (historical) rate for equity line items was originally out of scope here but has since been implemented. Equity accounts now translate at a frozen historical rate held in the **Historical Equity Rate** doctype (`epm_staging.historical_equity_rates`), applied in `gold_consolidated_trial_balance` ahead of the closing rate. See the [Consolidation Guide → Historical Equity Rates (IAS 21)](../../user-guide/consolidation-guide.md#historical-equity-rates-ias-21) for the worked example.
