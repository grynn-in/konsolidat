{{
    config(
        engine='MergeTree()',
        order_by='(main_account_id)'
    )
}}

select
    {{ cast_to_string('MainAccountId') }} as main_account_id,
    {{ cast_to_string('Name') }} as account_name,
    {{ cast_to_string('Type') }} as account_type,
    {{ cast_to_string("coalesce(MainAccountCategory, '')") }} as main_account_category,
    {{ cast_to_string("coalesce(DebitCreditDefault, '')") }} as debit_credit_default,
    {{ cast_to_string("coalesce(ChartOfAccounts, '')") }} as chart_of_accounts,
    {{ cast_to_int8('coalesce(IsSuspended, 0)') }} as is_suspended,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365__main_accounts') }}
