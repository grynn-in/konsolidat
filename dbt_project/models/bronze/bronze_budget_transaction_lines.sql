{{
    config(
        engine='MergeTree()',
        order_by='(budget_register_entry_recid, recid)',
        partition_by='toYYYYMM(transaction_date)'
    )
}}

select
    {{ cast_to_int64('record_id') }} as recid,
    {{ cast_to_int64('budget_register_entry_recid') }} as budget_register_entry_recid,
    {{ cast_to_date('posting_date') }} as transaction_date,
    {{ cast_to_string('main_account') }} as main_account,
    {{ cast_to_decimal128('amount', 2) }} as accounting_currency_amount,
    {{ cast_to_decimal128('transaction_amount', 2) }} as transaction_currency_amount,
    {{ cast_to_string("coalesce(transaction_currency, '')") }} as transaction_currency,
    {{ dim_select_from_source(dims=get_budget_dimensions()) }},
    {{ cast_to_int8('coalesce(include_in_cash_flow, 0)') }} as include_in_cash_flow,
    {{ cast_to_datetime('_loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_budget_entries') }}
