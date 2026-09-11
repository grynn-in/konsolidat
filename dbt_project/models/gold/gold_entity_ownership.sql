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

with periods_needed as (
    select distinct
        fiscal_year,
        fiscal_period,
        {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }}
    where 1 = 1
        {{ period_filter('fiscal_year', 'fiscal_period') }}
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
    cross join periods_needed as p
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
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    period_date,
    chain_depth,
    toUInt8(unresolved_links = 0) as has_complete_chain,
    if(unresolved_links = 0, chain_product, 0.0) as effective_ownership_pct,
    if(unresolved_links = 0, direct_pct, 0.0) as direct_ownership_pct,
    multiIf(
        method_rank = 1, 'full',
        method_rank = 2, 'proportional',
        method_rank = 3, 'equity',
        'none'
    ) as consolidation_method
from resolved
