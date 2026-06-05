{{
    config(
        engine='MergeTree()',
        order_by='(recid)'
    )
}}

select
    toInt64(RecId) as recid,
    toString(AccountCategory) as account_category,
    toString(Description) as description,
    toString(AccountType) as account_type,
    toString(coalesce(IsClosed, '')) as is_closed,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'main_account_categories') }}
