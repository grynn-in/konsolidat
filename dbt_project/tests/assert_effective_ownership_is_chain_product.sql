{#
    F2: the effective share must be the PRODUCT of every link's dated percentage
    along the consolidation chain.

    This replaces assert_ownership_fallback, which asserted the behaviour F2
    deleted — that an entity with no temporal ownership row falls back to the
    consolidation_groups seed. There is no fallback and no seed any more.

    Independent of the model's arithmetic: gold_entity_ownership multiplies with
    arrayProduct over a groupArray; this recomputes the same product as
    exp(sum(log(...))) directly from the ancestry closure and the periods, so a
    bug in either aggregation shows up as a disagreement rather than cancelling
    out. Rows with a zero link are excluded because log(0) is undefined — the
    has_complete_chain / zero case is covered by
    assert_ownership_chain_complete.
#}

with periods_needed as (
    select distinct
        fiscal_year,
        fiscal_period,
        {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }}
),

ownership as (
    select
        consolidation_group,
        data_area_id,
        effective_date,
        cast(end_date as Nullable(Date)) as end_date,
        cast(toFloat64(ownership_pct) as Nullable(Float64)) as ownership_pct
    from {{ source('epm_staging', 'ownership_periods') }}
),

ancestry_periods as (
    select
        a.consolidation_group as consolidation_group,
        a.data_area_id as data_area_id,
        a.link_group as link_group,
        a.link_data_area_id as link_data_area_id,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        p.period_date as period_date
    from {{ source('epm_staging', 'consolidation_ancestry') }} as a
    cross join periods_needed as p
    where a.consolidation_group != '' and a.data_area_id != ''
),

oracle as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.fiscal_year as fiscal_year,
        ap.fiscal_period as fiscal_period,
        exp(sum(log(if(o.end_date >= ap.period_date, o.ownership_pct, null) / 100.0))) as expected_pct,
        countIf(if(o.end_date >= ap.period_date, o.ownership_pct, null) is null) as unresolved,
        countIf(if(o.end_date >= ap.period_date, o.ownership_pct, null) = 0) as zero_links
    from ancestry_periods as ap
    asof left join ownership as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.period_date >= o.effective_date
    group by ap.consolidation_group, ap.data_area_id, ap.fiscal_year, ap.fiscal_period
)

select
    eo.consolidation_group,
    eo.data_area_id,
    eo.fiscal_year,
    eo.fiscal_period,
    eo.effective_ownership_pct as model_pct,
    o.expected_pct as expected_pct
from {{ ref('gold_entity_ownership') }} as eo
inner join oracle as o
    on eo.consolidation_group = o.consolidation_group
    and eo.data_area_id = o.data_area_id
    and eo.fiscal_year = o.fiscal_year
    and eo.fiscal_period = o.fiscal_period
where o.unresolved = 0
  and o.zero_links = 0
  and abs(eo.effective_ownership_pct - o.expected_pct) > 0.000001
