# Currency Translation Adjustment (CTA)

## Problem
`gold_fx_revaluation` has `cta_amount = 0` (placeholder). CTA is required under IFRS (IAS 21) and US GAAP (ASC 830) to keep the balance sheet balanced after translation.

## Depends On
FX Translation (separate closing and average rates must exist in consolidated TB)

## What is CTA?
When you translate a foreign subsidiary:
- BS at closing rate → net assets change period to period due to FX movement
- P&L at average rate → income doesn't translate at the same rate as BS
- CTA = the plug that makes `Assets - Liabilities = Equity + Income + CTA`

## Formula
For each entity/period:
```
CTA = (BS_net_at_closing - BS_net_at_prior_closing) - PnL_net_at_average
```
Simplified per-period:
```
CTA = sum(BS items × closing_rate) - sum(BS items × prior_closing_rate)
      - sum(PnL items × average_rate) + sum(PnL items × closing_rate)
```
Or equivalently:
```
CTA = sum(PnL items × (closing_rate - average_rate))
      + sum(BS opening × (closing_rate - prior_closing_rate))
```

## Requirements

### R1: Prior period closing rate
- Model must look up the prior period's closing rate for each currency pair
- Period 1 uses historical/opening rate (or closing from prior year period 12)

### R2: CTA line generation
- One CTA row per: consolidation_group, data_area_id, fiscal_year, fiscal_period
- `adjustment_type = 'CTA'`
- `cta_amount` = calculated per formula above
- `main_account = 'CTA'` (reserved account code for equity adjustment)

### R3: CTA flows into consolidated output
- CTA entries must be addable to consolidated TB so that group BS balances

## Acceptance Tests

| Test | Assertion |
|------|-----------|
| `assert_cta_not_zero_when_rates_differ` | When closing_rate ≠ average_rate, CTA ≠ 0 for that entity/period |
| `assert_consolidated_bs_balances_with_cta` | sum(BS group_amount) + sum(CTA) = sum(Equity group_amount + PnL group_amount) (or net = 0 within tolerance) |
| `assert_cta_zero_for_same_currency` | When entity currency = reporting currency, CTA = 0 |

## Out of Scope
- Goodwill CTA (no acquisition accounting)
- Recycling CTA to P&L on disposal
