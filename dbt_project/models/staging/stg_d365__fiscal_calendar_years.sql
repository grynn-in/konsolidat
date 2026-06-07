{#
    Fiscal Calendar Years staging model.
    Maps Calendar → FiscalCalendar, generates synthetic RecId.
#}

select
    coalesce(Calendar, '') as FiscalCalendar,
    coalesce(FiscalYear, Description, '') as Name,
    StartDate,
    EndDate,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'fiscal_calendar_years') }}
