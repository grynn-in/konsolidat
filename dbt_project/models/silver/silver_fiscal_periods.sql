{{
    config(
        engine='MergeTree()',
        order_by='(calendar_id, start_date)'
    )
}}

select
    fc.calendar_id,
    fc.calendar_name,
    fc.start_date as period_start_date,
    fc.end_date as period_end_date,
    fcy.year_name as fiscal_year_name,
    fcy.start_date as year_start_date,
    fcy.end_date as year_end_date,
    toYear(fc.start_date) as calendar_year,
    toMonth(fc.start_date) as calendar_month,
    fc.recid as period_recid,
    fcy.recid as year_recid
from {{ ref('bronze_fiscal_calendars') }} as fc
left join {{ ref('bronze_fiscal_calendar_years') }} as fcy
    on fc.calendar_id = fcy.fiscal_calendar
    and fc.start_date >= fcy.start_date
    and fc.start_date <= fcy.end_date
