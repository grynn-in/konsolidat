{{
    config(
        engine='MergeTree()',
        order_by='(calendar_id, period_start_date)'
    )
}}

{# Generate monthly fiscal periods from fiscal calendar year ranges.
   bronze_fiscal_calendars only has the calendar definition (1 row per calendar).
   bronze_fiscal_calendar_years has proper year ranges (e.g. 2015-01-01 to 2015-12-31).
   We generate 12 monthly periods per year by adding 0..11 months to year_start. #}

select
    fcy.fiscal_calendar as calendar_id,
    fcy.year_name as fiscal_year_name,
    fcy.start_date as year_start_date,
    fcy.end_date as year_end_date,
    {{ extract_year('fcy.start_date') }} as calendar_year,
    m.month_offset + 1 as calendar_month,
    toDate(addMonths(fcy.start_date, m.month_offset)) as period_start_date,
    toDate(subtractDays(addMonths(fcy.start_date, m.month_offset + 1), 1)) as period_end_date,
    fcy.recid as year_recid,
    0 as period_recid
from {{ ref('bronze_fiscal_calendar_years') }} as fcy
cross join (
    select arrayJoin(range(12)) as month_offset
) as m
where addMonths(fcy.start_date, m.month_offset) <= fcy.end_date
