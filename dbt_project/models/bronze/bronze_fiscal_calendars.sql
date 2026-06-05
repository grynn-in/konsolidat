{{
    config(
        engine='MergeTree()',
        order_by='(calendar_id, start_date)'
    )
}}

select
    toString(CalendarId) as calendar_id,
    toString(coalesce(Name, '')) as calendar_name,
    toDate(StartDate) as start_date,
    toDate(EndDate) as end_date,
    toInt64(RecId) as recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'fiscal_calendars') }}
