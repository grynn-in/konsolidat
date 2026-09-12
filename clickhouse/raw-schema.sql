-- Raw landing schema for the ERP source tables dbt reads (d365_raw, erpnext_raw).
--
-- Extracted from clickhouse/demo-data.sql, which carried these CREATE TABLEs
-- alongside 34 INSERTs of synthetic Contoso/Alpine data. The demo data is gone;
-- the tables must still exist on a fresh volume, or every staging model — and
-- so the whole dbt build — fails on a missing source. Real rows arrive from the
-- connectors (Airbyte / konsol extractor), or not at all for an entity that
-- submits its trial balance as a file.
--
-- Loaded by docker-compose as /docker-entrypoint-initdb.d/02-raw-schema.sql,
-- which ClickHouse runs ONLY against an empty volume.

CREATE DATABASE IF NOT EXISTS epm_raw;

CREATE TABLE IF NOT EXISTS epm_raw.main_accounts
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `IsSuspended` Nullable(String),
    `MainAccountId` Nullable(String),
    `ChartOfAccounts` Nullable(String),
    `MainAccountType` Nullable(String),
    `DebitCreditDefault` Nullable(String),
    `MainAccountCategory` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.main_account_categories
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Closed` Nullable(String),
    `Description` Nullable(String),
    `ReferenceId` Nullable(String),
    `MainAccountType` Nullable(String),
    `MainAccountCategory` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.legal_entities
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `LegalEntityId` Nullable(String),
    `AddressCountryRegionId` Nullable(String),
    `PartyNumber` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.ledgers
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `LegalEntityId` Nullable(String),
    `ChartOfAccountsId` Nullable(String),
    `ReportingCurrency` Nullable(String),
    `AccountingCurrency` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.fiscal_calendar_years
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `EndDate` Nullable(String),
    `Calendar` Nullable(String),
    `StartDate` Nullable(String),
    `FiscalYear` Nullable(String),
    `Description` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.exchange_rates
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Rate` Nullable(Decimal(38, 9)),
    `EndDate` Nullable(String),
    `StartDate` Nullable(String),
    `ToCurrency` Nullable(String),
    `FromCurrency` Nullable(String),
    `RateTypeName` Nullable(String),
    `ConversionFactor` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.exchange_rate_types
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Name` Nullable(String),
    `Description` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.dimension_attributes
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `DimensionName` Nullable(String),
    `UseValuesFrom` Nullable(String),
    `ReportColumnName` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.financial_dimension_values
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `ActiveTo` Nullable(String),
    `ActiveFrom` Nullable(String),
    `Description` Nullable(String),
    `IsSuspended` Nullable(String),
    `DimensionValue` Nullable(String),
    `FinancialDimension` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.consolidate_account_groups
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `ConsolidationAccountGroup` Nullable(String),
    `ConsolidationAccountGroupName` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.general_journal_entry_bi_entities
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `SourceKey` Nullable(Int64),
    `DocumentDate` Nullable(String),
    `PostingLayer` Nullable(String),
    `JournalNumber` Nullable(String),
    `AccountingDate` Nullable(String),
    `DocumentNumber` Nullable(String),
    `JournalCategory` Nullable(String),
    `SubledgerVoucher` Nullable(String),
    `FiscalCalendarYear` Nullable(Int64),
    `FiscalCalendarPeriod` Nullable(Int64),
    `SubledgerVoucherDataAreaId` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.general_journal_account_entry_bi_entities
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Text` Nullable(String),
    `IsCredit` Nullable(String),
    `SourceKey` Nullable(Int64),
    `PostingType` Nullable(String),
    `LedgerAccount` Nullable(String),
    `AccountingDate` Nullable(String),
    `GeneralJournalEntry` Nullable(Int64),
    `ReportingCurrencyAmount` Nullable(Decimal(38, 9)),
    `TransactionCurrencyCode` Nullable(String),
    `AccountingCurrencyAmount` Nullable(Decimal(38, 9)),
    `LedgerDimensionValuesJson` Nullable(String),
    `TransactionCurrencyAmount` Nullable(Decimal(38, 9))
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.budget_register_entries
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `Date` Nullable(String),
    `Status` Nullable(String),
    `Comment` Nullable(String),
    `BudgetCode` Nullable(String),
    `Department` Nullable(String),
    `dataAreaId` Nullable(String),
    `EntryNumber` Nullable(String),
    `BusinessUnit` Nullable(String),
    `CurrencyCode` Nullable(String),
    `BudgetModelId` Nullable(String),
    `LegalEntityId` Nullable(String),
    `ReasonComment` Nullable(String),
    `DimensionDisplayValue` Nullable(String),
    `AccountingCurrencyAmount` Nullable(Decimal(38, 9)),
    `IncludeInCashFlowForecast` Nullable(String),
    `TransactionCurrencyAmount` Nullable(Decimal(38, 9))
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;

CREATE TABLE IF NOT EXISTS epm_raw.trial_balance_fiscal_year_snapshots
(
    `_airbyte_raw_id` String,
    `_airbyte_extracted_at` DateTime64(3),
    `_airbyte_meta` String,
    `_airbyte_generation_id` UInt32,
    `YearName` Nullable(String),
    `LedgerName` Nullable(String),
    `AmountDebit` Nullable(Decimal(38, 9)),
    `AmountCredit` Nullable(Decimal(38, 9)),
    `EndingBalance` Nullable(Decimal(38, 9)),
    `OpeningBalance` Nullable(Decimal(38, 9)),
    `DimensionValue1` Nullable(String),
    `PeriodStartDate` Nullable(String)
) ENGINE = MergeTree ORDER BY _airbyte_raw_id;
