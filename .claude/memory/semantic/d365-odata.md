# D365 OData Entities — Lessons Learned

## Wrong entity (DO NOT USE)
- `GeneralLedgerActivities` — aggregate cube, uses RecIds everywhere, no dataAreaId, no readable account numbers.

## Actual OData entity names (verified on bizapps2 sandbox)
Standard D365 docs say `GeneralJournalAccountEntries` etc. but those return 404.
The REAL entity names available via `/data/`:

| # | OData Entity (real name) | Expected count | Notes |
|---|---|---|---|
| 1 | `GeneralJournalAccountEntryBiEntities` | 511K | BI entity — no dataAreaId/AccountingDate (get from header join); MainAccount is RecId, parse from LedgerAccount or LedgerDimensionValuesJson |
| 2 | `GeneralJournalEntryBiEntities` | 93K | BI entity — has SubledgerVoucherDataAreaId, AccountingDate, JournalNumber; SourceKey = RecId |
| 3 | `MainAccounts` | 9.5K | Field: `MainAccountType` (not `Type`), `IsSuspended` is string Yes/No |
| 4 | `MainAccountCategories` | 277 | Field: `MainAccountCategory` (not `AccountCategory`), `ReferenceId` (not `RecId`), `Closed` (not `IsClosed`) |
| 5 | `LegalEntities` | 144 | Field: `LegalEntityId` (not `dataArea`). NO AccountingCurrency — must join with `Ledgers` entity |
| 6 | `FiscalCalendarYears` | 237 | Field: `Calendar` (not `FiscalCalendar`), `FiscalYear` as string |
| 7 | `DimensionAttributes` | 101 | Replaces `FinancialDimensions` (404). Has `DimensionName`, `UseValuesFrom` |
| 8 | `FinancialDimensionValues` | 11K | Field: `FinancialDimension` (not `FinancialDimensionName`), `IsSuspended` string |
| 9 | `ExchangeRates` | 18.5K | NOT `ExchangeRateCurrencyPairs` (that only has pair defs, no rates). Fields: `FromCurrency`, `ToCurrency`, `Rate`, `StartDate`, `EndDate`, `RateTypeName`, `ConversionFactor` |
| 10 | `ExchangeRateTypes` | 28 | Fields: `Name`, `Description` only |
| 11 | `BudgetRegisterEntries` | 14K | Combined header+line entity. Has `EntryNumber`, `DimensionDisplayValue`, `AccountingCurrencyAmount`. Split into 2 tables in sync script |
| 12 | `ConsolidateAccountGroups` | 100 | NOT `ConsolidationAccountGroups`. Contains account-to-group mappings, deduplicate for groups |
| 13 | `TrialBalanceFiscalYearSnapshots` | 15K | Field: `AmountDebit`/`AmountCredit`/`EndingBalance` (not Debit/CreditAmount/ClosingBalance). `LedgerName` = company, `DimensionValue1` = main account |
| 14 | `Ledgers` | 144 | Needed for AccountingCurrency/ReportingCurrency per company |

## Key transformation gotchas
- **BOM**: `$count` responses have UTF-8 BOM (`\xef\xbb\xbf`). Use `decode('utf-8-sig')`
- **FX rates**: `ExchangeRates.Rate` is raw rate (e.g., 0.7435). dbt divides by 100. Store rate×100 when ConversionFactor="One"
- **GL join**: Account entries have no date/company — must join to `GeneralJournalEntryBiEntities` via `GeneralJournalEntry` = `SourceKey`
- **Dimensions JSON**: `LedgerDimensionValuesJson` = `[{"BUSINESSUNIT":"001","MAINACCOUNT":"140200"}]`
- **Yes/No strings**: Many boolean fields are strings "Yes"/"No", not 0/1

## Airbyte
- No native D365 F&O connector in Airbyte catalogue
- Microsoft Dataverse connector exists but D365 F&O OData is different
- Built custom sync script: `scripts/sync_d365_odata.py`
