{#
    konsol#117: the effective share is the SUM over paths of the PRODUCT of each
    path's dated link percentages. Replaces assert_effective_ownership_is_chain_product,
    which took one product over every link of a (group, entity) and so would have
    multiplied two paths into each other (shape 1: 0.8 x 0.6 x 0.2 = 0.096 instead of
    0.48 + 0.20 = 0.68).

    Independent of the model's arithmetic: gold_entity_ownership uses arrayProduct
    over a groupArray per path and sum across paths; this recomputes each path as
    exp(sum(log(...))) keyed on path_id, straight from the ancestry closure and the
    periods, then sums, so a bug in either aggregation shows up as a disagreement
    rather than cancelling out. A link is matched on BOTH its nodes (owned and owner),
    as the model does: two owners of one node are two links.

    A (group, entity, period) with an unresolved link on any path is skipped (the
    has_complete_chain / window case is assert_ownership_chain_complete's), and so is
    one with a zero link (log(0) is undefined).

    Fixtures: assert_effective_ownership_is_path_sum.direct_plus_indirect.sql (+ .must_flag),
    .indirect_associate.sql, .single_chain.sql.
#}

{# The periods and their dates come from the declared calendar, as the model's do (declared_periods(),
   konsolidat#171 / #252): this test checks the path arithmetic, not the window, so it reads the window on
   the same declared dates rather than on a second, disagreeing date rule. The window itself is checked
   independently by assert_ownership_window_matches_deal_period and assert_ownership_uses_effective_date. #}
with periods_needed as (
    select distinct
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        dp.window_start_date as period_start_date,
        dp.window_end_date as period_date
    from {{ ref('gold_trial_balance') }} as tb
    inner join {{ declared_periods() }} as dp
        on dp.fiscal_year = toUInt16(tb.fiscal_year)
        and dp.fiscal_period = toUInt16(tb.fiscal_period)
),

ownership as (
    select
        consolidation_group,
        data_area_id,
        owner_group,
        owner_data_area_id,
        effective_date,
        cast(end_date as Nullable(Date)) as end_date,
        cast(toFloat64(ownership_pct) as Nullable(Float64)) as ownership_pct
    from {{ source('epm_staging', 'ownership_periods') }}
),

ancestry_periods as (
    select
        a.consolidation_group as consolidation_group,
        a.data_area_id as data_area_id,
        a.path_id as path_id,
        a.link_group as link_group,
        a.link_data_area_id as link_data_area_id,
        a.link_owner_group as link_owner_group,
        a.link_owner_data_area_id as link_owner_data_area_id,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        p.period_start_date as period_start_date,
        p.period_date as period_date
    from {{ source('epm_staging', 'consolidation_ancestry') }} as a
    cross join periods_needed as p
    where a.consolidation_group != '' and a.data_area_id != ''
),

path_oracle as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.path_id as path_id,
        ap.fiscal_year as fiscal_year,
        ap.fiscal_period as fiscal_period,
        exp(sum(log(if(o.end_date >= ap.period_start_date, o.ownership_pct, null) / 100.0))) as path_pct,
        countIf(if(o.end_date >= ap.period_start_date, o.ownership_pct, null) is null) as unresolved,
        countIf(if(o.end_date >= ap.period_start_date, o.ownership_pct, null) = 0) as zero_links
    from ancestry_periods as ap
    asof left join ownership as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.link_owner_group = o.owner_group
        and ap.link_owner_data_area_id = o.owner_data_area_id
        and ap.period_date >= o.effective_date
    group by ap.consolidation_group, ap.data_area_id, ap.path_id, ap.fiscal_year, ap.fiscal_period
),

oracle as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        sum(path_pct) as expected_pct,
        count() as path_count,
        sum(unresolved) as unresolved,
        sum(zero_links) as zero_links
    from path_oracle
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
)

select
    eo.consolidation_group,
    eo.data_area_id,
    eo.fiscal_year,
    eo.fiscal_period,
    eo.effective_ownership_pct as model_pct,
    o.expected_pct as expected_pct,
    o.path_count as path_count
from {{ ref('gold_entity_ownership') }} as eo
inner join oracle as o
    on eo.consolidation_group = o.consolidation_group
    and eo.data_area_id = o.data_area_id
    and eo.fiscal_year = o.fiscal_year
    and eo.fiscal_period = o.fiscal_period
where o.unresolved = 0
  and o.zero_links = 0
  and abs(eo.effective_ownership_pct - o.expected_pct) > 0.000001
