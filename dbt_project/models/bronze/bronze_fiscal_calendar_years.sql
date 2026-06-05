{{
    config(
        engine='MergeTree()',
        order_by='(fiscal_calendar, start_date)'
    )
}}

select
    toString(FiscalCalendar) as fiscal_calendar,
    toString(Name) as year_name,
    toDate(StartDate) as start_date,
    toDate(EndDate) as end_date,
    toInt64(RecId) as recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'fiscal_calendar_years') }}
