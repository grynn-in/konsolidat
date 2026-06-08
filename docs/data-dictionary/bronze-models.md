# Bronze Models

14 models in the `epm_bronze` schema. Raw D365 OData data, type-cast to ClickHouse types and renamed to snake_case. No business logic applied.

All Bronze models source from Airbyte-managed tables in the `epm_bronze` database.

## General Ledger

### bronze_general_journal_account_entries

GL line items — debits and credits.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `recid` | Int64 | D365 record ID | not_null |
| `data_area_id` | String | Legal entity | not_null |
| `main_account` | String | Account code |  |
| `debit_amount` | Decimal(18,2) | Debit in accounting currency |  |
| `credit_amount` | Decimal(18,2) | Credit in accounting currency |  |
| `accounting_currency_amount` | Decimal(18,2) | Net amount |  |
| `general_journal_entry_recid` | Int64 | FK to journal headers |  |

### bronze_general_journal_entries

Journal headers.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `recid` | Int64 | D365 record ID | not_null |
| `journal_number` | String | Journal entry number |  |
| `accounting_date` | Date | Posting date |  |
| `subledger_voucher` | String | Voucher number |  |

## Chart of Accounts

### bronze_main_accounts

Account master data.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `main_account_id` | String | Account code | not_null |
| `name` | String | Account name |  |
| `type` | String | Account type (D365 enum: 0–7 or string) |  |

### bronze_main_account_categories

Account category mapping.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `recid` | Int64 | Record ID | not_null |
| `account_category` | String | Category name |  |

## Organization

### bronze_legal_entities

Legal entity / company master.

| Column | Type | Description | Test |
|--------|------|-------------|------|
| `data_area` | String | Entity code | not_null, unique |
| `name` | String | Company name |  |
| `accounting_currency` | String | Functional currency |  |

## Fiscal Calendar

### bronze_fiscal_calendars

Calendar definitions.

| Column | Type | Description |
|--------|------|-------------|
| `calendar_id` | String | Calendar identifier |
| `description` | String | Calendar name |

### bronze_fiscal_calendar_years

Year definitions within a calendar.

| Column | Type | Description |
|--------|------|-------------|
| `fiscal_calendar_id` | String | FK to calendar |
| `start_date` | Date | Year start date |
| `end_date` | Date | Year end date |
| `name` | String | Year label |

## Financial Dimensions

### bronze_financial_dimensions

Dimension definitions.

| Column | Type | Description |
|--------|------|-------------|
| `dimension_name` | String | Dimension name (e.g., CostCenter, Department) |

### bronze_financial_dimension_values

Dimension value master.

| Column | Type | Description |
|--------|------|-------------|
| `dimension_name` | String | Parent dimension |
| `dimension_value` | String | Value code |
| `description` | String | Display description |
| `is_active` | UInt8 | Active flag |

## Exchange Rates

### bronze_exchange_rate_currency_pairs

Exchange rate data.

| Column | Type | Description |
|--------|------|-------------|
| `from_currency` | String | Source currency |
| `to_currency` | String | Target currency |
| `exchange_rate` | Float64 | Rate (D365 stores × 100) |
| `valid_from` | Date | Effective start |
| `valid_to` | Date | Effective end |

### bronze_exchange_rate_types

Rate type definitions.

| Column | Type | Description |
|--------|------|-------------|
| `name` | String | Rate type name (e.g., Default) |
| `description` | String | Description |

## Budget

### bronze_budget_register_entries

Budget register headers.

| Column | Type | Description |
|--------|------|-------------|
| `entry_number` | String | Register entry number |
| `budget_model_id` | String | Budget model identifier |
| `status` | String | Entry status |

### bronze_budget_transaction_lines

Budget line items.

| Column | Type | Description |
|--------|------|-------------|
| `main_account` | String | Account code |
| `amount` | Decimal(18,2) | Budget amount |
| `date` | Date | Budget date |
| `data_area_id` | String | Legal entity |

## Consolidation

### bronze_consolidation_account_groups

Consolidation account group mapping.

| Column | Type | Description |
|--------|------|-------------|
| `consolidation_account_group` | String | Group identifier |

## Trial Balance Snapshot

### bronze_trial_balance_snapshot

Pre-built trial balance from D365 (fiscal year snapshots).

| Column | Type | Description |
|--------|------|-------------|
| `data_area_id` | String | Legal entity |
| `fiscal_year` | UInt16 | Year |
| `main_account` | String | Account code |
| `debit_amount` | Decimal(18,2) | Annual debit |
| `credit_amount` | Decimal(18,2) | Annual credit |
