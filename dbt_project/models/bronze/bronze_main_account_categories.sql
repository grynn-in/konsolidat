{{
    config(
        engine='MergeTree()',
        order_by='(recid)'
    )
}}

select
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_string('AccountCategory') }} as account_category,
    {{ cast_to_string('Description') }} as description,
    {{ cast_to_string('AccountType') }} as account_type,
    {{ cast_to_string("coalesce(IsClosed, '')") }} as is_closed,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ source('airbyte_raw', 'main_account_categories') }}
