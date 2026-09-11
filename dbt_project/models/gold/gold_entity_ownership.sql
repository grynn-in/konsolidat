{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# F2: the ONE resolved answer to "how much of this entity does this group own,
   in this period, and how is it consolidated".

   Two things were wrong before, and they compounded:

   1. Ownership lived in three places — the consolidation_groups seed, the
      consolidation_hierarchy staging table, and ownership_periods — with an
      ad-hoc `if(x != 0, ...)` chain choosing between them that read a genuine
      0% as "unset". Ownership is now temporal and lives only in Ownership
      Period; Consolidation Group is structure.

   2. The tree was stored and never traversed. Every consolidated model joined
      an entity to its IMMEDIATE parent group only, so GROUP_CORP's consolidated
      result contained JPMF and USMF and none of GROUP_EMEA's entities — at any
      percentage. `effective_ownership_pct` was a column name, not a
      computation: konsol wrote the direct percentage into it.

   The link closure (epm_staging.consolidation_ancestry, written by konsol's
   tree walk) carries one row per (ancestor group, entity, link between them).
   Multiplying each link's dated percentage gives the effective share, and
   emitting a row per ancestor is what makes consolidation multi-level: a
   60%-owned subsidiary of an 80%-owned sub-group reaches the top group at 48%.

   A chain is only usable if EVERY link resolves to a period covering the date.
   One missing link yields effective 0 and `has_complete_chain = 0` rather than
   a plausible-looking number — assert_ownership_chain_complete fails the build
   and names the entity. #}

{# The periods an entity actually HAS data in — per entity, not a global spine.
   A global spine crossed every link with every period in the warehouse, so an
   entity acquired in 2025 came out with an unresolvable chain for every period
   back to 2019 and a disposed one for every period after it left, and
   assert_ownership_chain_complete failed the build on all of them.

   No period_filter here either. This model is materialized `table`, and
   gold_nci_movement_schedule and gold_equity_method_associates are plain tables
   that now inner-join it on (fiscal_year, fiscal_period): filtering to one
   period during a scoped close would rebuild both holding that period alone and
   silently drop every prior period's NCI schedule and equity entries. The
   consolidation chokepoint downstream still applies its own filter, and
   gold_trial_balance is deliberately unscoped. #}
with entity_periods as (
    select distinct
        data_area_id,
        fiscal_year,
        fiscal_period,
        {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }}
),

ancestry as (
    select
        consolidation_group,
        data_area_id,
        link_group,
        link_data_area_id,
        link_depth,
        depth
    from {{ source('epm_staging', 'consolidation_ancestry') }}
    where consolidation_group != '' and data_area_id != ''
),

{# Nullable throughout: an ASOF LEFT JOIN miss is filled with the column DEFAULT
   (0 / '' / 1970-01-01), not NULL, so without this a node with no ownership
   period would read as a real 0% — indistinguishable from a deliberate
   deconsolidation. The same defaulting trap the FX and historical-rate blocks
   in gold_consolidated_trial_balance guard against. #}
ownership as (
    select
        consolidation_group,
        data_area_id,
        effective_date,
        cast(end_date as Nullable(Date)) as end_date,
        cast(toFloat64(ownership_pct) as Nullable(Float64)) as ownership_pct,
        cast(consolidation_method as Nullable(String)) as consolidation_method
    from {{ source('epm_staging', 'ownership_periods') }}
),

ancestry_periods as (
    select
        a.consolidation_group as consolidation_group,
        a.data_area_id as data_area_id,
        a.link_group as link_group,
        a.link_data_area_id as link_data_area_id,
        a.link_depth as link_depth,
        a.depth as depth,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        p.period_date as period_date
    from ancestry as a
    inner join entity_periods as p
        on a.data_area_id = p.data_area_id
),

{# Does the ENTITY's own node have any ownership history at all, and does it
   cover this period? "We know when we owned it and this is not it" (before an
   acquisition, after a disposal) is a deliberate 0, not a missing percentage —
   consolidation excludes it either way, but only the latter is worth failing a
   build over. #}
entity_windows as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.fiscal_year as fiscal_year,
        ap.fiscal_period as fiscal_period,
        max(o.consolidation_group != '') as node_has_any_period
    from ancestry_periods as ap
    left join {{ source('epm_staging', 'ownership_periods') }} as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.link_depth = ap.depth
    group by ap.consolidation_group, ap.data_area_id, ap.fiscal_year, ap.fiscal_period
),

{# ASOF picks the latest period whose effective_date <= period_date; end_date is
   then checked explicitly, because ASOF cannot carry a second inequality and
   would otherwise keep applying an expired period forever. #}
links as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.fiscal_year as fiscal_year,
        ap.fiscal_period as fiscal_period,
        ap.period_date as period_date,
        ap.link_group as link_group,
        ap.link_depth as link_depth,
        ap.depth as depth,
        if(o.end_date >= ap.period_date, o.ownership_pct, null) as link_pct,
        if(o.end_date >= ap.period_date, o.consolidation_method, null) as link_method
    from ancestry_periods as ap
    asof left join ownership as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.period_date >= o.effective_date
),

resolved as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        period_date,
        any(depth) as chain_depth,
        {# the entity's IMMEDIATE parent group: a historical equity rate and an
           entity name are recorded once, under the node that owns the entity —
           not under every ancestor that consolidates it #}
        anyIf(link_group, link_depth = depth) as owner_group,
        countIf(link_pct is null) as unresolved_links,
        arrayProduct(groupArray(coalesce(link_pct, 0.0) / 100.0)) as chain_product,
        {# the entity's own link: what its IMMEDIATE parent owns of it #}
        coalesce(anyIf(link_pct, link_depth = depth), 0.0) / 100.0 as direct_pct,
        {# the weakest link governs: a sub-group held at equity is not line
           consolidated into its parent, so nothing beneath it is either. An
           unrecognised method is treated as the strictest rather than silently
           as 'full'. #}
        max(multiIf(
            link_method = 'full', 1,
            link_method = 'proportional', 2,
            link_method = 'equity', 3,
            link_method = 'none', 4,
            4
        )) as method_rank
    from links
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date
)

select
    r.consolidation_group as consolidation_group,
    r.data_area_id as data_area_id,
    r.fiscal_year as fiscal_year,
    r.fiscal_period as fiscal_period,
    r.period_date as period_date,
    r.chain_depth as chain_depth,
    r.owner_group as owner_group,
    toUInt8(r.unresolved_links = 0) as has_complete_chain,
    {# 1 when the entity's node HAS ownership history but none of it covers this
       period — i.e. we did not own it then. Distinguishes a deliberate gap from
       an unrecorded one; assert_ownership_chain_complete only fails on the
       latter. #}
    toUInt8(r.unresolved_links > 0 and w.node_has_any_period > 0) as outside_ownership_window,
    if(r.unresolved_links = 0, r.chain_product, 0.0) as effective_ownership_pct,
    if(r.unresolved_links = 0, r.direct_pct, 0.0) as direct_ownership_pct,
    multiIf(
        r.method_rank = 1, 'full',
        r.method_rank = 2, 'proportional',
        r.method_rank = 3, 'equity',
        'none'
    ) as consolidation_method
from resolved as r
left join entity_windows as w
    on r.consolidation_group = w.consolidation_group
    and r.data_area_id = w.data_area_id
    and r.fiscal_year = w.fiscal_year
    and r.fiscal_period = w.fiscal_period
