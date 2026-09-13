{# The ownership chain resolved per (group, entity, period): the CTEs behind
   gold_entity_ownership, kept here so gold_ic_reconciliation resolves the
   same chain on a period spine of its own (#175 third review M1, M2).

   periods_cte names a CTE with one row per (data_area_id, fiscal_year,
   fiscal_period, period_date) to resolve. The macro emits CTEs whose names
   start with p, ending in {p}resolution, which holds gold_entity_ownership's
   columns. Call it after at least one CTE, as `with x as (...), {{ ... }}`.
   The commentary on each step is in gold_entity_ownership. #}
{% macro ownership_resolution_ctes(periods_cte, p='') %}
{{ p }}ancestry as (
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

{{ p }}ownership as (
    select
        consolidation_group,
        data_area_id,
        effective_date,
        cast(end_date as Nullable(Date)) as end_date,
        cast(toFloat64(ownership_pct) as Nullable(Float64)) as ownership_pct,
        cast(consolidation_method as Nullable(String)) as consolidation_method
    from {{ source('epm_staging', 'ownership_periods') }}
),

{{ p }}ancestry_periods as (
    select
        a.consolidation_group as consolidation_group,
        a.data_area_id as data_area_id,
        a.link_group as link_group,
        a.link_data_area_id as link_data_area_id,
        a.link_depth as link_depth,
        a.depth as depth,
        pp.fiscal_year as fiscal_year,
        pp.fiscal_period as fiscal_period,
        pp.period_date as period_date
    from {{ p }}ancestry as a
    inner join {{ periods_cte }} as pp
        on a.data_area_id = pp.data_area_id
),

{{ p }}entity_windows as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.fiscal_year as fiscal_year,
        ap.fiscal_period as fiscal_period,
        max(o.consolidation_group != '') as node_has_any_period
    from {{ p }}ancestry_periods as ap
    left join {{ source('epm_staging', 'ownership_periods') }} as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.link_depth = ap.depth
    group by ap.consolidation_group, ap.data_area_id, ap.fiscal_year, ap.fiscal_period
),

{{ p }}links as (
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
    from {{ p }}ancestry_periods as ap
    asof left join {{ p }}ownership as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.period_date >= o.effective_date
),

{{ p }}resolved as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        period_date,
        any(depth) as chain_depth,
        anyIf(link_group, link_depth = depth) as owner_group,
        countIf(link_pct is null) as unresolved_links,
        arrayProduct(groupArray(coalesce(link_pct, 0.0) / 100.0)) as chain_product,
        coalesce(anyIf(link_pct, link_depth = depth), 0.0) / 100.0 as direct_pct,
        max(multiIf(
            link_method = 'full', 1,
            link_method = 'proportional', 2,
            link_method = 'equity', 3,
            link_method = 'none', 4,
            4
        )) as method_rank
    from {{ p }}links
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date
),

{{ p }}resolution as (
    select
        r.consolidation_group as consolidation_group,
        r.data_area_id as data_area_id,
        r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period,
        r.period_date as period_date,
        r.chain_depth as chain_depth,
        r.owner_group as owner_group,
        toUInt8(r.unresolved_links = 0) as has_complete_chain,
        toUInt8(r.unresolved_links > 0 and w.node_has_any_period > 0) as outside_ownership_window,
        if(r.unresolved_links = 0, r.chain_product, 0.0) as effective_ownership_pct,
        if(r.unresolved_links = 0, r.direct_pct, 0.0) as direct_ownership_pct,
        multiIf(
            r.method_rank = 1, 'full',
            r.method_rank = 2, 'proportional',
            r.method_rank = 3, 'equity',
            'none'
        ) as consolidation_method
    from {{ p }}resolved as r
    left join {{ p }}entity_windows as w
        on r.consolidation_group = w.consolidation_group
        and r.data_area_id = w.data_area_id
        and r.fiscal_year = w.fiscal_year
        and r.fiscal_period = w.fiscal_period
)
{% endmacro %}
