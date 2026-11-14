-- PRD-9 Test: When temporal ownership exists, the consolidated TB must use it
-- Check that ownership_pct matches the temporal staging record for the period.
{# konsolidat#171 / #252: the period an Ownership Period applies to is read from the DECLARED calendar
   (epm_staging.fiscal_periods), never built from the period number. Before, this test judged fiscal
   period P at the first of calendar month P, the same macro the model used, so it could not catch the
   model being wrong: on a fiscal year starting in April it checked P1 against 1 January.

   The expectation is computed here, independently of the window's macros, by the deal journals' span
   rule (deal_period_holds()): a date belongs to the lowest Regular period whose declared span holds it. An Ownership Period
   applies from the period holding its effective_date through the period holding its end_date; a date
   before the calendar is before every period, and a date after it (or the open end, 9999-12-31 stored as
   2149-06-06) is after every period. A Closing period compares as its year's last Regular period. Where
   several Ownership Periods of one entity apply to one period (a change dated inside it), the latest one
   is the holding at the period's end and is the one expected. Fixture:
   assert_ownership_uses_effective_date.april_fiscal_year.sql. #}
with calendar as (
    select
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        start_date,
        end_date,
        period_type
    from {{ source('epm_staging', 'fiscal_periods') }}
),

last_regular as (
    select fy, max(fp) as last_fp
    from calendar
    where period_type = 'Regular'
    group by fy
),

compare_key as (
    select
        c.fy as fy,
        c.fp as fp,
        if(c.period_type = 'Closing' and lr.last_fp > 0, lr.last_fp, c.fp) as cmp_fp
    from calendar as c
    left join last_regular as lr
        on lr.fy = c.fy
),

calendar_start as (
    select min(start_date) as first_day from calendar
),

ops as (
    select
        op.consolidation_group as consolidation_group,
        op.data_area_id as data_area_id,
        op.effective_date as effective_date,
        op.end_date as end_date,
        toFloat64(op.ownership_pct) as ownership_pct,
        countIf({{ deal_period_holds('c', 'op.effective_date') }}) as n_from,
        minIf((c.fy, c.fp), {{ deal_period_holds('c', 'op.effective_date') }}) as from_key,
        countIf({{ deal_period_holds('c', 'op.end_date') }}) as n_to,
        minIf((c.fy, c.fp), {{ deal_period_holds('c', 'op.end_date') }}) as to_key
    from {{ source('epm_staging', 'ownership_periods') }} as op
    cross join calendar as c
    group by op.consolidation_group, op.data_area_id, op.effective_date, op.end_date, op.ownership_pct
),

op_windows as (
    select
        o.consolidation_group as consolidation_group,
        o.data_area_id as data_area_id,
        o.effective_date as effective_date,
        o.ownership_pct as ownership_pct,
        if(o.n_from > 0, o.from_key,
           if(o.effective_date < cs.first_day, (toUInt16(0), toUInt16(0)), (toUInt16(65535), toUInt16(65535)))) as from_key,
        if(o.n_to > 0, o.to_key,
           if(o.end_date < cs.first_day, (toUInt16(0), toUInt16(0)), (toUInt16(65535), toUInt16(65535)))) as to_key
    from ops as o
    cross join calendar_start as cs
),

expected as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        any(ctb.ownership_pct) as used_pct,
        argMax(w.ownership_pct, w.effective_date) / 100.0 as expected_pct
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join compare_key as k
        on k.fy = toUInt16(ctb.fiscal_year)
        and k.fp = toUInt16(ctb.fiscal_period)
    inner join op_windows as w
        on w.consolidation_group = ctb.consolidation_group
        and w.data_area_id = ctb.data_area_id
    {# ClickHouse rejects a cross-table range condition inside JOIN ... ON
       (INVALID_JOIN_ON_EXPRESSION); apply the period-in-range filter in WHERE. #}
    where (k.fy, k.cmp_fp) >= w.from_key
      and (k.fy, k.cmp_fp) <= w.to_key
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    used_pct,
    expected_pct
from expected
where abs(used_pct - expected_pct) > 0.001
limit 10
