{{
    config(
        engine='MergeTree()',
        order_by='(budget_register_entry_recid, recid)',
        partition_by='toYYYYMM(transaction_date)'
    )
}}

select
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_int64('BudgetRegisterEntry') }} as budget_register_entry_recid,
    {{ cast_to_date('Date') }} as transaction_date,
    {{ cast_to_string('MainAccount') }} as main_account,
    {{ cast_to_decimal128('AccountingCurrencyAmount', 2) }} as accounting_currency_amount,
    {{ cast_to_decimal128('TransactionCurrencyAmount', 2) }} as transaction_currency_amount,
    {{ cast_to_string("coalesce(TransactionCurrency, '')") }} as transaction_currency,
    {{ dim_select_from_source(dims=get_budget_dimensions()) }},
    {{ cast_to_int8('coalesce(IncludeInCashFlowForecast, 0)') }} as include_in_cash_flow,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365__budget_transaction_lines') }}
