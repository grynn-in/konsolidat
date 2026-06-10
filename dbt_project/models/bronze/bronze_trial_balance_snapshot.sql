{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, main_account)',
        partition_by='fiscal_year'
    )
}}

select
    {{ cast_to_string('entity_id') }} as data_area_id,
    {{ cast_to_string('main_account') }} as main_account,
    {{ cast_to_string("coalesce(account_name, '')") }} as main_account_name,
    {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
    {{ cast_to_decimal128('coalesce(opening_balance, 0)', 2) }} as opening_balance,
    {{ cast_to_decimal128('coalesce(debit_amount, 0)', 2) }} as debit_amount,
    {{ cast_to_decimal128('coalesce(credit_amount, 0)', 2) }} as credit_amount,
    {{ cast_to_decimal128('coalesce(closing_balance, 0)', 2) }} as closing_balance,
    {{ cast_to_string("coalesce(currency_code, '')") }} as currency_code,
    {{ cast_to_string("coalesce(account_type, '')") }} as account_type,
    {{ cast_to_datetime('_loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_trial_balance') }}
