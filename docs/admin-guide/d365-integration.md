# D365 F&O Integration

How Open EPM extracts data from Dynamics 365 Finance & Operations via Airbyte and OData.

## Azure AD App Registration

### Step-by-Step

1. Go to [Azure Portal → App Registrations](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)
2. Click **New registration**
   - Name: `Open EPM Airbyte`
   - Supported account types: Single tenant
   - Redirect URI: Leave blank
3. Note the **Application (client) ID** and **Directory (tenant) ID**
4. Go to **Certificates & secrets** → **New client secret**
   - Description: `Open EPM production`
   - Expiry: 24 months
   - Copy the secret value immediately (shown only once)
5. Go to **API permissions** → **Add a permission**
   - Select **Dynamics 365 Finance and Operations**
   - Choose **Delegated permissions** → `Ax.FullAccess`
   - Click **Grant admin consent**

### Required Values

| Value | Where to Find | Used By |
|-------|--------------|---------|
| Tenant ID | App registration → Overview | Airbyte source config |
| Client ID | App registration → Overview | Airbyte source config |
| Client Secret | Certificates & secrets | Airbyte source config |
| Environment URL | D365 → System administration | Airbyte source config |

The environment URL typically looks like: `https://yourorg.operations.dynamics.com`

## OData Entities

Open EPM extracts 15 D365 OData entities. All use `cross_company=true` to pull data across all legal entities in a single request.

### General Ledger

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `GeneralJournalAccountEntries` | GL line items (debits/credits) | `RecId`, `DataAreaId`, `MainAccount`, `DebitAmount`, `CreditAmount` |
| `GeneralJournalEntries` | Journal headers | `RecId`, `JournalNumber`, `AccountingDate` |

### Chart of Accounts

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `MainAccounts` | Account master | `MainAccountId`, `Name`, `Type` |
| `MainAccountCategories` | Account category mapping | `RecId`, `AccountCategory` |

### Organization

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `LegalEntities` | Company master | `DataArea`, `Name`, `AccountingCurrency` |

### Fiscal Calendar

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `FiscalCalendars` | Calendar definitions | `CalendarId`, `Description` |
| `FiscalCalendarYears` | Year definitions | `FiscalCalendarId`, `StartDate`, `EndDate` |

### Financial Dimensions

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `FinancialDimensions` | Dimension definitions | `DimensionName` |
| `FinancialDimensionValues` | Dimension value master | `DimensionName`, `DimensionValue`, `IsActive` |

### Exchange Rates

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `ExchangeRateCurrencyPairs` | Rate data | `FromCurrency`, `ToCurrency`, `ExchangeRate`, `ValidFrom` |
| `ExchangeRateTypes` | Rate type definitions | `Name`, `Description` |

### Budget

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `BudgetRegisterEntries` | Budget register headers | `EntryNumber`, `BudgetModelId`, `Status` |
| `BudgetTransactionLines` | Budget line items | `MainAccount`, `Amount`, `Date` |

### Consolidation

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `ConsolidationAccountGroups` | Group mapping | `ConsolidationAccountGroup` |

### Trial Balance Snapshot

| OData Entity | Purpose | Key Fields |
|-------------|---------|------------|
| `LedgerTrialBalanceFiscalYearSnapshotDataEntity` | Pre-built TB snapshot | `MainAccount`, `DebitAmount`, `CreditAmount`, `FiscalYear` |

## Airbyte Configuration

### Source: Dynamics 365 Finance & Operations

| Setting | Value |
|---------|-------|
| Source type | Dynamics 365 F&O (OData) |
| Tenant ID | From Azure AD app registration |
| Client ID | From Azure AD app registration |
| Client Secret | From Azure AD app registration |
| Environment URL | `https://yourorg.operations.dynamics.com` |

### Destination: ClickHouse

| Setting | Value |
|---------|-------|
| Host | `host.docker.internal` (Docker) or ClickHouse hostname |
| Port | `8123` |
| Database | `epm_bronze` |
| User | `default` (or dedicated write user) |
| Password | From `.env` |

### Stream Configuration

Enable all 15 entities listed above. For each stream:
- **Sync mode**: Full Refresh (overwrite) for reference data; Incremental for GL entries (if supported)
- **Cursor field**: `RecId` or `ModifiedDateTime` for incremental
- **Primary key**: `RecId` for most entities; `DataArea` for `LegalEntities`

### Cross-Company Setting

All entity requests include `cross_company=true` in the OData query to retrieve data across all legal entities in the D365 instance.

## Entity-to-Model Mapping

How D365 entities flow through the dbt layers:

| OData Entity | → Bronze | → Silver | → Gold |
|-------------|----------|----------|--------|
| GeneralJournalAccountEntries | `bronze_general_journal_account_entries` | `silver_gl_entries` | `gold_trial_balance` |
| GeneralJournalEntries | `bronze_general_journal_entries` | `silver_gl_entries` (joined) | — |
| MainAccounts | `bronze_main_accounts` | `silver_main_accounts` | — |
| MainAccountCategories | `bronze_main_account_categories` | `silver_main_accounts` (joined) | — |
| LegalEntities | `bronze_legal_entities` | `silver_legal_entities` | — |
| FiscalCalendars | `bronze_fiscal_calendars` | `silver_fiscal_periods` | `gold_period_hierarchy` |
| FiscalCalendarYears | `bronze_fiscal_calendar_years` | `silver_fiscal_periods` (joined) | — |
| ExchangeRateCurrencyPairs | `bronze_exchange_rate_currency_pairs` | `silver_exchange_rates` | `gold_consolidated_trial_balance` |
| BudgetRegisterEntries | `bronze_budget_register_entries` | `silver_budget_entries` | `gold_spread_budget` |
| BudgetTransactionLines | `bronze_budget_transaction_lines` | `silver_budget_entries` (joined) | — |

## Sync Schedule

| Approach | Frequency | Best For |
|----------|-----------|----------|
| Manual (via task pane or API) | On-demand | Development, ad-hoc |
| Airbyte scheduler | Daily at off-peak hours | Standard production |
| Event-driven | On D365 posting | Real-time requirements |

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` from D365 | Expired client secret or missing permissions | Rotate secret, verify `Ax.FullAccess` |
| Empty sync results | `cross_company=true` not set | Check stream settings |
| Missing entities | Entity not enabled in D365 | Contact D365 admin to expose the data entity |
| Timeout on large syncs | Too many records in one batch | Increase Airbyte timeout, use incremental sync |
| Rate limiting (429) | D365 throttling | Reduce batch size, add retry logic |

## Next Steps

- [Setup Guide](../getting-started/setup-guide.md) — Full installation including Airbyte
- [Configuration Reference](../getting-started/configuration-reference.md) — EPM Settings fields
- [Bronze Models](../data-dictionary/bronze-models.md) — What the raw data looks like
