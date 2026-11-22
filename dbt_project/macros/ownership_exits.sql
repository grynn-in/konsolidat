{# konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai): the exit events of the ownership graph.

   An exit event of an entity E from a group G: E was live in G in a declared period and is not live in the next
   one, F (the first period out), and no full Business Disposal ended it. The event's period P is the period the
   derecognition journal for a bare link end (gold_ownership_exit_journal) posts in; it reverses everything the
   group carried for E through AND including P.

   P (#358 review F1, IFRS 10.25: derecognise when control is lost): the Regular period that HOLDS the end date
   that caused the exit (deal_period_holds(), lowest tuple, before F), the rule that puts a full disposal in the
   period holding its disposal_date. The ownership window (macros/ownership_resolution.sql) keeps a link that
   ended inside a period live for that period, so E is consolidated in P and the exit takes it out by P's end,
   as disposal line (0) does: an end on 15 March posts in March, not April. An end on the last day of a period
   is held through it: that period is P too (the window holds the link at the period end, and F is the next one).
   Where no end date caused the exit (a method change, a lapsed declaration), or no Regular period before F
   holds it, P = F: E is already not consolidated in F, so the journal reverses what was carried before it.
   Readers that need the first period E is no longer consolidated (the #257 stint boundary in
   gold_consolidated_trial_balance, the IC 'left' row) read F, out_fiscal_year / out_fiscal_period.

   Year end. An Opening, Closing or Adjustment period carries the state of the Regular period it follows
   (declared_periods()), so a link ended on the last day of a year's last Regular period is still live through
   Closing P13, Adjustment P14 and the next year's Opening P0, and F is the next Regular period, while P is the
   year's last Regular period. The window does not drop such a row in those boundary periods as it drops one
   ended by a full disposal (ended_by_disposal): a successor or a transfer dated on the next day must still see
   the old row there. A layer-1 row of E in P14 or P0 after such an exit is therefore not reversed; the window
   rule for a bare end on a year's last day is a follow-up. A link ended inside the last Regular period, not on
   its last day, is not held in P14 or P0; P13 (judged as that Regular period) holds it.

   Live = the entity line-consolidates, or is equity-accounted, into G at the period: a complete ownership
   chain, consolidation_method full, proportional or equity (ownership_resolution_ctes: has_complete_chain
   and consolidation_method). Resolved exactly as gold_ic_reconciliation resolves its 'left' row, from the
   same CTEs on a period spine of declared_periods(), so an intercompany pair that leaves with E leaves in F
   (the first spine period at or after it). It does NOT read gold_entity_ownership: that model has rows only
   where a trial balance exists, so a missing row there is not an exit.

   Not an exit:
     - a successor Ownership Period, or an owner-to-owner transfer: E stays live, the chain is held at F
       (konsol#305-Q1-1, steps stay free);
     - a link ended by a full Business Disposal of E (ended_by_disposal, ownership_resolution_ctes): the
       disposal journal derecognises E, line (0). Only E's own link counts; a sub-group's disposal ends E's
       window without a journal for E, so E exits, in the period holding the sub-group's disposal date.
   Out of scope here (a WARN names them, task X8): a step to equity, a share that drops through another path.

   One row per event: consolidation_group, data_area_id, fiscal_year, fiscal_period (P, the exit period),
   out_fiscal_year, out_fiscal_period (F), previous_fiscal_year, previous_fiscal_period (the declared period
   before F), method_before, share_before (effective_ownership_pct, 0..1 as ownership_resolution_ctes carries
   it), end_date (the latest end date of a link on E's chain that falls from the previous period's start up to
   F's end; NULL when none does, e.g. a method change).

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
        ),

        {# P: the Regular period holding the end (deal_period_holds()), lowest tuple, before F #}
        ex_holding as (
            select
                en.consolidation_group as consolidation_group,
                en.data_area_id as data_area_id,
                en.fiscal_year as fiscal_year,
                en.fiscal_period as fiscal_period,
                min((dp.fiscal_year, dp.fiscal_period)) as holding_period,
                toUInt8(1) as has_holding
            from ex_ends as en
            cross join {{ declared_periods() }} as dp
            where {{ deal_period_holds('dp', 'en.last_end') }}
              and (dp.fiscal_year, dp.fiscal_period) < (en.fiscal_year, en.fiscal_period)
            group by en.consolidation_group, en.data_area_id, en.fiscal_year, en.fiscal_period
        )

        select
            c.consolidation_group as consolidation_group,
            c.data_area_id as data_area_id,
            {# join_use_nulls=0: no holding period reads has_holding = 0, and P = F #}
            if(h.has_holding = 1, tupleElement(h.holding_period, 1), c.fiscal_year) as fiscal_year,
            if(h.has_holding = 1, tupleElement(h.holding_period, 2), c.fiscal_period) as fiscal_period,
            c.fiscal_year as out_fiscal_year,
            c.fiscal_period as out_fiscal_period,
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
        left join ex_holding as h
            on h.consolidation_group = c.consolidation_group and h.data_area_id = c.data_area_id
            and h.fiscal_year = c.fiscal_year and h.fiscal_period = c.fiscal_period
        where coalesce(en.ended_by_own_disposal, 0) = 0
    )
{% endmacro %}
