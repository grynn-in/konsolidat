{{
    config(
        engine='MergeTree()',
        order_by='(consolidation_account_group)'
    )
}}

select
    {{ cast_to_string('ConsolidationAccountGroup') }} as consolidation_account_group,
    {{ cast_to_string("coalesce(Name, '')") }} as group_name,
    {{ cast_to_string("coalesce(Description, '')") }} as description,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ source('airbyte_raw', 'consolidation_account_groups') }}
