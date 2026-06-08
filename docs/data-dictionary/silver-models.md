# Silver Models

8 cleaned, deduplicated, and standardized models in the `epm_silver` schema.

## silver_gl_entries

GL entries joined with journal headers, with flattened dimension columns.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `recid` | Int64 | D365 record ID | not_null |
| `data_area_id` | String | Legal entity | not_null |
| `accounting_date` | Date | Posting date | not_null |
| `fiscal_year` | UInt16 | Fiscal year derived from accounting_date |  |
| `fiscal_period` | UInt8 | Fiscal period (1–12) |  |
| `main_account` | String | Account code |  |
| `debit_amount` | Decimal(18,2) | Debit in accounting currency |  |
| `credit_amount` | Decimal(18,2) | Credit in accounting currency |  |
| `accounting_currency_amount` | Decimal(18,2) | Net amount (debit − credit) |  |
| `dim_cost_center` | String | Cost center dimension |  |
| `dim_department` | String | Department dimension |  |
| `dim_business_unit` | String | Business unit dimension |  |
| `journal_number` | String | Journal entry number |  |

**Sources**: `bronze_general_journal_account_entries` + `bronze_general_journal_entries` (joined on journal header RecId).

## silver_main_accounts

Chart of accounts with readable account type labels.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `main_account_id` | String | Account code | not_null, unique (warn) |
| `account_name` | String | Account name |  |
| `account_type` | String | Mapped type: Revenue, Expense, Asset, Liability, Equity, Total |  |
| `account_category` | String | Category from D365 |  |

**Sources**: `bronze_main_accounts` + `bronze_main_account_categories`. Account type mapping via `map_account_type()` macro.

## silver_legal_entities

Company master with currency.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area` | String | Legal entity code | not_null, unique |
| `entity_name` | String | Company name |  |
| `accounting_currency` | String | Functional currency code |  |

**Source**: `bronze_legal_entities`.

## silver_fiscal_periods

Standardized fiscal period lookup table.

| Column | Type | Description |
|--------|------|-------------|
| `fiscal_calendar_id` | String | Calendar identifier |
| `fiscal_year` | UInt16 | Year |
| `fiscal_period` | UInt8 | Period number (0–13, including special periods) |
| `period_start` | Date | First day of period |
| `period_end` | Date | Last day of period |
| `period_label` | String | Display label |
| `fiscal_quarter` | String | Quarter (Q1–Q4 or OPN/CLS) |
| `fiscal_half` | String | Half (H1, H2 or OPN/CLS) |

**Sources**: `bronze_fiscal_calendars` + `bronze_fiscal_calendar_years`. Generates monthly periods from year start/end dates.

## silver_financial_dimensions

Dimension value master with active status.

| Column | Type | Description |
|--------|------|-------------|
| `dimension_name` | String | Dimension name (e.g., CostCenter) |
| `dimension_value` | String | Dimension value code |
| `description` | String | Display description |
| `is_active` | UInt8 | 1 = active |

**Sources**: `bronze_financial_dimensions` + `bronze_financial_dimension_values`.

## silver_exchange_rates

Cleaned exchange rates. D365 stores rates multiplied by 100; this model divides by 100.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `from_currency` | String | Source currency code |  |
| `to_currency` | String | Target currency code |  |
| `exchange_rate` | Float64 | Rate (D365 value ÷ 100) | not_null |
| `exchange_rate_type` | String | Rate type (e.g., Default) |  |
| `valid_from` | Date | Rate effective start date |  |
| `valid_to` | Date | Rate effective end date |  |

**Sources**: `bronze_exchange_rate_currency_pairs` + `bronze_exchange_rate_types`.

## silver_budget_entries

Standardized budget lines joined with register headers.

| Column | Type | Description |
|--------|------|-------------|
| `entry_number` | String | Budget register entry number |
| `budget_model_id` | String | Budget model |
| `main_account` | String | Account code |
| `data_area_id` | String | Legal entity |
| `transaction_date` | Date | Budget date |
| `fiscal_year` | UInt16 | Fiscal year |
| `fiscal_period` | UInt8 | Fiscal period |
| `amount` | Decimal(18,2) | Budget amount |
| `dim_cost_center` | String | Cost center |
| `dim_department` | String | Department |

**Sources**: `bronze_budget_register_entries` + `bronze_budget_transaction_lines`.

## silver_trial_balance

Trial balance from D365 snapshot entity — used as a validation baseline against the computed trial balance.

| Column | Type | Description |
|--------|------|-------------|
| `data_area_id` | String | Legal entity |
| `fiscal_year` | UInt16 | Fiscal year |
| `main_account` | String | Account code |
| `debit_amount` | Decimal(18,2) | Annual debit total |
| `credit_amount` | Decimal(18,2) | Annual credit total |

**Source**: `bronze_trial_balance_snapshot`.
