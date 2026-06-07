{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYear(accounting_date)'
    )
}}

select
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_string('dataAreaId') }} as data_area_id,
    {{ cast_to_date('AccountingDate') }} as accounting_date,
    {{ cast_to_string('MainAccount') }} as main_account,
    {{ cast_to_decimal128('AccountingCurrencyAmount', 2) }} as accounting_currency_amount,
    {{ cast_to_decimal128('ReportingCurrencyAmount', 2) }} as reporting_currency_amount,
    {{ cast_to_decimal128('TransactionCurrencyAmount', 2) }} as transaction_currency_amount,
    {{ cast_to_string('TransactionCurrencyCode') }} as transaction_currency_code,
    {{ cast_to_string('PostingType') }} as posting_type,
    {{ cast_to_int64('GeneralJournalEntry') }} as general_journal_entry_recid,
    {{ cast_to_string('LedgerAccount') }} as ledger_account,
    {{ cast_to_string('Text') }} as description,
    {{ dim_select_from_source() }},
    {{ cast_to_int8('IsCredit') }} as is_credit,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365__gl_account_entries') }}
