{# Ownership resolved per (consolidating group, entity, period): the CTEs behind
   gold_entity_ownership, kept here so gold_ic_reconciliation resolves the same
   graph on a period spine of its own (#175 third review M1, M2).

   konsol#117 (option A, decided 7 Nov 2026): ownership is a graph of dated
   links, and an entity can be reached from a group along several paths.
   epm_staging.consolidation_ancestry carries one row per (ancestor group,
   entity, path, link on that path); `path_id` keys the path, and each link
   names the node it owns (link_group, link_data_area_id) and the node that
   holds it (link_owner_group, link_owner_data_area_id). The Ownership Period
   behind a link is matched on BOTH nodes: two owners of one node are two rows.

       pct(p)   = product over links l on p of link_pct(l)   (one path: as before)
       eff(G,E) = sum over paths p of pct(p)                  (NEW: paths add)
       nci(G,E) = 1 - eff(G,E)                                (unchanged downstream)

   Whose method applies (design comment section 2; DECLARATION_TRIGGER_PCT is
   the one named constant):

       exactly one path                                -> weakest link, 'link'
       several, same weakest method, one path all-full -> that method, 'link'
       several, same weakest method, none all-full,
           eff <= DECLARATION_TRIGGER_PCT              -> that method, 'link'
       several, weakest methods disagree               -> declared
       several, none all-full, eff > trigger           -> declared
       declaration required and absent                 -> consolidation_method
           'none', method_source 'undeclared': nothing consolidates for (G, E)
           and assert_method_declared_for_multi_path fails the build naming it.

   The trigger (50%, the IFRS 10.B35 presumption of control through votes)
   only REQUIRES a declaration; it never picks a method. A declaration is a row
   of epm_staging.consolidation_method_declarations for (G, E), read ASOF
   effective_date <= period_date and not lapsed, read as a link is (below).

   THE WINDOW (konsolidat#171, #252, #278): a period is judged on the dates
   konsol's calendar DECLARES for it (macros/declared_periods.sql), never on a
   date built from the period number. The ASOF join, keyed on period_date (P's
   declared end), picks per link the latest Ownership Period that started by
   P's end, and the holding is read AT THE PERIOD END: a link counts when it
   has not ended by P's end. Only when no path from the group to the entity is
   held at P's end (a full disposal inside P) does a link that ended inside P
   still count (end_date >= period_start_date), so the disposal period stays in
   the window. Read at the start for every link, a holding moved between two
   owners inside P counted under both (PR #345 review, finding 1). A
   declaration lapses by the same reading.

   This agrees with the period the deal journals post in (deal_period_holds():
   the Regular period holding the date): an acquisition is consolidated from
   the period its journal posts in (line (0) brings the balance sheet in up to
   the period before), and a full disposal up to and including the period its
   journal posts in (line (0) derecognises the cumulative balances through that
   period), and not after. Opening, Adjustment and Closing periods are judged as
   declared_periods() explains.

   periods_cte names a CTE with one row per (data_area_id, fiscal_year,
   fiscal_period, period_start_date, period_date) to resolve, the two dates
   being a declared_periods() row's window_start_date and window_end_date. The macro emits CTEs whose names
   start with p, ending in {p}resolution, which holds gold_entity_ownership's
   columns. Call it after at least one CTE, as `with x as (...), {{ ... }}`.
   The commentary on each step is in gold_entity_ownership. #}
{% macro ownership_resolution_ctes(periods_cte, p='') %}
{% set DECLARATION_TRIGGER_PCT = 50 %}
{{ p }}ancestry as (
    select
        consolidation_group,
        data_area_id,
        link_group,
        link_data_area_id,
        link_owner_group,
        link_owner_data_area_id,
        link_depth,
        depth,
        path_id
    from {{ source('epm_staging', 'consolidation_ancestry') }}
    where consolidation_group != '' and data_area_id != ''
),

{{ p }}ownership as (
    select
        consolidation_group,
        data_area_id,
        owner_group,
        owner_data_area_id,
        effective_date,
        cast(end_date as Nullable(Date)) as end_date,
        cast(toFloat64(ownership_pct) as Nullable(Float64)) as ownership_pct,
        cast(consolidation_method as Nullable(String)) as consolidation_method
    from {{ source('epm_staging', 'ownership_periods') }}
),

{# Does this link have ANY ownership history, whatever its dates? A link whose
   node has periods but none covering the date is one we did not hold then
   (before an acquisition, after a disposal): its path contributes 0 and nothing
   fails. A link with no period at all is an unrecorded gap, which fails the
   build (assert_ownership_chain_complete). #}
{{ p }}link_history as (
    select
        consolidation_group,
        data_area_id,
        owner_group,
        owner_data_area_id,
        toUInt8(1) as has_history
    from {{ p }}ownership
    group by consolidation_group, data_area_id, owner_group, owner_data_area_id
),

{{ p }}declarations as (
    select
        consolidation_group,
        data_area_id,
        effective_date,
        cast(end_date as Nullable(Date)) as end_date,
        cast(consolidation_method as Nullable(String)) as consolidation_method
    from {{ source('epm_staging', 'consolidation_method_declarations') }}
),

{{ p }}ancestry_periods as (
    select
        a.consolidation_group as consolidation_group,
        a.data_area_id as data_area_id,
        a.path_id as path_id,
        a.link_group as link_group,
        a.link_data_area_id as link_data_area_id,
        a.link_owner_group as link_owner_group,
        a.link_owner_data_area_id as link_owner_data_area_id,
        a.link_depth as link_depth,
        a.depth as depth,
        pp.fiscal_year as fiscal_year,
        pp.fiscal_period as fiscal_period,
        pp.period_start_date as period_start_date,
        pp.period_date as period_date
    from {{ p }}ancestry as a
    inner join {{ periods_cte }} as pp
        on a.data_area_id = pp.data_area_id
),

{# Each link, read two ways (PR #345 review, finding 1):
     *_end    held at the period END: the ASOF row (the latest that started by
              period_date) has not ended by it. greatest() because an Opening or
              Adjustment period's window_start_date lies after its window_end_date
              (declared_periods()): held at its end means still held when the next
              Regular period starts.
     *_start  not ended before the period began (end_date >= period_start_date):
              a link that ended INSIDE the period still counts. #}
{{ p }}link_candidates as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.path_id as path_id,
        ap.fiscal_year as fiscal_year,
        ap.fiscal_period as fiscal_period,
        ap.period_start_date as period_start_date,
        ap.period_date as period_date,
        ap.link_group as link_group,
        ap.link_owner_group as link_owner_group,
        ap.link_owner_data_area_id as link_owner_data_area_id,
        ap.link_depth as link_depth,
        ap.depth as depth,
        if(o.end_date >= greatest(ap.period_date, ap.period_start_date), o.ownership_pct, null) as link_pct_end,
        if(o.end_date >= greatest(ap.period_date, ap.period_start_date), o.consolidation_method, null) as link_method_end,
        if(o.end_date >= ap.period_start_date, o.ownership_pct, null) as link_pct_start,
        if(o.end_date >= ap.period_start_date, o.consolidation_method, null) as link_method_start,
        h.has_history as link_has_history
    from {{ p }}ancestry_periods as ap
    asof left join {{ p }}ownership as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.link_owner_group = o.owner_group
        and ap.link_owner_data_area_id = o.owner_data_area_id
        and ap.period_date >= o.effective_date
    left join {{ p }}link_history as h
        on ap.link_group = h.consolidation_group
        and ap.link_data_area_id = h.data_area_id
        and ap.link_owner_group = h.owner_group
        and ap.link_owner_data_area_id = h.owner_data_area_id
),

{# (group, entity, period) with at least one path whose every link is held at
   the period end. There the period-end reading decides: a holding that moved
   between owners inside the period counts once, under the owner holding it at
   the end, and an owner that sold out inside it counts for nothing. Where NO
   path is held at the end (a full disposal inside the period), the
   not-ended-before-the-start reading decides, so the disposal period stays in
   the window for the disposal journal's line (0) to derecognise. #}
{{ p }}held_at_end as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period, toUInt8(1) as window_at_end
    from (
        select consolidation_group, data_area_id, path_id, fiscal_year, fiscal_period,
               countIf(link_pct_end is null) as n_not_held
        from {{ p }}link_candidates
        group by consolidation_group, data_area_id, path_id, fiscal_year, fiscal_period
    )
    where n_not_held = 0
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

{{ p }}links as (
    select
        lc.consolidation_group as consolidation_group,
        lc.data_area_id as data_area_id,
        lc.path_id as path_id,
        lc.fiscal_year as fiscal_year,
        lc.fiscal_period as fiscal_period,
        lc.period_start_date as period_start_date,
        lc.period_date as period_date,
        lc.link_group as link_group,
        lc.link_owner_group as link_owner_group,
        lc.link_owner_data_area_id as link_owner_data_area_id,
        lc.link_depth as link_depth,
        lc.depth as depth,
        {# join_use_nulls=0: a miss reads window_at_end = 0 #}
        he.window_at_end as window_at_end,
        if(he.window_at_end = 1, lc.link_pct_end, lc.link_pct_start) as link_pct,
        if(he.window_at_end = 1, lc.link_method_end, lc.link_method_start) as link_method,
        lc.link_has_history as link_has_history
    from {{ p }}link_candidates as lc
    left join {{ p }}held_at_end as he
        on he.consolidation_group = lc.consolidation_group
        and he.data_area_id = lc.data_area_id
        and he.fiscal_year = lc.fiscal_year
        and he.fiscal_period = lc.fiscal_period
),

{# One row per path: its product, its weakest link, its direct (last) link. An
   unresolved link ranks as 'none' (the strictest), as an unrecognised method
   does. #}
{{ p }}paths as (
    select
        consolidation_group,
        data_area_id,
        path_id,
        fiscal_year,
        fiscal_period,
        period_start_date,
        period_date,
        max(window_at_end) as path_at_end,
        max(depth) as path_depth,
        anyIf(link_owner_group, link_depth = depth) as direct_owner_group,
        anyIf(link_owner_data_area_id, link_depth = depth) as direct_owner_data_area_id,
        anyIf(link_group, link_depth = depth) as node_group,
        anyIf(link_pct, link_depth = depth) as direct_pct,
        countIf(link_pct is null) as unresolved_links,
        countIf(link_pct is null and link_has_history = 0) as unrecorded_links,
        {# links on this path that are full and below 100%: a joint operation beneath one is refused
           (assert_joint_operation_path_has_no_partial_full_link, konsol#117 pair 3 finding A) #}
        countIf(link_method = 'full' and link_pct < 100) as partial_full_links,
        arrayProduct(groupArray(coalesce(link_pct, 0.0) / 100.0)) as path_product,
        max(multiIf(
            link_method = 'full', 1,
            link_method = 'proportional', 2,
            link_method = 'equity', 3,
            link_method = 'none', 4,
            4
        )) as path_method_rank
    from {{ p }}links
    group by consolidation_group, data_area_id, path_id, fiscal_year, fiscal_period, period_start_date, period_date
),

{# All paths from G to E, summed. Only a path whose every link resolves counts,
   and the method vote is among those paths. direct_ownership_pct is the sum of
   the DISTINCT links into E's node: two paths may end on the same link. #}
{{ p }}resolved as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        period_start_date,
        period_date,
        max(path_at_end) as window_at_end,
        max(path_depth) as chain_depth,
        toUInt32(uniqExact(path_id)) as path_count,
        toUInt32(uniqExact((direct_owner_group, direct_owner_data_area_id))) as direct_owner_count,
        countIf(unresolved_links = 0) as resolved_paths,
        countIf(unrecorded_links > 0) as unrecorded_paths,
        sumIf(path_product, unresolved_links = 0) as effective_sum,
        arraySum(arrayMap(t -> t.3, arrayDistinct(groupArrayIf(
            (direct_owner_group, direct_owner_data_area_id, coalesce(direct_pct, 0.0) / 100.0),
            direct_pct is not null
        )))) as direct_sum,
        {# The group the historical-rate join keys on: the consolidation_group of
           the entity's OWN node, the same on every path (an entity sits in one
           tree node). It is what konsol validates a Historical Equity Rate
           against (historical_equity_rate.py, the node lookup on
           consolidation_group + data_area_id) and exactly what this column held
           before konsol#117, so the upgrade changes no rate match. The nodes
           holding the links are in direct_owner_count; whether the rate needs a
           group at all is the open question on konsol#117. #}
        any(node_group) as owner_group,
        uniqExactIf(path_method_rank, unresolved_links = 0) as method_ranks,
        maxIf(path_method_rank, unresolved_links = 0) as method_rank,
        maxIf(path_method_rank = 1, unresolved_links = 0) as any_path_all_full,
        toUInt8(maxIf(partial_full_links > 0, unresolved_links = 0)) as has_partial_full_link
    from {{ p }}paths
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, period_start_date, period_date
),

{{ p }}ruled as (
    select
        *,
        toUInt8(resolved_paths > 1 and (
            method_ranks > 1
            or (any_path_all_full = 0 and effective_sum * 100.0 > {{ DECLARATION_TRIGGER_PCT }})
        )) as needs_declaration
    from {{ p }}resolved
),

{{ p }}resolution as (
    select
        r.consolidation_group as consolidation_group,
        r.data_area_id as data_area_id,
        r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period,
        r.period_date as period_date,
        r.period_start_date as period_start_date,
        r.chain_depth as chain_depth,
        r.owner_group as owner_group,
        toUInt8(r.resolved_paths > 0 and r.unrecorded_paths = 0) as has_complete_chain,
        toUInt8(r.resolved_paths = 0 and r.unrecorded_paths = 0) as outside_ownership_window,
        if(r.resolved_paths > 0 and r.unrecorded_paths = 0, r.effective_sum, 0.0) as effective_ownership_pct,
        if(r.resolved_paths > 0 and r.unrecorded_paths = 0, r.direct_sum, 0.0) as direct_ownership_pct,
        multiIf(
            r.needs_declaration = 0, 'link',
            d.consolidation_method is not null and d.end_date >= if(r.window_at_end = 1, greatest(r.period_date, r.period_start_date), r.period_start_date), 'declared',
            'undeclared'
        ) as method_source,
        multiIf(
            r.needs_declaration = 1 and d.consolidation_method is not null and d.end_date >= if(r.window_at_end = 1, greatest(r.period_date, r.period_start_date), r.period_start_date),
                assumeNotNull(d.consolidation_method),
            r.needs_declaration = 1, 'none',
            r.resolved_paths = 0, 'none',
            r.method_rank = 1, 'full',
            r.method_rank = 2, 'proportional',
            r.method_rank = 3, 'equity',
            'none'
        ) as consolidation_method,
        r.path_count as path_count,
        r.direct_owner_count as direct_owner_count,
        r.has_partial_full_link as has_partial_full_link
    from {{ p }}ruled as r
    asof left join {{ p }}declarations as d
        on r.consolidation_group = d.consolidation_group
        and r.data_area_id = d.data_area_id
        and r.period_date >= d.effective_date
)
{% endmacro %}
