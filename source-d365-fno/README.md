# Source D365 Finance & Operations

Airbyte source connector for Microsoft Dynamics 365 Finance & Operations.

Extracts 14 OData entities from D365 F&O with raw field passthrough. Field renaming and transforms are handled by downstream dbt staging models.

## Streams

| Stream | OData Entity | Sync Mode |
|--------|-------------|-----------|
| general_journal_account_entry_bi_entities | GeneralJournalAccountEntryBiEntities | Incremental |
| general_journal_entry_bi_entities | GeneralJournalEntryBiEntities | Incremental |
| main_accounts | MainAccounts | Full Refresh |
| main_account_categories | MainAccountCategories | Full Refresh |
| legal_entities | LegalEntities | Full Refresh |
| ledgers | Ledgers | Full Refresh |
| fiscal_calendar_years | FiscalCalendarYears | Full Refresh |
| dimension_attributes | DimensionAttributes | Full Refresh |
| financial_dimension_values | FinancialDimensionValues | Full Refresh |
| exchange_rates | ExchangeRates | Incremental |
| exchange_rate_types | ExchangeRateTypes | Full Refresh |
| budget_register_entries | BudgetRegisterEntries | Incremental |
| consolidate_account_groups | ConsolidateAccountGroups | Full Refresh |
| trial_balance_fiscal_year_snapshots | TrialBalanceFiscalYearSnapshots | Full Refresh |

## Configuration

| Parameter | Required | Description |
|-----------|----------|-------------|
| tenant_id | Yes | Azure AD tenant ID |
| client_id | Yes | Azure AD application client ID |
| client_secret | Yes | Azure AD client secret |
| environment_url | Yes | D365 F&O base URL |
| page_size | No | Records per page (default: 5000) |

## Development

```bash
pip install -e ".[dev]"
pytest unit_tests/
```
