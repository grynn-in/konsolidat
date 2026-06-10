{#
    D365 F&O GL entries adapter.
    Joins GeneralJournalAccountEntryBiEntities with GeneralJournalEntryBiEntities.
    Parses LedgerDimensionValuesJson for MainAccount and dimension values.
    Output matches canonical stg_gl_entries schema.
#}

with entries as (
    select * from {{ source('d365_raw', 'GeneralJournalAccountEntryBiEntities') }}
),

headers as (
    select * from {{ source('d365_raw', 'GeneralJournalEntryBiEntities') }}
),

joined as (
    select
        'd365_fo' as erp_source,
        toString(entries.SourceKey) as record_id,
        upper(coalesce(headers.SubledgerVoucherDataAreaId, '')) as entity_id,
        toString(substring(coalesce(toString(headers.AccountingDate), '1900-01-01'), 1, 10)) as posting_date,
        toString(coalesce(headers.FiscalCalendarYear, 0)) as fiscal_year,
        toString(coalesce(headers.FiscalCalendarPeriod, 0)) as fiscal_period,
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].MAINACCOUNT'
            ),
            splitByChar('-', coalesce(entries.LedgerAccount, ''))[1]
        ) as main_account,
        '' as account_name,
        toString(coalesce(entries.AccountingCurrencyAmount, 0)) as amount,
        toString(
            case
                when coalesce(entries.AccountingCurrencyAmount, 0) >= 0 then coalesce(entries.AccountingCurrencyAmount, 0)
                else 0
            end
        ) as debit_amount,
        toString(
            case
                when coalesce(entries.AccountingCurrencyAmount, 0) < 0 then abs(coalesce(entries.AccountingCurrencyAmount, 0))
                else 0
            end
        ) as credit_amount,
        coalesce(entries.TransactionCurrencyCode, '') as transaction_currency,
        toString(coalesce(entries.TransactionCurrencyAmount, 0)) as currency_amount,
        coalesce(entries.Text, '') as description,
        coalesce(headers.JournalNumber, '') as journal_number,
        coalesce(entries.PostingType, '') as posting_type,
        coalesce(entries.LedgerAccount, '') as ledger_account,
        toString(
            case
                when lower(toString(coalesce(entries.IsCredit, ''))) in ('yes', 'true', '1') then 1
                else 0
            end
        ) as is_credit,
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].COSTCENTER'
            ),
            ''
        ) as dim_cost_center,
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].DEPARTMENT'
            ),
            ''
        ) as dim_department,
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].BUSINESSUNIT'
            ),
            ''
        ) as dim_business_unit,
        toString(entries._airbyte_extracted_at) as _loaded_at,
        toString(entries._airbyte_raw_id) as _raw_id,
        -- Keep D365-specific fields needed by bronze (backward compat)
        toString(coalesce(entries.ReportingCurrencyAmount, 0)) as reporting_currency_amount,
        toString(entries.GeneralJournalEntry) as general_journal_entry_recid
    from entries
    left join headers
        on entries.GeneralJournalEntry = headers.SourceKey
)

select * from joined
