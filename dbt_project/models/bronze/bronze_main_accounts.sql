{{
    config(
        engine='MergeTree()',
        order_by='(main_account_id)'
    )
}}

select
    {{ cast_to_string('account_id') }} as main_account_id,
    {{ cast_to_string('account_name') }} as account_name,
    {{ cast_to_string('account_type') }} as account_type,
    {{ cast_to_string("coalesce(account_category, '')") }} as main_account_category,
    {{ cast_to_string("coalesce(debit_credit_default, '')") }} as debit_credit_default,
    {{ cast_to_string("coalesce(chart_of_accounts, '')") }} as chart_of_accounts,
    {{ cast_to_int8('coalesce(is_suspended, 0)') }} as is_suspended,
    {{ cast_to_datetime('_loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_accounts') }}
