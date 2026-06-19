# Seeds Reference

12 CSV seed files loaded into the `epm_gold` schema via `dbt seed`.

## cash_flow_categories.csv

Maps each balance-sheet GL account to a cash flow category and the sign that
converts a BS movement into its cash effect. Consumed by
`gold_cash_flow_indirect` and `gold_consolidated_cash_flow` (Phase 6.1).

| Column | Type | Description |
|--------|------|-------------|
| `main_account` | String | GL account (matches `gold_bs_movement.main_account`) |
| `cf_category` | String | `Operating`, `Investing`, or `Financing` |
| `cf_line_item` | String | Sub-line label (e.g. `Change in Trade Receivables`, `Dividends Paid`) |
| `is_cash` | UInt8 | 1 = account *is* cash/cash-equivalent (excluded from activity, defines reconciliation target) |
| `sign` | Int8 | `+1` (credit-natured: liabilities, equity, contra-assets) or `-1` (debit-natured: assets, contra-equity) — an asset increase is a cash outflow |

**Default data**: 12 rows for the demo chart — cash (`1010`, `is_cash=1`);
receivables/inventory/IC receivable, payables/accrued, accumulated depreciation,
and retained earnings → Operating; fixed assets → Investing; long-term debt,
share capital, and dividends declared → Financing.

## allocation_rules.csv

Defines multi-step allocation rules.

| Column | Type | Description |
|--------|------|-------------|
| `allocation_rule_id` | String | Unique rule ID (e.g., `ALLOC_001`) |
| `rule_name` | String | Human-readable name |
| `step_order` | Int | Execution order (1, 2, 3) |
| `source_account` | String | GL account to allocate from |
| `source_cost_center` | String | Cost center holding the pool |
| `driver_type` | String | Driver name: `headcount`, `sqm`, `revenue` |
| `target_account` | String | GL account to allocate to |
| `description` | String | Rule description |

**Default data**: 3 rules (IT → headcount, Facility → sqm, Management → revenue).

## allocation_drivers_headcount.csv

Headcount driver values per cost center.

| Column | Type | Description |
|--------|------|-------------|
| `data_area_id` | String | Legal entity |
| `cost_center` | String | Cost center |
| `driver_value` | Decimal | Headcount number |
| `fiscal_year` | UInt16 | Year |
| `fiscal_period` | UInt8 | Period |

## allocation_drivers_sqm.csv

Square meter driver values per cost center. Same schema as headcount.

## allocation_drivers_revenue.csv

Revenue driver values per cost center. Same schema as headcount. Values ≤ 0 are excluded during allocation.

## budget_annual_input.csv

Annual budget line items to be spread across 12 periods.

| Column | Type | Description |
|--------|------|-------------|
| `scenario_id` | String | Budget scenario (e.g., `BUDGET_2025`) |
| `data_area_id` | String | Legal entity |
| `fiscal_year` | UInt16 | Budget year |
| `main_account` | String | GL account |
| `dim_cost_center` | String | Cost center |
| `dim_department` | String | Department |
| `annual_amount` | Decimal | Total annual budget |
| `spread_profile_id` | String | How to spread (e.g., `EVEN`, `SEASONAL_RETAIL`) |
| `submitted_by` | String | Who submitted |

## spread_profiles.csv

Monthly weight profiles for budget spreading. Each profile has 12 rows (one per period).

| Column | Type | Description |
|--------|------|-------------|
| `profile_id` | String | Profile identifier |
| `profile_name` | String | Display name |
| `fiscal_period` | UInt8 | Period (1–12) |
| `weight` | Decimal | Relative weight for this month |

**Default profiles**:
- `EVEN` — all weights = 1.0 (equal monthly distribution)
- `SEASONAL_RETAIL` — weights 0.5–2.5 (Q4 peak: period 12 = 2.5)

Weights are normalized during spreading: `period_weight = weight / SUM(all 12 weights)`.

## consolidation_groups.csv

Maps legal entities to consolidation groups with ownership percentages.

| Column | Type | Description |
|--------|------|-------------|
| `consolidation_group` | String | Group identifier |
| `data_area_id` | String | Legal entity code |
| `entity_name` | String | Company name |
| `ownership_pct` | Decimal(5,2) | Parent ownership (0–100) |
| `reporting_currency` | String | Group reporting currency |
| `consolidation_method` | String | Method: `full` |

**Default data**: GROUP_CORP with USMF (100%), DEMF (100%), GBMF (80%), JPMF (51%).

## consolidation_adjustments.csv

Top-side journal entries posted at the group level.

| Column | Type | Description |
|--------|------|-------------|
| `consolidation_group` | String | Group |
| `adjustment_type` | String | Type of adjustment |
| `journal_id` | String | Journal entry ID |
| `data_area_id` | String | Entity |
| `fiscal_year` | UInt16 | Year |
| `fiscal_period` | UInt8 | Period |
| `main_account` | String | Account |
| `debit_amount` | Decimal(18,2) | Debit |
| `credit_amount` | Decimal(18,2) | Credit |
| `description` | String | Narrative |
| `posted_by` | String | Who posted |

Each journal must balance (total debits = total credits).

## ic_elimination_rules.csv

Intercompany elimination rule definitions.

| Column | Type | Description |
|--------|------|-------------|
| `rule_id` | String | Rule identifier |
| `rule_name` | String | Display name |
| `debit_account` | String | Debit-side account |
| `credit_account` | String | Credit-side account |
| `debit_entity_pattern` | String | Entity filter for debit side (`*` = all) |
| `credit_entity_pattern` | String | Entity filter for credit side (`*` = all) |
| `description` | String | Rule description |

**Default rules**:
- `IC_001`: IC Receivable (1300) / Payable (2100)
- `IC_002`: IC Revenue (4000) / COGS (5000)
- `IC_003`: IC Dividend (8100) / Equity (3200)

## scenario_definitions.csv

Scenario metadata.

| Column | Type | Description |
|--------|------|-------------|
| `scenario_id` | String | Unique identifier |
| `scenario_name` | String | Display name |
| `scenario_type` | String | Type: `actual`, `budget`, `forecast`, `whatif` |
| `is_active` | UInt8 | 1 = active, 0 = inactive |

**Default data**: ACTUAL, BUDGET, FORECAST (active), WHATIF_01 (inactive).

## entity_fiscal_calendars.csv

Maps legal entities to their fiscal calendar.

| Column | Type | Description |
|--------|------|-------------|
| `data_area_id` | String | Legal entity code |
| `fiscal_calendar_id` | String | Calendar ID from D365 |

**Default data**: 65+ entities mapped. Most use `Fiscal`; regional variants include `Fiscal_CN`, `Fiscal_IN`, `Fiscal_MY`, `Fiscal_SA`, `Fiscal_TH`, and bespoke calendars.
