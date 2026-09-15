{{
    config(
        engine='MergeTree()',
        order_by='(dimension_name, dimension_value)'
    )
}}

{# D365 F&O only. With `d365_fo` not in `erp_sources`, an empty relation with
   the same columns and types (empty_relation, macros/erp_sources.sql). #}

{% if 'd365_fo' in var('erp_sources', []) %}
select
    {{ cast_to_string('FinancialDimensionName') }} as dimension_name,
    {{ cast_to_string('DimensionValue') }} as dimension_value,
    {{ cast_to_string("coalesce(Description, '')") }} as description,
    {{ cast_to_int8('coalesce(IsSuspended, 0)') }} as is_suspended,
    {{ cast_to_date("coalesce(ActiveFrom, '1900-01-01')") }} as active_from,
    {{ cast_to_date("coalesce(ActiveTo, '2099-12-31')") }} as active_to,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__financial_dimension_values') }}
{% else %}
{{ empty_relation([
    ('dimension_name', 'String'),
    ('dimension_value', 'String'),
    ('description', 'String'),
    ('is_suspended', 'Int8'),
    ('active_from', 'Date'),
    ('active_to', 'Date'),
    ('recid', 'Int64'),
    ('_airbyte_extracted_at', 'DateTime'),
    ('_airbyte_raw_id', 'String'),
]) }}
{% endif %}
