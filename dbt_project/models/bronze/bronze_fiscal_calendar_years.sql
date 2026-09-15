{{
    config(
        engine='MergeTree()',
        order_by='(fiscal_calendar, start_date)'
    )
}}

{# D365 F&O only. With `d365_fo` not in `erp_sources`, an empty relation with
   the same columns and types (empty_relation, macros/erp_sources.sql). #}

{% if 'd365_fo' in var('erp_sources', []) %}
select
    {{ cast_to_string('FiscalCalendar') }} as fiscal_calendar,
    {{ cast_to_string('Name') }} as year_name,
    {{ cast_to_date('StartDate') }} as start_date,
    {{ cast_to_date('EndDate') }} as end_date,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__fiscal_calendar_years') }}
{% else %}
{{ empty_relation([
    ('fiscal_calendar', 'String'),
    ('year_name', 'String'),
    ('start_date', 'Date'),
    ('end_date', 'Date'),
    ('recid', 'Int64'),
    ('_airbyte_extracted_at', 'DateTime'),
    ('_airbyte_raw_id', 'String'),
]) }}
{% endif %}
