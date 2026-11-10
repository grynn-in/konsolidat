{# konsolidat#171 / #252 (task 2a): the ONE source of declared period dates for the ownership window.

   One row per (fiscal_year, fiscal_period) that konsol's fiscal calendar declares
   (epm_staging.fiscal_periods): its period_type, its declared start_date and end_date, and the span the
   ownership window judges it on (window_start_date, window_end_date).

   The window span. A deal date belongs to a Regular period (deal_period_holds() below), and the deal
   journals compare every other period with it by (fiscal_year, fiscal_period) tuple: the disposal journal's
   line (0) derecognises every tuple up to and including the disposal period, and the acquisition journal's
   line (0) brings in every tuple before the acquisition period. So:
     Regular      its declared span.
     Opening, Adjustment
                  a BOUNDARY period, between two Regular periods (PR #345 reviews). window_end_date is
                  the end_date of the latest Regular period BEFORE it, window_start_date the start_date of
                  the earliest Regular period AFTER it (so window_start_date > window_end_date). The
                  ownership window reads it at window_end_date: it carries the state of the period before
                  it, except that a row ended by a full disposal dated on or before that day is not held
                  (macros/ownership_resolution.sql). That is "acquisition period < P and disposal period >
                  P" in tuple order: an Opening P0 is consolidated for an entity acquired by the eve of the
                  year (an acquisition on day 1 posts in P1, and its line (0) carries P0) and still held,
                  or disposed of, after it (the disposal journal of P1 derecognises P0 too); an Adjustment
                  P14 likewise (a disposal in P12 derecognises through P12, never P14). With no Regular
                  period before or after it, the day before its start or the day after its end stands in.
     Closing      judged as its fiscal year's last Regular period, so it is consolidated exactly when that
                  period is, a disposal in the last Regular period included. It holds only the year-end
                  close (silver_tb_movements: profit and loss into retained earnings), which line (0) never
                  derecognises (it leaves equity and P&L alone), and the group closes the year of an entity
                  it sold in its last Regular period the same way (IFRS 10.B98: the result up to disposal
                  stays in group reserves). The rule rate_period_map() declares for rates. A Closing period
                  in a year with no Regular period is judged by tuple order, as Opening is.
   A non-Regular period's window_start_date may be later than its window_end_date: that is the tuple rule,
   not an empty window.

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
            any(d.declared_type) as period_type,
            any(d.declared_start) as start_date,
            any(d.declared_end) as end_date,
            multiIf(
                any(d.declared_type) = 'Regular', any(d.declared_start),
                any(d.is_closing) = 1 and countIf(r.one = 1 and r.ry = d.fy) > 0,
                    argMaxIf(r.r_start, r.rfp, r.one = 1 and r.ry = d.fy),
                countIf(r.one = 1 and (r.ry, r.rfp) > (d.fy, d.fpn)) > 0,
                    argMinIf(r.r_start, (r.ry, r.rfp), r.one = 1 and (r.ry, r.rfp) > (d.fy, d.fpn)),
                addDays(any(d.declared_end), 1)
            ) as window_start_date,
            multiIf(
                any(d.declared_type) = 'Regular', any(d.declared_end),
                any(d.is_closing) = 1 and countIf(r.one = 1 and r.ry = d.fy) > 0,
                    argMaxIf(r.r_end, r.rfp, r.one = 1 and r.ry = d.fy),
                countIf(r.one = 1 and (r.ry, r.rfp) < (d.fy, d.fpn)) > 0,
                    argMaxIf(r.r_end, (r.ry, r.rfp), r.one = 1 and (r.ry, r.rfp) < (d.fy, d.fpn)),
                subtractDays(any(d.declared_start), 1)
            ) as window_end_date
        from (
            {# aliases differ from the columns they aggregate: ClickHouse would read a
               same-named alias inside the sibling aggregates (ILLEGAL_AGGREGATION) #}
            select
                toUInt16(fp.fiscal_year) as fy,
                toUInt16(fp.fiscal_period) as fpn,
                any(fp.period_type) as declared_type,
                max(fp.period_type = 'Closing') as is_closing,
                min(fp.start_date) as declared_start,
                max(fp.end_date) as declared_end,
                toUInt8(1) as one
            from {{ source('epm_staging', 'fiscal_periods') }} as fp
            group by fp.fiscal_year, fp.fiscal_period
        ) as d
        {# every declared Regular period, joined on a constant so a calendar with none still keeps its rows
           (join_use_nulls=0: a miss reads r.one = 0, which every aggregate above filters on) #}
        left join (
            select
                toUInt16(rp.fiscal_year) as ry,
                toUInt16(rp.fiscal_period) as rfp,
                min(rp.start_date) as r_start,
                max(rp.end_date) as r_end,
                toUInt8(1) as one
            from {{ source('epm_staging', 'fiscal_periods') }} as rp
            where rp.period_type = 'Regular'
            group by rp.fiscal_year, rp.fiscal_period
        ) as r
            on r.one = d.one
        group by d.fy, d.fpn
    )
{% endmacro %}

{# konsolidat#171 / #252 (PR #345 review, finding 2): THE rule that puts a dated deal in a period. A deal date
   belongs to the Regular period whose declared span holds it (start_date <= date <= end_date, period_type
   'Regular'); a caller takes the lowest such tuple. Opening (P0), Closing (P13) and Adjustment (P14) periods
   never hold a deal: konsol declares Opening and Closing as one-day periods that share their day with P1 and
   P12, and an Adjustment period is a year-end bookkeeping period, so a deal on that day belongs to the Regular
   period. One definition for the acquisition, disposal and goodwill amortisation journals and for every test
   that looks for a deal's period, so none can map a date differently.
   Used as `where {{ deal_period_holds('fp', 'bd.disposal_date') }}` on a cross join with the calendar. #}
{% macro deal_period_holds(fp, date_expr) %}
    ({{ fp }}.period_type = 'Regular' and {{ fp }}.start_date <= {{ date_expr }} and {{ fp }}.end_date >= {{ date_expr }})
{% endmacro %}


{# konsolidat#171 step 2c (T5): the share of the deal period the group did NOT hold, by calendar days.
   Decided by Deepak Pai: 18 Sep 2026 (mid-period P&L follows the group's declared partial_period_treatment),
   10 Nov 2026 Q2 C (a disposal period's P&L follows the treatment, IFRS 10.B88).
   Days are inclusive and the deal date is a group day on both sides:
     acquisition  dateDiff('day', start_date, deal_date) / (dateDiff('day', start_date, end_date) + 1)
                  an acquisition on the 11th of a 31-day month removes 10/31; on the first day, 0.
     disposal     dateDiff('day', deal_date, end_date) / (dateDiff('day', start_date, end_date) + 1)
                  a disposal on the 20th of a 30-day month removes 10/30; on the last day, 0.
   start_date and end_date are the deal period's declared span (the Regular period deal_period_holds() gives).
   Returns Float64. `side` is the literal 'acquisition' or 'disposal'. #}
{% macro partial_period_removed_fraction(side, deal_date, start_date, end_date) %}
    {%- if side == 'acquisition' -%}
    if({{ deal_date }} > {{ start_date }},
       toFloat64(dateDiff('day', {{ start_date }}, {{ deal_date }}))
           / (dateDiff('day', {{ start_date }}, {{ end_date }}) + 1),
       toFloat64(0))
    {%- elif side == 'disposal' -%}
    if({{ deal_date }} < {{ end_date }},
       toFloat64(dateDiff('day', {{ deal_date }}, {{ end_date }}))
           / (dateDiff('day', {{ start_date }}, {{ end_date }}) + 1),
       toFloat64(0))
    {%- else -%}
    {{ exceptions.raise_compiler_error("partial_period_removed_fraction: side must be 'acquisition' or 'disposal', got '" ~ side ~ "'") }}
    {%- endif -%}
{% endmacro %}
