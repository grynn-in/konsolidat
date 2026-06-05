{{
    config(
        engine='MergeTree()',
        order_by='(consolidation_account_group)'
    )
}}

select
    toString(ConsolidationAccountGroup) as consolidation_account_group,
    toString(coalesce(Name, '')) as group_name,
    toString(coalesce(Description, '')) as description,
    toInt64(RecId) as recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'consolidation_account_groups') }}
