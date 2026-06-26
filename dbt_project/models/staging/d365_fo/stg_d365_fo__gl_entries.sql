{#
    D365 F&O GL entries adapter.
    Joins GeneralJournalAccountEntryBiEntities with GeneralJournalEntryBiEntities.
    Parses LedgerDimensionValuesJson for MainAccount and dimension values.
    Output matches canonical stg_gl_entries schema.

    NOTE: D365 stores both debits and credits as the raw AccountingCurrencyAmount
    with an IsCredit flag. We pass the raw amount through — bronze/silver handle
    debit/credit splitting using is_credit.
#}

with entries as (
    select * from {{ source('d365_raw', 'general_journal_account_entry_bi_entities') }}
),

headers as (
    select * from {{ source('d365_raw', 'general_journal_entry_bi_entities') }}
),

joined as (
    select
        -- Canonical columns
        'd365_fo' as erp_source,
        entries.SourceKey as record_id,
        upper(coalesce(headers.SubledgerVoucherDataAreaId, '')) as entity_id,
        toString(substring(coalesce(toString(headers.AccountingDate), '1900-01-01'), 1, 10)) as posting_date,
        coalesce(headers.FiscalCalendarYear, 0) as fiscal_year,
        coalesce(headers.FiscalCalendarPeriod, 0) as fiscal_period,
        coalesce(
            JSON_VALUE(
                replaceAll(coalesce(entries.LedgerDimensionValuesJson, '[]'), '''', '"'),
                '$[0].MAINACCOUNT'
            ),
            splitByChar('-', coalesce(entries.LedgerAccount, ''))[1]
        ) as main_account,
        '' as account_name,
        entries.AccountingCurrencyAmount as amount,
        coalesce(entries.ReportingCurrencyAmount, 0) as reporting_currency_amount,
        coalesce(entries.TransactionCurrencyAmount, 0) as transaction_currency_amount,
        coalesce(entries.TransactionCurrencyCode, '') as transaction_currency,
        coalesce(entries.Text, '') as description,
        coalesce(headers.JournalNumber, '') as journal_number,
        coalesce(entries.PostingType, '') as posting_type,
        coalesce(entries.LedgerAccount, '') as ledger_account,
        case
            when lower(toString(coalesce(entries.IsCredit, ''))) in ('yes', 'true', '1') then 1
            else 0
        end as is_credit,
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
        ) as dim_business_unit_raw,
        entries._airbyte_extracted_at as _loaded_at,
        entries._airbyte_raw_id as _raw_id,
        entries.GeneralJournalEntry as general_journal_entry_recid
    from entries
    left join headers
        on entries.GeneralJournalEntry = headers.SourceKey
),

{# Demo: AMUS posts all rows as SERVICES in raw D365 JSON. Split by account
   so MGMT_DEMO hierarchy rollups (CORP / OPS / BU_ROOT) are testable locally. #}
with_demo_bu as (
    select
        * except (dim_business_unit_raw),
        case
            when entity_id = 'AMUS' and main_account in ('5010', '5030') then 'MANUFACTURING'
            when entity_id = 'AMUS' and main_account in ('6010', '6020', '6030', '6040', '6050', '6060') then 'CORP'
            else dim_business_unit_raw
        end as dim_business_unit
    from joined
)

select * from with_demo_bu
