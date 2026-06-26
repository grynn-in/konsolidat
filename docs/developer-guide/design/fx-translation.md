# FX Translation (Closing vs Average Rate)

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
