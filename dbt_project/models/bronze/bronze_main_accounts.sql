{{
    config(
        engine='MergeTree()',
        order_by='(main_account_id)'
    )
}}

select
    toString(MainAccountId) as main_account_id,
    toString(Name) as account_name,
    toString(Type) as account_type,
    toString(coalesce(MainAccountCategory, '')) as main_account_category,
    toString(coalesce(DebitCreditDefault, '')) as debit_credit_default,
    toString(coalesce(ChartOfAccounts, '')) as chart_of_accounts,
    toInt8(coalesce(IsSuspended, 0)) as is_suspended,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'main_accounts') }}
