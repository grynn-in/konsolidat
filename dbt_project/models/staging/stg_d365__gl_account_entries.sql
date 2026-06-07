{#
    GL Account Entries staging model.
    Joins GeneralJournalAccountEntryBiEntities with GeneralJournalEntryBiEntities
    to get dataAreaId and AccountingDate from the header.
    Parses LedgerDimensionValuesJson for MainAccount and dimension values.
    Outputs schema matching epm_bronze.general_journal_account_entries.
#}

with entries as (
    select * from {{ source('d365_raw', 'GeneralJournalAccountEntryBiEntities') }}
),

headers as (
    select * from {{ source('d365_raw', 'GeneralJournalEntryBiEntities') }}
),

joined as (
    select
        entries.SourceKey as RecId,
        upper(coalesce(headers.SubledgerVoucherDataAreaId, '')) as dataAreaId,
        toString(substring(coalesce(toString(headers.AccountingDate), '1900-01-01'), 1, 10)) as AccountingDate,
        -- Parse MainAccount from LedgerDimensionValuesJson, fallback to LedgerAccount
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].MAINACCOUNT'
            ),
            splitByChar('-', coalesce(entries.LedgerAccount, ''))[1]
        ) as MainAccount,
        entries.AccountingCurrencyAmount,
        coalesce(entries.ReportingCurrencyAmount, 0) as ReportingCurrencyAmount,
        coalesce(entries.TransactionCurrencyAmount, 0) as TransactionCurrencyAmount,
        coalesce(entries.TransactionCurrencyCode, '') as TransactionCurrencyCode,
        coalesce(entries.PostingType, '') as PostingType,
        entries.GeneralJournalEntry,
        coalesce(entries.LedgerAccount, '') as LedgerAccount,
        coalesce(entries.Text, '') as Text,
        -- Parse dimension values from JSON
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].COSTCENTER'
            ),
            ''
        ) as CostCenter,
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].DEPARTMENT'
            ),
            ''
        ) as Department,
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].BUSINESSUNIT'
            ),
            ''
        ) as BusinessUnit,
        case
            when lower(toString(coalesce(entries.IsCredit, ''))) in ('yes', 'true', '1') then 1
            else 0
        end as IsCredit,
        entries._airbyte_extracted_at,
        entries._airbyte_raw_id
    from entries
    left join headers
        on entries.GeneralJournalEntry = headers.SourceKey
)

select * from joined
