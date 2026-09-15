{{
    config(
        engine='MergeTree()',
        order_by='(recid)'
    )
}}

{# D365 F&O only. With `d365_fo` not in `erp_sources`, an empty relation with
   the same columns and types (empty_relation, macros/erp_sources.sql). #}

{% if 'd365_fo' in var('erp_sources', []) %}
select
    reinterpretAsInt64(cityHash64(assumeNotNull(RecId))) as recid,
    {{ cast_to_string('AccountCategory') }} as account_category,
    {{ cast_to_string('Description') }} as description,
    {{ cast_to_string('AccountType') }} as account_type,
    {{ cast_to_string("coalesce(IsClosed, '')") }} as is_closed,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__main_account_categories') }}
{% else %}
{{ empty_relation([
    ('recid', 'Int64'),
    ('account_category', 'String'),
    ('description', 'String'),
    ('account_type', 'String'),
    ('is_closed', 'String'),
    ('_airbyte_extracted_at', 'DateTime'),
    ('_airbyte_raw_id', 'String'),
]) }}
{% endif %}
