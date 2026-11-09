{# konsolidat#171 / #252 (task 2a): the ONE source of declared period dates for the ownership window.

   One row per (fiscal_year, fiscal_period) that konsol's fiscal calendar declares
   (epm_staging.fiscal_periods): its period_type, its declared start_date and end_date, and the span the
   ownership window judges it on (window_start_date, window_end_date).

   The window span is the declared span, with one declared exception: a Closing period is judged as its
   fiscal year's last Regular period. A Closing period holds the year-end close (silver_tb_movements posts
   the close there) and no deal is ever dated into it (the deal journals skip Closing periods), so it is
   consolidated exactly when the year's last Regular period is. It is the same rule rate_period_map()
   declares for rates. A Closing period in a year with no Regular period keeps its own span.

   A period the calendar does not declare has NO row here. Nothing is invented for it (no first or last
   day of a calendar month): a reader that inner-joins this drops the period, and
   assert_trial_balance_period_declared (ERROR) fails the build naming it. A period declared on several
   rows is grouped to one, so a duplicated calendar row cannot fan a join out; the same test refuses one
   declared with conflicting spans.

   Why a macro returning a subquery, not a model: the readers (gold_entity_ownership,
   gold_ic_reconciliation) already depend on the source, it adds no node to build or order, and the fixture
   gate creates no relation for it. rate_period_map() is the precedent. Used as
   `inner join {{ declared_periods() }} as dp on dp.fiscal_year = ... and dp.fiscal_period = ...`;
   fiscal_year and fiscal_period are UInt16. #}
{% macro declared_periods() %}
    (
        select
            d.fy as fiscal_year,
            d.fpn as fiscal_period,
            d.declared_type as period_type,
            d.declared_start as start_date,
            d.declared_end as end_date,
            if(d.is_closing = 1 and r.has_regular = 1, r.regular_start_date, d.declared_start) as window_start_date,
            if(d.is_closing = 1 and r.has_regular = 1, r.regular_end_date, d.declared_end) as window_end_date
        from (
            {# aliases differ from the columns they aggregate: ClickHouse would read a
               same-named alias inside the sibling aggregates (ILLEGAL_AGGREGATION) #}
            select
                toUInt16(fp.fiscal_year) as fy,
                toUInt16(fp.fiscal_period) as fpn,
                any(fp.period_type) as declared_type,
                max(fp.period_type = 'Closing') as is_closing,
                min(fp.start_date) as declared_start,
                max(fp.end_date) as declared_end
            from {{ source('epm_staging', 'fiscal_periods') }} as fp
            group by fp.fiscal_year, fp.fiscal_period
        ) as d
        {# join_use_nulls=0: a year with no Regular period reads has_regular = 0, never NULL #}
        left join (
            select
                toUInt16(rp.fiscal_year) as ry,
                argMax(rp.start_date, toUInt16(rp.fiscal_period)) as regular_start_date,
                argMax(rp.end_date, toUInt16(rp.fiscal_period)) as regular_end_date,
                toUInt8(1) as has_regular
            from {{ source('epm_staging', 'fiscal_periods') }} as rp
            where rp.period_type = 'Regular'
            group by rp.fiscal_year
        ) as r
            on r.ry = d.fy
    )
{% endmacro %}
