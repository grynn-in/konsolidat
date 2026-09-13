# Gold Models

Business-ready models in the `epm_gold` schema (46 in `dbt_project/models/gold/`), consumed by the Frappe API and Excel reports. This page documents the main ones.

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

### gold_trial_balance_by_partner

`gold_trial_balance` with one row per intercompany partner (konsol #159). Only `gold_consolidated_trial_balance` reads it. `gold_trial_balance` keeps the account grain that its own readers (year-on-year, YTD, P&L) join and window on. Summing this model over `partner_data_area_id` gives `gold_trial_balance`.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | — |
| `account_name`, `account_type_name` | String | Account name and type | — |
| `is_balance_sheet`, `is_pnl` | 0/1 | Account class | — |
| `partner_data_area_id` | String | The other group entity the row is held with; `''` where the row has none | — |
| dimension columns | String | As in `gold_trial_balance` | — |
| measure columns | Decimal | As in `gold_trial_balance` (`period_debit`, `period_credit`, …) | — |

**Test**: `assert_partner_grain_not_fanned_out` — the partner never fans out a per-account figure (`gold_trial_balance` grain, consolidated YTD).

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

## Cash Flow Models

### gold_cash_flow_indirect

Entity-level cash flow statement (indirect method). Each non-cash balance-sheet
account's `period_movement` is converted to a cash effect via the
published **Cash Flow Category** mappings (`epm_staging.cash_flow_categories`; `cash_flow_amount = period_movement × sign`) and
classified into Operating / Investing / Financing. Net income is captured by the
retained-earnings (3100) movement, not a separate P&L pull, so nothing is
double-counted. Cash accounts (`is_cash = 1`) are excluded from the activity
lines and define the reconciliation target. Opening-balance artifact rows
(`fiscal_period = 0`) are dropped.

Grain: `data_area_id × fiscal_year × fiscal_period × cf_category × cf_line_item × main_account`.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area_id` | String | Legal entity | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `cf_category` | String | Operating / Investing / Financing | accepted_values |
| `cf_line_item` | String | Sub-line label from the Cash Flow Category | — |
| `main_account` | String | Source BS account | — |
| `cash_flow_amount` | Decimal | `period_movement × sign`, summed over dimensions | — |

Reconciliation (`assert_cf_categories_equal_net_change`): per entity/year/period,
`Σ(Operating + Investing + Financing) = Σ period_movement of is_cash accounts`,
within ±0.01. Holds only when the BS balances each period.

### gold_consolidated_cash_flow

Group-level cash flow statement built **after FX translation** from
`gold_fully_consolidated_tb` (entity translated balances + IC elimination + CTA +
topside + equity-method + acquisition/disposal). Because `amount` there is a
per-period flow, it is the period movement directly — no consecutive-period
delta is needed. Each layer's amount is folded into the underlying `main_account`
and categorized identically via the Cash Flow Category mappings, so CTA revaluations land in the
affected account's category and the statement still ties to the change in
translated cash.

Grain: `consolidation_group × fiscal_year × fiscal_period × cf_category × cf_line_item × main_account`.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Consolidation group | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `cf_category` | String | Operating / Investing / Financing | accepted_values |
| `cf_line_item` | String | Sub-line label from the Cash Flow Category | — |
| `main_account` | String | Source BS account | — |
| `cash_flow_amount` | Decimal | `amount × sign`, summed over layers | — |

Reconciliation (`assert_consolidated_cf_reconciles`): per group/year/period,
`Σ(O + I + F) = Σ amount of is_cash accounts across all layers`, within ±0.01.
Holds when the consolidated BS balances (see `assert_end_to_end_bs_balances`).

## Consolidation Models

### gold_consolidated_trial_balance

Multi-company consolidated trial balance with currency translation. One row per group, entity, period, account, dimensions and intercompany partner; an entity appears once for each ancestor group it line-consolidates into (method not `equity` or `none`, complete ownership chain).

Rates come only from the approved **Group Exchange Rates** in `epm_staging.group_exchange_rates`, looked up by (entity currency, group reporting currency, fiscal year, fiscal period) and used exactly as published: the true rate, units of the group currency per 1 unit of the entity currency. The model's first pre-hook refuses the run, **before** it deletes its scope, when a translated key has no usable rate (missing, duplicate, invalid, or more than 10× from the USD references), listing up to 50 keys. See the [Exchange Rates Guide](../user-guide/exchange-rates-guide.md#how-consolidation-uses-the-rates).

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `data_area_id` | String | Legal entity | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `main_account` | String | Account | — |
| `account_name`, `account_type_name` | String | Account name and type | — |
| `is_balance_sheet`, `is_pnl`, `is_equity` | 0/1 | Account class; equity is looked up for a historical rate | — |
| `local_amount` | Decimal | Signed amount (debit − credit) in the entity's own currency | — |
| `accounting_currency` | String | Entity's functional currency (from `silver_entity_currencies`) | — |
| `reporting_currency` | String | The group's Reporting Currency, from its Consolidation Group node | — |
| `ownership_pct` | Decimal | Effective ownership for the period, as a fraction (`gold_entity_ownership`) | — |
| `consolidation_method` | String | The weakest method on the ownership chain | — |
| `closing_rate` | Float64 | Governed Closing rate (1 for a same-currency entity) | — |
| `average_rate` | Float64 | Governed Average rate (1 for a same-currency entity) | — |
| `historical_equity_rate` | Float64 | Historical Equity Rate in force for the period, if any | — |
| `translation_rate` | Float64 | Rate applied: 1 for a same-currency entity; the historical rate for equity that has one; closing for balance sheet; average for P&L | — |
| `translated_amount` | Decimal | `local_amount × translation_rate` (100%) | — |
| `group_amount` | Decimal | `translated_amount × ownership_pct` | — |
| `nci_amount` | Decimal | `translated_amount × (1 − ownership_pct)` | — |
| `partner_data_area_id` | String | Intercompany partner (`''` for none). The last column | — |

**Tests**: `assert_translated_amount_formula`, `assert_group_amount_formula`, `assert_nci_plus_group_equals_translated`, `assert_nci_zero_for_full_ownership`, `assert_bs_uses_closing_rate`, `assert_pnl_uses_average_rate`. Governed rates (warn): `assert_every_translated_currency_has_a_governed_rate` (lists every key without a usable rate), `assert_governed_rate_sane`, `assert_governed_rate_grain_unique`. `assert_fx_magnitude_cases` runs the magnitude rule over a fixed case table; `assert_exchange_rate_sane_magnitude` (warn) checks the ERP's quotes, which only feed konsol's pre-fill.

### gold_ic_reconciliation

Intercompany pairs (konsolidat #148, konsol #159): a row for each pair in each period where either side booked something, plus the period the pair joins a group and the first period after it leaves; a balance-sheet pair's row carries its balance to date. A side is (entity, partner, account) on a Published Intercompany Account; its other side is (partner, entity, counterpart account). Side `a` is the lexically smaller (entity, account). Both sides are compared at 100% in the group's reporting currency; a balance-sheet pair on its balance to date, a P&L pair on the period's movement. A pair is live while both entities line-consolidate into the group, from the ownership windows. See the [Intercompany Guide](../user-guide/intercompany-guide.md).

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group | — |
| `fiscal_year`, `fiscal_period` | | Period | — |
| `entity_a`, `account_a` | String | Side a | not_null (`entity_a`) |
| `entity_b`, `account_b` | String | Side b | — |
| `basis` | String | `balance` (balance-sheet pair, to date) or `movement` (P&L pair) | accepted_values |
| `pair_event` | String | `joined` (first period both are members), `left` (first period after the pair stops being live: both sides 0, everything reversed), or `''` | accepted_values |
| `currency_a`, `currency_b` | String | Each entity's functional currency | — |
| `local_a`, `local_b` | Float64 | Each side in its entity's own currency | — |
| `balance_a`, `balance_b` | Float64 | Each side at 100% (`translated_amount`), in group currency: what pairs match on | — |
| `group_balance_a`, `group_balance_b` | Float64 | Each side at the group's share (`group_amount`) | — |
| `share_a`, `share_b` | Float64 | The share of each side the group view holds | — |
| `matched_amount` | Float64 | The smaller side when the two offset, else 0 | — |
| `difference` | Float64 | `balance_a + balance_b` (`net_balance` holds the same figure) | — |
| `residual_a`, `residual_b` | Float64 | What is left of each side once the matched amount is eliminated | — |
| `difference_cause` | String | `none`, `booking` or `fx` | accepted_values |
| `ic_difference_account` | String | The group's Intercompany Difference Account (`''` if none) | — |
| `tolerance` | Float64 | The group's Intercompany Difference Tolerance | — |
| `match_status` | String | `matched`, `within_tolerance`, `over_tolerance` (booking differences), or `fx_difference` (never counts against tolerance) | accepted_values |

**Tests**: `assert_ic_reconciliation_matched`, `assert_ic_pair_basis`, `assert_ic_difference_cause`, `assert_ic_difference_not_from_ownership`, `assert_ic_pair_left_is_reversed`, `assert_ic_account_in_one_pair`, `assert_ic_difference_account_in_chart` (warn).

### gold_ic_eliminations

Intercompany elimination entries. Each row is a two-legged entry: `debit_account` takes `debit_elimination` (≤ 0) and `credit_account` takes `credit_elimination` (≥ 0), so every row nets to zero. Balance entries come from `gold_ic_reconciliation`; `unrealized_profit` entries come from IC Elimination Rules and IC Balance. A balance-sheet pair posts, each period, the change in its eliminations since the previous period.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `rule_id` | String | `IC:<account_a>/<account_b>` for a balance entry; the rule ID for unrealised profit | not_null |
| `rule_name` | String | `Intercompany: <kind>`, or the rule's name | — |
| `rule_type` | String | `balance` or `unrealized_profit` | — |
| `consolidation_group` | String | Group | — |
| `fiscal_year`, `fiscal_period` | | Period | — |
| `debit_account`, `credit_account` | String | The two legs' accounts. The NCI line is the account `NCI` unless the dbt var `ic_nci_account` maps it | — |
| `debit_entity`, `credit_entity` | String | The entity on each leg | — |
| `elimination_amount` | Float64 | Size of the entry | — |
| `debit_elimination`, `credit_elimination` | Float64 | `−elimination_amount`, `+elimination_amount` | — |
| `elimination_kind` | String | `matched`, `nci` (minority's portion to the NCI line), `difference` (to the difference account) or `unrealized_profit` | accepted_values |
| `difference_cause` | String | On `difference` rows, `booking` or `fx`; `''` otherwise | — |
| `basis` | String | `balance` or `movement`; `''` for unrealised profit | — |
| `elimination_view` | String | `group` (booked by `gold_fully_consolidated_tb`) or `nci` (the minority's share, added by the consolidation report for its 100% column) | accepted_values |
| `entity_a`, `account_a`, `entity_b`, `account_b` | String | The pair a balance entry belongs to (`''` for unrealised profit) | — |

**Tests**: `assert_ic_elimination_nets_zero` (each entry, the layer, and each pair in the group view), `assert_ic_nci_line_nets_zero`, `assert_ic_full_view_nets_zero`, `assert_ic_elimination_within_balance`, `assert_ic_nci_leg_entity`.

### gold_ic_unmatched

Balances on Published intercompany accounts with **no partner** (decision 2, 13 Sep 2026). They are never eliminated and nothing guesses their partner; they stay in the consolidated figures and are listed here. This includes every connector (D365, ERPNext) ledger line on an intercompany account until the ERP's partner is mapped.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group | — |
| `fiscal_year`, `fiscal_period` | | Period | — |
| `data_area_id` | String | Entity | not_null |
| `main_account` | String | The intercompany account | — |
| `counterpart_account` | String | Its counterpart in the pair | — |
| `unmatched_local_amount` | Decimal | In the entity's own currency | — |
| `unmatched_amount` | Decimal | In group currency, at the group's share (`group_amount`) | — |
| `reason` | String | `no partner` | — |

Rows under 0.005 in group currency are left out.

### gold_fx_revaluation

Currency translation adjustment (CTA) entries.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `data_area_id` | String | Entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `cta_amount` | Decimal | `−Σ group_amount` per entity and period: the residual that balances the translated group share | — |

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

Unified consolidated TB: entity balances + IC eliminations + CTA + topside adjustments + equity-method entries + acquisition/disposal adjustments. A table, rebuilt in full on every run. The entity layer sums `gold_consolidated_trial_balance` over intercompany partners; the IC layers take the group view of `gold_ic_eliminations` only.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `adjustment_type` | String | Layer: `entity`, `ic_elimination`, `ic_elimination_nci` (the minority's portion moved to the NCI line), `cta`, `equity_method`, an acquisition/disposal type, or a topside type | not_null |
| `data_area_id` | String | Entity (blank for non-entity layers; on `ic_elimination_nci` legs, the entity whose minority holds the amount) | — |
| `journal_id` | String | Source journal; the `rule_id` for IC eliminations | — |
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

Scenario version metadata from konsol's **Scenario** doctype (`epm_gold.scenario_definitions`) and the API.

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
