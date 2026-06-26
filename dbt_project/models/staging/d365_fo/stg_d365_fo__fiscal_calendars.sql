{#
    Fiscal Calendars staging model.
    Derives one row per distinct Calendar from FiscalCalendarYears,
    with min/max date bounds.
#}

select
    Calendar as CalendarId,
    any(coalesce(Description, Calendar)) as Name,
    min(toDate(substring(coalesce(toString(StartDate), '1900-01-01'), 1, 10))) as StartDate,
    max(toDate(substring(coalesce(toString(EndDate), '2099-12-31'), 1, 10))) as EndDate,
    rowNumberInAllBlocks() as RecId,
    max(_airbyte_extracted_at) as _airbyte_extracted_at,
    any(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('d365_raw', 'fiscal_calendar_years') }}
group by Calendar
