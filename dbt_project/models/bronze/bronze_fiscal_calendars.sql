{{
    config(
        engine='MergeTree()',
        order_by='(calendar_id, start_date)'
    )
}}

select
    {{ cast_to_string('CalendarId') }} as calendar_id,
    {{ cast_to_string("coalesce(Name, '')") }} as calendar_name,
    {{ cast_to_date('StartDate') }} as start_date,
    {{ cast_to_date('EndDate') }} as end_date,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365__fiscal_calendars') }}
