{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYear(accounting_date)'
    )
}}

select
    {{ cast_to_int64('record_id') }} as recid,
    {{ cast_to_string('entity_id') }} as data_area_id,
    {{ cast_to_date('posting_date') }} as accounting_date,
    {{ cast_to_string('main_account') }} as main_account,
    {{ cast_to_decimal128('amount', 2) }} as accounting_currency_amount,
    {{ cast_to_decimal128('reporting_currency_amount', 2) }} as reporting_currency_amount,
    {{ cast_to_decimal128('currency_amount', 2) }} as transaction_currency_amount,
    {{ cast_to_string('transaction_currency') }} as transaction_currency_code,
    {{ cast_to_string('posting_type') }} as posting_type,
    {{ cast_to_int64('general_journal_entry_recid') }} as general_journal_entry_recid,
    {{ cast_to_string('ledger_account') }} as ledger_account,
    {{ cast_to_string('description') }} as description,
    {{ dim_select_from_source() }},
    {{ cast_to_int8('is_credit') }} as is_credit,
    {{ cast_to_datetime('_loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_gl_entries') }}
