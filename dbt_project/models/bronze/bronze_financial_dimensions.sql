{{
    config(
        engine='MergeTree()',
        order_by='(dimension_name)'
    )
}}

select
    {{ cast_to_string('DimensionName') }} as dimension_name,
    {{ cast_to_string("coalesce(Description, '')") }} as description,
    {{ cast_to_string("coalesce(BackingEntityType, '')") }} as backing_entity_type,
    {{ cast_to_int8('coalesce(IsActive, 1)') }} as is_active,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__financial_dimensions') }}
