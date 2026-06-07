{#
    Fiscal Calendar Years staging model.
    Maps Calendar → FiscalCalendar, generates synthetic RecId.
#}

select
    coalesce(Calendar, '') as FiscalCalendar,
    coalesce(FiscalYear, Description, '') as Name,
    toString(substring(coalesce(toString(StartDate), '1900-01-01'), 1, 10)) as StartDate,
    toString(substring(coalesce(toString(EndDate), '2099-12-31'), 1, 10)) as EndDate,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'FiscalCalendarYears') }}
