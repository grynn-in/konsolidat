{# konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai): the exit events of the ownership graph.

   An exit event (G, E, P) is the FIRST declared period P in which an entity E that was live in a group G
   the period before is no longer live, and where no full Business Disposal ended it. The derecognition
   journal for a bare link end (gold_ownership_exit_journal, tasks X3-X5) posts in P and reverses the
   to-date carried balances.

   Live = the entity line-consolidates, or is equity-accounted, into G at the period: a complete ownership
   chain, consolidation_method full, proportional or equity (ownership_resolution_ctes: has_complete_chain
   and consolidation_method). Resolved exactly as gold_ic_reconciliation resolves its 'left' row, from the
   same CTEs on a period spine of declared_periods(), so an intercompany pair that leaves with E and E's
   exit land in the SAME period. It does NOT read gold_entity_ownership: that model has rows only where a
   trial balance exists, so a missing row there is not an exit.

   "The period before" is the previous declared period of the calendar in (fiscal_year, fiscal_period)
   order, whatever its type. An Opening, Closing or Adjustment period carries the state of the Regular
   period it follows (declared_periods()), so a link ended in the last Regular period of a year is still
   live through Closing P13, Adjustment P14 and the next year's Opening P0, and the exit lands in the next
   Regular period. A link ended on a day inside a year's last Regular period, but not on its last day, is
   no longer held in the Adjustment period (window_start_date, the first day of the next year, is after
   the end): the exit lands there, as gold_ic_reconciliation's 'left' row does when that period has data.

   Not an exit:
     - a successor Ownership Period, or an owner-to-owner transfer: E stays live, the chain is held at P
       (konsol#305-Q1-1, steps stay free);
     - a link ended by a full Business Disposal of E (ended_by_disposal, ownership_resolution_ctes): the
       disposal journal derecognises E, line (0). Only E's own link counts; a sub-group's disposal ends E's
       window without a journal for E, so E exits.
   Out of scope here (a WARN names them, task X8): a step to equity, a share that drops through another path.

   One row per event: consolidation_group, data_area_id, fiscal_year, fiscal_period (the exit period),
   previous_fiscal_year, previous_fiscal_period, method_before, share_before (effective_ownership_pct, 0..1
   as ownership_resolution_ctes carries it), end_date (the latest end date of a link on E's chain that falls
   from the previous period's start up to the exit period's end; NULL when none does, e.g. a method change).

   A macro returning a subquery, not a model, for the reason declared_periods() is: no node to build or
   order. Used as `from {{ ownership_exits() }} as x`. #}
{% macro ownership_exits() %}
    (
        with ex_entities as (
            select distinct data_area_id
            from {{ source('epm_staging', 'consolidation_ancestry') }}
            where consolidation_group != '' and data_area_id != ''
        ),

        ex_entity_periods as (
            select
                e.data_area_id as data_area_id,
                dp.fiscal_year as fiscal_year,
                dp.fiscal_period as fiscal_period,
                dp.window_start_date as period_start_date,
                dp.window_end_date as period_date
            from ex_entities as e
            cross join {{ declared_periods() }} as dp
        ),

        {{ ownership_resolution_ctes('ex_entity_periods', 'ex_') }},

        ex_state as (
            select
                consolidation_group, data_area_id, fiscal_year, fiscal_period, period_start_date, period_date,
                toUInt8(has_complete_chain = 1 and consolidation_method in ('full', 'proportional', 'equity')) as is_live,
                consolidation_method,
                effective_ownership_pct
            from ex_resolution
        ),

        ex_marked as (
            select
                *,
                lagInFrame(is_live, 1, toUInt8(0)) over w as prev_live,
                lagInFrame(fiscal_year, 1, toUInt16(0)) over w as prev_fiscal_year,
                lagInFrame(fiscal_period, 1, toUInt16(0)) over w as prev_fiscal_period,
                lagInFrame(period_start_date, 1, toDate('1970-01-01')) over w as prev_start_date,
                lagInFrame(period_date, 1, toDate('1970-01-01')) over w as prev_date,
                lagInFrame(consolidation_method, 1, '') over w as prev_method,
                lagInFrame(effective_ownership_pct, 1, toFloat64(0)) over w as prev_share
            from ex_state
            window w as (
                partition by consolidation_group, data_area_id
                order by fiscal_year, fiscal_period
                rows between unbounded preceding and current row
            )
        ),

        ex_candidates as (
            select * from ex_marked where is_live = 0 and prev_live = 1
        ),

        {# the links of E's chain that ended since the previous period began: the end that caused the exit #}
        ex_ends as (
            select
                c.consolidation_group as consolidation_group,
                c.data_area_id as data_area_id,
                c.fiscal_year as fiscal_year,
                c.fiscal_period as fiscal_period,
                count() as n_ends,
                max(o.end_date) as last_end,
                {# only E's own link is derecognised by E's disposal journal #}
                max(toUInt8(a.link_data_area_id = c.data_area_id and coalesce(o.ended_by_disposal, 0) = 1)) as ended_by_own_disposal
            from ex_candidates as c
            inner join ex_ancestry as a
                on a.consolidation_group = c.consolidation_group and a.data_area_id = c.data_area_id
            inner join ex_ownership as o
                on o.consolidation_group = a.link_group
                and o.data_area_id = a.link_data_area_id
                and o.owner_group = a.link_owner_group
                and o.owner_data_area_id = a.link_owner_data_area_id
            where o.end_date >= least(c.prev_start_date, c.prev_date)
              and o.end_date < c.period_date
            group by c.consolidation_group, c.data_area_id, c.fiscal_year, c.fiscal_period
        )

        select
            c.consolidation_group as consolidation_group,
            c.data_area_id as data_area_id,
            c.fiscal_year as fiscal_year,
            c.fiscal_period as fiscal_period,
            c.prev_fiscal_year as previous_fiscal_year,
            c.prev_fiscal_period as previous_fiscal_period,
            c.prev_method as method_before,
            c.prev_share as share_before,
            {# join_use_nulls=0: a miss reads n_ends = 0 #}
            if(en.n_ends = 0, cast(null as Nullable(Date)), cast(en.last_end as Nullable(Date))) as end_date
        from ex_candidates as c
        left join ex_ends as en
            on en.consolidation_group = c.consolidation_group and en.data_area_id = c.data_area_id
            and en.fiscal_year = c.fiscal_year and en.fiscal_period = c.fiscal_period
        where coalesce(en.ended_by_own_disposal, 0) = 0
    )
{% endmacro %}
