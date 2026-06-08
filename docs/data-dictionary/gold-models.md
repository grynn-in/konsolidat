# Gold Models

22 business-ready models in the `epm_gold` schema, consumed by the Frappe API and Excel reports.

## Trial Balance & GL

### gold_trial_balance

Period-level trial balance aggregated from GL entries. **Primary model for the `actuals` scenario.**

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity identifier | not_null |
| `fiscal_year` | UInt16 | Fiscal year | not_null |
| `fiscal_period` | UInt8 | Fiscal period (1–12) | not_null |
| `main_account` | String | Main account ID from chart of accounts | not_null |
| `dim_cost_center` | String | Cost center dimension | — |
| `dim_department` | String | Department dimension | — |
| `dim_business_unit` | String | Business unit dimension | — |
| `period_debit` | Decimal | `sum(debit_amount)` | — |
| `period_credit` | Decimal | `sum(credit_amount)` | — |
| `period_net_amount` | Decimal | `sum(accounting_currency_amount)` | — |
| `transaction_count` | UInt64 | `count(*)` | — |

**API mapping**: `scenario=actuals` → queries this table.

### gold_ytd_trial_balance

Year-to-date running totals over `gold_trial_balance`.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity identifier | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Main account ID | — |
| `dim_cost_center` | String | Cost center | — |
| `dim_department` | String | Department | — |
| `dim_business_unit` | String | Business unit | — |
| `ytd_debit` | Decimal | Cumulative debit through period | — |
| `ytd_credit` | Decimal | Cumulative credit through period | — |
| `ytd_net_amount` | Decimal | Cumulative net amount through period | not_null desc |

**Test**: `assert_ytd_p12_equals_annual` — YTD at period 12 must equal sum of all 12 periods.

## P&L Models

### gold_pnl_by_period

P&L view — revenue and expense accounts only.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account (revenue/expense only) | not_null |
| `account_type` | String | `Revenue` or `Expense` | — |
| `period_net_amount` | Decimal | Net amount for period | — |

**Test**: `assert_pnl_only_pnl_accounts` — only P&L account types present.

### gold_pnl_quarterly

Quarterly P&L aggregation for P&L accounts.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_quarter` | String | Quarter label (Q1–Q4) | not_null |
| `main_account` | String | Account | — |
| `quarter_net_amount` | Decimal | Sum of `period_net_amount` for the quarter | — |

### gold_pnl_half_yearly

Half-yearly P&L aggregation for P&L accounts.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_half` | String | Half label (H1, H2) | not_null |
| `main_account` | String | Account | — |
| `half_net_amount` | Decimal | Sum of `period_net_amount` for the half | — |

## Balance Sheet Models

### gold_balance_sheet

Balance sheet view — cumulative balances for BS accounts.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account (asset/liability/equity only) | not_null |
| `account_type` | String | `Asset`, `Liability`, or `Equity` | — |
| `cumulative_balance` | Decimal | Running sum of `period_net_amount` within the year | — |

**Test**: `assert_bs_only_bs_accounts` — only BS account types present.

### gold_bs_movement

Balance sheet movement schedule: opening, movement, closing.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | not_null |
| `opening_balance` | Decimal | Cumulative balance at prior period | — |
| `period_movement` | Decimal | Net amount for the period | — |
| `closing_balance` | Decimal | Cumulative balance at current period | — |

## Consolidation Models

### gold_consolidated_trial_balance

Multi-company consolidated trial balance with currency translation.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `data_area_id` | String | Legal entity | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | — |
| `local_amount` | Decimal | Amount in entity's local currency | — |
| `accounting_currency` | String | Entity's local currency code | — |
| `reporting_currency` | String | Group reporting currency | — |
| `translation_rate` | Decimal | FX rate applied | — |
| `closing_rate` | Decimal | Period-end FX rate | — |
| `average_rate` | Decimal | Period average FX rate | — |
| `translated_amount` | Decimal | `local_amount × translation_rate` | — |
| `ownership_pct` | Decimal | Parent's ownership percentage | — |
| `group_amount` | Decimal | `translated_amount × ownership_pct` | — |
| `nci_amount` | Decimal | `translated_amount × (1 − ownership_pct)` | — |

**Tests**: `assert_translated_amount_formula`, `assert_group_amount_formula`, `assert_nci_plus_group_equals_translated`, `assert_nci_zero_for_full_ownership`, `assert_bs_uses_closing_rate`, `assert_pnl_uses_average_rate`.

### gold_ic_eliminations

Intercompany elimination entries.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `rule_id` | String | IC elimination rule ID | not_null |
| `debit_elimination` | Decimal | Debit-side elimination amount | — |
| `credit_elimination` | Decimal | Credit-side elimination amount | — |
| `elimination_amount` | Decimal | Lesser of debit/credit IC balances | — |

**Test**: `assert_ic_elimination_nets_zero` — eliminations net to zero per group/year/period.

### gold_fx_revaluation

Currency translation adjustment (CTA) entries.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `cta_amount` | Decimal | `sum(local × (closing − average) × ownership)` | — |

**Tests**: `assert_cta_not_zero_when_rates_differ`, `assert_cta_zero_for_same_currency`.

### gold_consolidation_adjustments

Top-side journal adjustments for consolidation.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `journal_id` | String | Journal entry ID | not_null |
| `adjustment_type` | String | Type of adjustment | — |
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | — |
| `debit_amount` | Decimal | Debit | — |
| `credit_amount` | Decimal | Credit | — |
| `net_amount` | Decimal | `debit_amount − credit_amount` | — |

**Test**: `assert_topside_journal_balanced` — each journal must balance (debits = credits).

### gold_fully_consolidated_tb

Unified consolidated TB: entity balances + IC eliminations + CTA + topside adjustments.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `adjustment_type` | String | Layer: `entity`, `ic_elimination`, `cta`, or topside type | not_null |
| `data_area_id` | String | Entity (or blank for non-entity layers) | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | — |
| `amount` | Decimal | Amount for this layer | — |

**Test**: `assert_fctb_entity_layer_ties` — entity layer ties to `gold_consolidated_trial_balance.group_amount`.

### gold_consolidated_ytd

Year-to-date running totals on fully consolidated trial balance.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `adjustment_type` | String | Layer type | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | — |
| `ytd_amount` | Decimal | Cumulative sum of amount through period | — |

## Allocation Model

### gold_allocation_results

Results of driver-based cost allocations (multi-step cascade).

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `allocation_rule_id` | String | Rule identifier | not_null |
| `step_order` | UInt8 | Step number in cascade (1, 2, 3) | — |
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `source_account` | String | Account being allocated from | — |
| `source_cost_center` | String | Cost center being allocated from | — |
| `target_cost_center` | String | Cost center receiving allocation | — |
| `target_account` | String | Account receiving allocation | — |
| `driver_type` | String | Driver used (`headcount`, `sqm`, `revenue`) | — |
| `pool_amount` | Decimal | Total amount in the allocation pool | — |
| `driver_weight` | Decimal | Recipient's share (0–1) | — |
| `allocated_amount` | Decimal | Amount allocated to this target | — |

**Tests**: `assert_each_step_sums_to_pool`, `assert_no_self_allocation`.

## Budget & Variance Models

### gold_spread_budget

Annual budget spread across 12 periods using profile weights. **Primary model for the `budget` scenario.**

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `scenario_id` | String | Budget scenario ID | not_null |
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period (1–12) | — |
| `main_account` | String | Account | — |
| `dim_cost_center` | String | Cost center | — |
| `dim_department` | String | Department | — |
| `annual_amount` | Decimal | Total annual budget | — |
| `spread_profile_id` | String | Spread profile used | — |
| `period_weight` | Decimal | Weight for this period | — |
| `period_amount` | Decimal | `annual_amount × period_weight` | — |

**API mapping**: `scenario=budget` → queries this table.
**Tests**: `assert_spread_sums_to_annual`, `assert_spread_has_12_periods`.

### gold_variance_analysis

Actual vs budget variance with favorable/unfavorable logic. **Primary model for the `variance` scenario.**

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | not_null |
| `account_type` | String | Revenue or Expense | — |
| `actual_amount` | Decimal | From trial balance | — |
| `budget_amount` | Decimal | From spread budget | — |
| `variance_abs` | Decimal | `actual_amount − budget_amount` | — |
| `variance_pct` | Decimal | Variance as % of budget | — |
| `variance_favorable` | UInt8 | 1 if favorable, 0 if unfavorable | — |

**API mapping**: `scenario=variance` → queries this table.
**Tests**: `assert_variance_abs_formula`, `assert_favorable_revenue`, `assert_favorable_expense`.

### gold_variance_ytd

YTD variance: actual vs budget with running totals.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | not_null |
| `ytd_actual` | Decimal | Year-to-date actual amount | — |
| `ytd_budget` | Decimal | Year-to-date budget amount | — |

### gold_variance_quarterly

Quarterly variance: actual vs budget aggregated by quarter.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_quarter` | String | Quarter (Q1–Q4) | not_null |
| `main_account` | String | Account | — |

### gold_prior_year_comparison

Current vs prior year comparison with YoY variance.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Current fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | not_null |
| `current_amount` | Decimal | Current year period amount | — |
| `prior_year_amount` | Decimal | Same period prior year amount | — |
| `yoy_variance_abs` | Decimal | `current_amount − prior_year_amount` | — |

## Scenario & Period Models

### gold_scenario_versions

Scenario version metadata from seed and API.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `scenario_id` | String | Scenario identifier | not_null |
| `scenario_name` | String | Display name | — |
| `scenario_type` | String | `actual`, `budget`, `forecast`, `whatif` | — |
| `is_active` | UInt8 | 1 = active | — |

### gold_scenario_trial_balance

Union of actual + budget + forecast across all scenarios.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `scenario_id` | String | Scenario identifier | not_null |
| `data_area_id` | String | Entity | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | — |
| `amount` | Decimal | Period amount for the scenario | — |

### gold_period_hierarchy

Period dimension mapping fiscal_period to quarter and half labels.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `fiscal_period` | UInt8 | Period number (1–12) | not_null, unique |
| `fiscal_quarter` | String | Quarter label (Q1–Q4) | — |
| `fiscal_half` | String | Half-year label (H1, H2) | — |
