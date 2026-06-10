# PRD-30: Canonical Staging Schema & Adapter Interface

**Status:** In Progress
**Priority:** P0 — Foundation for all multi-ERP work
**Labels:** `multi-erp`, `prd-30`
**Dependencies:** None (this is the root of the multi-ERP dependency graph)
**Blocks:** PRD-31, PRD-32, PRD-33, PRD-34, PRD-35, PRD-36

---

## Problem

Konsolidat's 15 staging models (`stg_d365__*`) are hardcoded to D365 F&O OData entity names and column conventions. The bronze layer directly references these D365-specific models via `{{ ref('stg_d365__gl_account_entries') }}`. This means:

1. Adding a new ERP (SAP, ERPNext, D365 BC) requires modifying every bronze model
2. There is no contract defining what a staging adapter must produce
3. Column names leak D365 conventions (`dataAreaId`, `RecId`) into layers that should be ERP-agnostic

The silver and gold layers are already ERP-agnostic — they consume from bronze with generic column names. The gap is between raw ERP data and bronze.

## Solution

Introduce a **canonical staging interface** — a set of 7 staging models with standardised column names that every ERP adapter must produce. Each canonical model UNION ALLs from per-ERP adapters, gated by `var('erp_sources')`.

### Architecture

```
Raw ERP Data (Airbyte)
    ↓
Per-ERP Adapters (e.g., stg_d365_fo__gl_entries)
    ↓
Canonical Staging (stg_gl_entries — UNION ALL from adapters)
    ↓
Bronze (type casting, ClickHouse materialisation)
    ↓
Silver → Gold (unchanged)
```

### Canonical Models

| Model | Purpose | Key Columns |
|-------|---------|-------------|
| `stg_gl_entries` | GL line items | erp_source, record_id, entity_id, posting_date, main_account, amount |
| `stg_trial_balance` | Period-end TB snapshots | erp_source, entity_id, main_account, fiscal_year, opening/closing balance |
| `stg_accounts` | Chart of accounts | erp_source, account_id, account_name, account_type |
| `stg_legal_entities` | Company/entity master | erp_source, entity_id, entity_name, accounting_currency |
| `stg_exchange_rates` | FX rates | erp_source, from_currency, to_currency, valid_from, rate |
| `stg_budget_entries` | Budget lines | erp_source, entity_id, posting_date, main_account, amount |
| `stg_fiscal_periods` | Fiscal calendar | erp_source, calendar_id, fiscal_year, start_date, end_date |

### `erp_source` Column

Every canonical model includes `erp_source` (String) identifying the source ERP:

| Value | ERP |
|-------|-----|
| `d365_fo` | Dynamics 365 Finance & Operations |
| `d365_bc` | Dynamics 365 Business Central |
| `sap_s4` | SAP S/4HANA |
| `sap_ecc` | SAP ECC 6.0 |
| `sap_b1` | SAP Business One |
| `erpnext` | ERPNext |

### `erp_sources` Variable

`dbt_project.yml` gains a new var:

```yaml
vars:
  erp_sources:
    - d365_fo
```

Canonical models conditionally include adapters based on this list. Adding a new ERP is:
1. Write the adapter models in `models/staging/<erp>/`
2. Add the ERP key to `erp_sources`
3. `dbt build` — canonical models automatically UNION the new adapter

## Canonical Column Specifications

### stg_gl_entries

```
erp_source            String    -- 'd365_fo', 'sap_s4', 'erpnext', etc.
record_id             String    -- unique row ID within source
entity_id             String    -- legal entity / company code
posting_date          String    -- accounting date (YYYY-MM-DD)
fiscal_year           String    -- fiscal year
fiscal_period         String    -- period 1-12
main_account          String    -- GL account number
account_name          String    -- account description (empty if N/A)
amount                String    -- signed amount (positive=debit, negative=credit)
debit_amount          String    -- absolute debit
credit_amount         String    -- absolute credit
transaction_currency  String    -- original currency code
currency_amount       String    -- amount in transaction currency
description           String    -- posting text / voucher
journal_number        String    -- journal header reference
posting_type          String    -- posting type code
ledger_account        String    -- full ledger account string
is_credit             String    -- '1' if credit, '0' if debit
dim_cost_center       String    -- dimension: cost center
dim_department        String    -- dimension: department
dim_business_unit     String    -- dimension: business unit
_loaded_at            String    -- extraction timestamp
_raw_id               String    -- source system row identifier
```

### stg_trial_balance

```
erp_source            String
entity_id             String    -- legal entity
main_account          String    -- GL account number
account_name          String    -- account description
fiscal_year           String    -- fiscal year
opening_balance       String    -- period opening balance
debit_amount          String    -- period debits
credit_amount         String    -- period credits
closing_balance       String    -- period closing balance
currency_code         String    -- reporting currency
account_type          String    -- BS/PL classification
_loaded_at            String
_raw_id               String
```

### stg_accounts

```
erp_source            String
account_id            String    -- GL account number
account_name          String    -- description
account_type          String    -- Revenue/Expense/Asset/Liability/Equity
account_category      String    -- sub-classification
debit_credit_default  String    -- default side
chart_of_accounts     String    -- CoA identifier
is_suspended          String    -- '1' if inactive
_loaded_at            String
_raw_id               String
```

### stg_legal_entities

```
erp_source            String
entity_id             String    -- company code / legal entity ID
entity_name           String    -- display name
accounting_currency   String    -- functional currency
reporting_currency    String    -- group reporting currency
party_number          String    -- external party reference
country_region        String    -- ISO country code
_loaded_at            String
_raw_id               String
```

### stg_exchange_rates

```
erp_source            String
from_currency         String    -- source currency
to_currency           String    -- target currency
valid_from            String    -- rate effective date
valid_to              String    -- rate expiry date
exchange_rate         String    -- rate value (scaled for ClickHouse)
rate_type             String    -- rate type (spot, average, etc.)
_loaded_at            String
_raw_id               String
```

### stg_budget_entries

```
erp_source            String
record_id             String    -- budget line ID
entity_id             String    -- legal entity
posting_date          String    -- budget date
main_account          String    -- GL account
amount                String    -- budget amount (accounting currency)
transaction_amount    String    -- amount in transaction currency
transaction_currency  String    -- transaction currency code
budget_model          String    -- budget model / version
budget_status         String    -- Completed / Draft
dim_cost_center       String    -- dimension
dim_department        String    -- dimension
_loaded_at            String
_raw_id               String
```

### stg_fiscal_periods

```
erp_source            String
calendar_id           String    -- fiscal calendar identifier
calendar_name         String    -- display name
fiscal_year           String    -- year name
start_date            String    -- period start
end_date              String    -- period end
_loaded_at            String
_raw_id               String
```

## D365 F&O Adapter Mapping

The existing `stg_d365__*` models are renamed to `stg_d365_fo__*` and their output columns aligned to the canonical schema:

| D365 F&O Column | Canonical Column |
|-----------------|-----------------|
| `RecId` / `SourceKey` | `record_id` |
| `dataAreaId` | `entity_id` |
| `AccountingDate` | `posting_date` |
| `MainAccount` | `main_account` |
| `AccountingCurrencyAmount` | `amount` |
| `TransactionCurrencyCode` | `transaction_currency` |
| `_airbyte_extracted_at` | `_loaded_at` |
| `_airbyte_raw_id` | `_raw_id` |

## File Structure

```
models/staging/
├── d365_fo/                          # D365 F&O adapter
│   ├── _d365_fo__sources.yml         # d365_raw source definition
│   ├── _d365_fo__models.yml          # D365 adapter model docs
│   ├── stg_d365_fo__gl_entries.sql   # GL entries adapter
│   ├── stg_d365_fo__gl_journal_entries.sql
│   ├── stg_d365_fo__trial_balance.sql
│   ├── stg_d365_fo__accounts.sql
│   ├── stg_d365_fo__legal_entities.sql
│   ├── stg_d365_fo__exchange_rates.sql
│   ├── stg_d365_fo__budget_entries.sql
│   ├── stg_d365_fo__fiscal_periods.sql
│   └── (internal helpers: dimensions, categories, etc.)
├── canonical/                         # Canonical interface
│   ├── _canonical__models.yml
│   ├── stg_gl_entries.sql
│   ├── stg_trial_balance.sql
│   ├── stg_accounts.sql
│   ├── stg_legal_entities.sql
│   ├── stg_exchange_rates.sql
│   ├── stg_budget_entries.sql
│   └── stg_fiscal_periods.sql
└── (old stg_d365__*.sql removed)
```

## Testing

- Schema tests in `_canonical__models.yml`: not_null on key columns
- Custom tests: `test_canonical_gl_entries_schema.sql`, `test_erp_source_valid.sql`
- Regression: `dbt build` must pass all existing 26+ tests unchanged

## Success Criteria

1. All bronze models consume from canonical staging (no `stg_d365__` refs)
2. `dbt build` passes with zero regressions
3. Gold model outputs are byte-identical before and after
4. Adding a new ERP requires only: adapter models + `erp_sources` var update
