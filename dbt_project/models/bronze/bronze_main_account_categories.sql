{{
    config(
        engine='MergeTree()',
        order_by='(recid)'
    )
}}

select
    reinterpretAsInt64(cityHash64(assumeNotNull(RecId))) as recid,
    {{ cast_to_string('AccountCategory') }} as account_category,
    {{ cast_to_string('Description') }} as description,
    {{ cast_to_string('AccountType') }} as account_type,
    {{ cast_to_string("coalesce(IsClosed, '')") }} as is_closed,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__main_account_categories') }}
