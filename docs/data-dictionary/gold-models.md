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

**Test**: `assert_ytd_at_last_regular_period_equals_annual` (warn) — YTD at the year's last Regular period (from `epm_staging.fiscal_periods`, not a hardcoded 12) must equal the sum of the year's Regular periods; the Closing period is left out because the year-end close posted there (`silver_tb_movements`) reclassifies the year's result, it is not activity.

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
`cash_flow_categories` seed (`cash_flow_amount = period_movement × sign`) and
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
| `cf_line_item` | String | Sub-line label from seed | — |
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
and categorized identically via the seed, so CTA revaluations land in the
affected account's category and the statement still ties to the change in
translated cash.

Grain: `consolidation_group × fiscal_year × fiscal_period × cf_category × cf_line_item × main_account`.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Consolidation group | not_null |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | Fiscal period | — |
| `cf_category` | String | Operating / Investing / Financing | accepted_values |
| `cf_line_item` | String | Sub-line label from seed | — |
| `main_account` | String | Source BS account | — |
| `cash_flow_amount` | Decimal | `amount × sign`, summed over layers | — |

Reconciliation (`assert_consolidated_cf_reconciles`): per group/year/period,
`Σ(O + I + F) = Σ amount of is_cash accounts across all layers`, within ±0.01.
Holds when the consolidated BS balances (see `assert_end_to_end_bs_balances`).

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

**Tests**: `assert_translated_amount_formula`, `assert_group_amount_formula`, `assert_nci_plus_group_equals_translated`, `assert_nci_zero_for_full_ownership`, `assert_translation_follows_fx_method`.

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

### gold_business_combination_journal

The balanced acquisition journal per submitted Business Combination
(`epm_staging.business_combinations` and its child tables), `journal_id =
ACQ-<group>-<entity>-<acquisition_date>`, group currency, posted once in the
acquisition period. Design: [Business Combinations](../developer-guide/design/business-combinations.md).

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | The acquiring group | not_null |
| `data_area_id` | String | The acquired entity | — |
| `fiscal_year` | UInt16 | Acquisition fiscal year | — |
| `fiscal_period` | UInt8 | Acquisition period from `epm_staging.fiscal_periods` (`start_date <= acquisition_date <= end_date`, Closing periods skipped) | — |
| `main_account` | String | Account posted to (declared on the group root, or the acquired balance's account) | not_null |
| `account_name` | String | Account name from the chart | — |
| `adjustment_type` | String | `acquisition` | accepted_values |
| `adjustment_amount` | Decimal | Group currency; debit positive, credit negative | — |
| `acquisition_date` | Date | From the deal header | — |
| `journal_id` | String | `ACQ-<group>-<entity>-<acquisition_date>` | not_null |
| `line_no` | UInt16 | 0 opening_balance lines; the child idx for equity lines; 101 fva, 102 goodwill, 103 investment, 104 nci, 105 bargain_gain, 110+idx costs, 130+idx their settlement credit | — |
| `account_role` | String | `opening_balance`, `equity_eliminated`, `fva`, `goodwill`, `investment`, `nci`, `bargain_gain`, `costs`, `proceeds` | accepted_values |
| `deal` | String | The Business Combination document name | — |
| `measurement_basis` | String | How net assets were measured: `acquired_balances`, `header_net_assets` or `measured_from_tb` | — |

**Tests**: `assert_acquisition_journal_balances` (each journal sums to 0 per period),
`assert_acquisition_accounts_declared`, `assert_bargain_purchase_refused`,
`assert_goodwill_calculated`, `assert_acquisition_measured_in_period` (warn).

### gold_goodwill_amortisation_journal

Straight-line goodwill amortisation per the group's `goodwill_treatment`; empty under
`Impairment only`. `journal_id = GWA-<group>-<entity>-<acquisition_date>`, two lines in
every Regular period from the acquisition period until fully amortised or the
disposal period.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group | not_null |
| `data_area_id` | String | The acquired entity | — |
| `fiscal_year` | UInt16 | Fiscal year | — |
| `fiscal_period` | UInt8 | A Regular period of the declared calendar | — |
| `main_account` | String | `goodwill_amortisation_expense_account` or `goodwill_account` | not_null |
| `account_name` | String | Account name | — |
| `adjustment_type` | String | `goodwill_amortisation` | accepted_values |
| `adjustment_amount` | Decimal | Group currency; the instalment (+ expense, − goodwill) | — |
| `acquisition_date` | Date | From the deal header | — |
| `journal_id` | String | `GWA-<group>-<entity>-<acquisition_date>` | not_null |
| `line_no` | UInt8 | 1 the expense debit, 2 the goodwill credit | — |
| `account_role` | String | `amortisation_expense`, `goodwill` | accepted_values |
| `deal` | String | The Business Combination document name | — |
| `instalment` | UInt32 | The period's number within the schedule, 1 .. `n_instalments` | — |
| `n_instalments` | UInt32 | `goodwill_amortisation_years` × Regular periods of the acquisition year | — |

**Test**: `assert_goodwill_amortisation_journal_balances`.

### gold_business_disposal_journal

The balanced disposal journal per submitted Business Disposal
(`epm_staging.business_disposals` and its proceeds lines), full disposals only
(`retained_interest_pct = 0`), `journal_id = DSP-<group>-<entity>-<disposal_date>`,
posted once in the disposal period. Replaced `gold_disposal_adjustments`.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group | not_null |
| `data_area_id` | String | The disposed entity | — |
| `fiscal_year` | UInt16 | Disposal fiscal year | — |
| `fiscal_period` | UInt8 | Disposal period from `epm_staging.fiscal_periods` | — |
| `main_account` | String | Account posted to (`CTA` for the recycling line) | not_null |
| `account_name` | String | Account name | — |
| `adjustment_type` | String | `disposal` | accepted_values |
| `adjustment_amount` | Decimal | Group currency; debit positive, credit negative | — |
| `disposal_date` | Date | From the deal header | — |
| `journal_id` | String | `DSP-<group>-<entity>-<disposal_date>` | not_null |
| `line_no` | UInt16 | 0 derecognised lines; 101 goodwill, 102 fva, 103 cta, 104 nci, 110+idx proceeds (110 for the header figure), 199 gain_loss | — |
| `account_role` | String | `derecognised`, `goodwill`, `fva`, `cta`, `nci`, `proceeds`, `gain_loss` | accepted_values |
| `deal` | String | The Business Disposal document name | — |

**Tests**: `assert_disposal_journal_balances`, `assert_disposal_gain_loss_exists`,
`assert_cta_recycled_on_disposal`.

### gold_fully_consolidated_tb

Unified consolidated TB: entity balances + IC eliminations + CTA + topside adjustments
+ equity method + the acquisition/disposal layer (P&L proration and the three deal journals).

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `consolidation_group` | String | Group identifier | not_null |
| `adjustment_type` | String | Layer: `entity`, `ic_elimination`, `ic_elimination_nci`, `cta`, `equity_method`, `pnl_proration`, `acquisition`, `goodwill_amortisation`, `disposal`, or topside type | not_null |
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
