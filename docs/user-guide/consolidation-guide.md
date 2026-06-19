# Consolidation Guide

Konsolidat consolidates financial data from multiple legal entities into a single group report. The process includes currency translation, intercompany elimination, CTA calculation, and top-side adjustments.

## Overview

```mermaid
graph TD
    TB[gold_trial_balance<br/>Entity-level amounts] --> CTB[gold_consolidated_trial_balance<br/>FX translation + ownership split]
    CTB --> IC[gold_ic_eliminations<br/>Intercompany entries]
    CTB --> FX[gold_fx_revaluation<br/>CTA entries]
    ADJ[consolidation_adjustments seed<br/>Top-side journals] --> CADJ[gold_consolidation_adjustments]
    CTB --> FCTB[gold_fully_consolidated_tb<br/>4-layer union]
    IC --> FCTB
    FX --> FCTB
    CADJ --> FCTB
    FCTB --> CYTD[gold_consolidated_ytd<br/>YTD running totals]
```

## Consolidation Groups

Defined in the `consolidation_groups` seed CSV:

```csv
consolidation_group,data_area_id,entity_name,ownership_pct,reporting_currency,consolidation_method
GROUP_CORP,USMF,Contoso US,100,USD,full
GROUP_CORP,DEMF,Contoso DE,100,USD,full
GROUP_CORP,GBMF,Contoso UK,80,USD,full
GROUP_CORP,JPMF,Contoso JP,51,USD,full
```

| Field | Description |
|-------|-------------|
| `consolidation_group` | Group identifier (e.g., `GROUP_CORP`) |
| `data_area_id` | Legal entity code from D365 |
| `ownership_pct` | Parent's ownership (0–100) |
| `reporting_currency` | Group reporting currency |
| `consolidation_method` | Currently: `full` |

## Currency Translation

### Rate Selection Rules

| Account Type | Rate Used | Rationale |
|-------------|-----------|-----------|
| Balance Sheet (Asset, Liability) | **Closing rate** | BS at period-end value |
| P&L (Revenue, Expense) | **Average rate** | P&L at period average |
| Equity | **Closing rate** | Simplified; historical rate for full IAS 21 |

The rate is looked up from `silver_exchange_rates` using the `convert_currency()` macro with a fallback chain:
1. Exact match on `from_currency`, `to_currency`, `valid_from ≤ date ≤ valid_to`
2. Latest available rate before the period
3. Default to `1.0` (same-currency assumption)

### Translation Formulas

```
translated_amount = local_amount × translation_rate
group_amount      = translated_amount × ownership_pct
nci_amount        = translated_amount × (1 − ownership_pct)
```

**Example**: GBMF (UK entity, 80% owned) reports GBP 100,000 revenue, closing rate 1.27 USD/GBP:

```
translated_amount = 100,000 × 1.27 = 127,000 USD
group_amount      = 127,000 × 0.80 = 101,600 USD
nci_amount        = 127,000 × 0.20 =  25,400 USD
```

### Tests

| Test | Assertion |
|------|-----------|
| `assert_translated_amount_formula` | `\|translated − (local × rate)\| ≤ 0.01` |
| `assert_group_amount_formula` | `\|group − (translated × ownership)\| ≤ 0.01` |
| `assert_nci_plus_group_equals_translated` | `\|translated − (group + nci)\| ≤ 0.01` |
| `assert_nci_zero_for_full_ownership` | NCI = 0 when ownership = 100% |
| `assert_bs_uses_closing_rate` | BS accounts use closing rate |
| `assert_pnl_uses_average_rate` | P&L accounts use average rate |

## Intercompany Elimination

### IC Elimination Rules

Defined in the `ic_elimination_rules` seed:

```csv
rule_id,rule_name,debit_account,credit_account,debit_entity_pattern,credit_entity_pattern,description
IC_001,IC Receivable/Payable,1300,2100,*,*,Eliminate IC receivables against payables
IC_002,IC Revenue/COGS,4000,5000,*,*,Eliminate IC revenue against COGS
IC_003,IC Dividend,8100,3200,*,*,Eliminate IC dividends
```

The elimination engine:
1. For each rule, finds matching debit/credit account balances across entities in the same group
2. Calculates the elimination amount as the lesser of the two IC balances
3. Posts offsetting entries to zero out the intercompany position

### Test

`assert_ic_elimination_nets_zero` — for each group/year/period, `sum(debit_elimination + credit_elimination)` must be ≤ 0.01.

## Currency Translation Adjustment (CTA)

CTA arises because P&L is translated at the average rate but the balance sheet at the closing rate. The difference is posted as an equity adjustment.

```
cta_amount = sum(local_amount × (closing_rate − average_rate) × ownership_pct)
```

### Tests

| Test | Assertion |
|------|-----------|
| `assert_cta_not_zero_when_rates_differ` | CTA is non-zero when closing ≠ average rate |
| `assert_cta_zero_for_same_currency` | CTA = 0 when entity currency = reporting currency |

## Top-Side Adjustments

Manual journal entries posted at the group level for adjustments that don't originate from entity GL (e.g., goodwill, purchase price allocation, fair value adjustments).

Defined in the `consolidation_adjustments` seed:

| Field | Type | Description |
|-------|------|-------------|
| `consolidation_group` | String | Group |
| `adjustment_type` | String | Type of adjustment |
| `journal_id` | String | Unique journal ID |
| `data_area_id` | String | Entity (or group-level) |
| `fiscal_year` | UInt16 | Year |
| `fiscal_period` | UInt8 | Period |
| `main_account` | String | Account |
| `debit_amount` | Decimal(18,2) | Debit |
| `credit_amount` | Decimal(18,2) | Credit |
| `description` | String | Narrative |

**Test**: `assert_topside_journal_balanced` — each journal must balance (total debits = total credits).

## Fully Consolidated Trial Balance (4-Layer Union)

```mermaid
graph LR
    E[Entity Layer<br/>group_amount from CTB] --> FCTB[gold_fully_consolidated_tb]
    IC[IC Elimination Layer] --> FCTB
    CTA[CTA Layer] --> FCTB
    TS[Topside Layer] --> FCTB
```

The `gold_fully_consolidated_tb` model unions four layers:

| `adjustment_type` | Source | Amount |
|-------------------|--------|--------|
| `entity` | `gold_consolidated_trial_balance` | `group_amount` |
| `ic_elimination` | `gold_ic_eliminations` | `elimination_amount` |
| `cta` | `gold_fx_revaluation` | `cta_amount` |
| (topside type) | `gold_consolidation_adjustments` | `net_amount` |

**Test**: `assert_fctb_entity_layer_ties` — entity layer sums tie to `gold_consolidated_trial_balance.group_amount`.

## Cash Flow Statement (Indirect Method)

The platform derives the third primary statement from balance-sheet account
movements — no separate cash-flow ledger is required.

**Entity level** — `gold_cash_flow_indirect`:

- Every non-cash BS account's `period_movement` (from `gold_bs_movement`) is
  classified into Operating / Investing / Financing via the
  `cash_flow_categories` seed and converted to a cash effect:
  `cash_flow_amount = period_movement × sign`.
- Because balances are stored as positive magnitudes, the cash direction is set
  explicitly per account in the seed's `sign` column: credit-natured accounts
  (liabilities, equity, contra-assets like accumulated depreciation) are `+1`;
  debit-natured accounts (assets, contra-equity like dividends declared) are
  `-1` — an asset increase is a cash outflow.
- Net income is **not** pulled separately from the P&L; the retained-earnings
  movement already carries period net income on the balance sheet, so it is the
  Operating "Net Income" line. Dividends declared go to Financing.

**Group level** — `gold_consolidated_cash_flow`:

- Built after FX translation from `gold_fully_consolidated_tb`, so group totals
  reflect translated (closing-rate) amounts and differ from the simple sum of
  entity local-currency cash flows.
- Each consolidation layer's amount (entity, IC elimination, CTA, topside, …) is
  folded into the underlying account and categorized identically. CTA is the
  plug that keeps the translated balance sheet in balance, so the statement
  still ties to the change in translated cash.

### Categorizing accounts

Edit `seeds/cash_flow_categories.csv` and re-run `dbt seed` to map a new GL
account. The relationships test on `gold_bs_movement.main_account` fails the
build if any balance-sheet account is left uncategorized.

### Tests

- `assert_cf_categories_equal_net_change` — entity: `Σ(O + I + F) = Σ period_movement of is_cash accounts`, per entity/period, within ±0.01.
- `assert_consolidated_cf_reconciles` — group: same identity across all layers, per group/period.
- `accepted_values` on `cf_category` ∈ {Operating, Investing, Financing}.

Both reconciliations hold only when the (consolidated) balance sheet balances
each period; a failure points at unbalanced source data, not the model.

## Reporting with EPM()

Consolidated data is available via the gold models. For entity-level reporting:

```
=EPM("USMF", 2024, "FY", "401100")
```

For consolidated reports, query the fully consolidated models directly via SQL or build summary reports that reference the consolidation gold tables.

## Next Steps

- [Allocation Guide](allocation-guide.md) — Cost allocation after consolidation
- [Budgeting Guide](budgeting-guide.md) — Budget input and spreading
- [Data Dictionary: Gold Models](../data-dictionary/gold-models.md) — Full column reference
