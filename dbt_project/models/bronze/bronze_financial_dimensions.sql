{{
    config(
        engine='MergeTree()',
        order_by='(dimension_name)'
    )
}}

select
    toString(DimensionName) as dimension_name,
    toString(coalesce(Description, '')) as description,
    toString(coalesce(BackingEntityType, '')) as backing_entity_type,
    toInt8(coalesce(IsActive, 1)) as is_active,
    toInt64(RecId) as recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'financial_dimensions') }}
