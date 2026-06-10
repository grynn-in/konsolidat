{{
    config(
        engine='MergeTree()',
        order_by='(fiscal_calendar, start_date)'
    )
}}

select
    {{ cast_to_string('FiscalCalendar') }} as fiscal_calendar,
    {{ cast_to_string('Name') }} as year_name,
    {{ cast_to_date('StartDate') }} as start_date,
    {{ cast_to_date('EndDate') }} as end_date,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__fiscal_calendar_years') }}
