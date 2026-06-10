{#
    D365 F&O fiscal periods adapter.
    Combines fiscal calendar years into canonical stg_fiscal_periods schema.
#}

select
    'd365_fo' as erp_source,
    coalesce(Calendar, '') as calendar_id,
    coalesce(Description, Calendar, '') as calendar_name,
    coalesce(FiscalYear, Description, '') as fiscal_year,
    toString(substring(coalesce(toString(StartDate), '1900-01-01'), 1, 10)) as start_date,
    toString(substring(coalesce(toString(EndDate), '2099-12-31'), 1, 10)) as end_date,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('d365_raw', 'FiscalCalendarYears') }}
