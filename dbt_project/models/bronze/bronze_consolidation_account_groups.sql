{{
    config(
        engine='MergeTree()',
        order_by='(consolidation_account_group)'
    )
}}

{# D365 F&O only. With `d365_fo` not in `erp_sources`, an empty relation with
   the same columns and types (empty_relation, macros/erp_sources.sql). #}

{% if 'd365_fo' in var('erp_sources', []) %}
select
    {{ cast_to_string('ConsolidationAccountGroup') }} as consolidation_account_group,
    {{ cast_to_string("coalesce(Name, '')") }} as group_name,
    {{ cast_to_string("coalesce(Description, '')") }} as description,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__consolidation_groups') }}
{% else %}
{{ empty_relation([
    ('consolidation_account_group', 'String'),
    ('group_name', 'String'),
    ('description', 'String'),
    ('recid', 'Int64'),
    ('_airbyte_extracted_at', 'DateTime'),
    ('_airbyte_raw_id', 'String'),
]) }}
{% endif %}
