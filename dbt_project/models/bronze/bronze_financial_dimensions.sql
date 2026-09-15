{{
    config(
        engine='MergeTree()',
        order_by='(dimension_name)'
    )
}}

{# D365 F&O only. With `d365_fo` not in `erp_sources`, an empty relation with
   the same columns and types (empty_relation, macros/erp_sources.sql). #}

{% if 'd365_fo' in var('erp_sources', []) %}
select
    {{ cast_to_string('DimensionName') }} as dimension_name,
    {{ cast_to_string("coalesce(Description, '')") }} as description,
    {{ cast_to_string("coalesce(BackingEntityType, '')") }} as backing_entity_type,
    {{ cast_to_int8('coalesce(IsActive, 1)') }} as is_active,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__financial_dimensions') }}
{% else %}
{{ empty_relation([
    ('dimension_name', 'String'),
    ('description', 'String'),
    ('backing_entity_type', 'String'),
    ('is_active', 'Int8'),
    ('recid', 'Int64'),
    ('_airbyte_extracted_at', 'DateTime'),
    ('_airbyte_raw_id', 'String'),
]) }}
{% endif %}
