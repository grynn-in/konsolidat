{#
    konsol#117: the effective share is the SUM over paths of the PRODUCT of each
    path's dated link percentages. Replaces assert_effective_ownership_is_chain_product,
    which took one product over every link of a (group, entity) and so would have
    multiplied two paths into each other (shape 1: 0.8 x 0.6 x 0.2 = 0.096 instead of
    0.48 + 0.20 = 0.68).

    An independent oracle (PR #345 review, findings 1 and F3). It shares no macro with
    gold_entity_ownership: the period dates come straight from epm_staging.fiscal_periods,
    each link's Ownership Period is picked with argMax over a plain join (the model uses an
    ASOF join), each path is a product of exp(log) (the model uses arrayProduct), and every
    branch of the reading is checked, not skipped:

      the dates a period is read on, from the calendar source:
        Regular                 its declared start S and end E
        Closing                 its year's last Regular period's S and E
        Opening, Adjustment     E = end of the latest Regular period before it,
                                S = start of the earliest Regular period after it
                                (S > E: the period sits on a boundary between them)
      R = the later of S and E: the date a holding is read at. A link's Ownership Period
      is the latest one that started by R.
        held at R               it has not ended before R
        some path held at R     sum the held paths
        no path held at R       sum the paths whose links had not ended before S
                                (a full disposal inside the period: it stays in)
      a boundary period (S > E) counts only if some path was held at E, the eve of the
      boundary (an entity acquired on S is not in it); otherwise expect 0.

    A holding split exactly at a boundary (a step or an owner transfer dated on the first
    day of a year: konsol ends the old row the day before) is read at S, so it is never lost.
    Skipped: a (group, entity, period) with a link that has no Ownership Period at all
    (assert_ownership_chain_complete's case) or a zero link on a counted path (log(0)).

    Fixtures: assert_effective_ownership_is_path_sum.*.sql (direct_plus_indirect + .must_flag,
    indirect_associate, single_chain, owner_transfer, partial_sale, step_on_day_one,
    transfer_on_day_one), and every window fixture builds this test too.
#}

with calendar as (
    select
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        period_type,
        start_date,
        end_date
    from {{ source('epm_staging', 'fiscal_periods') }}
),

regular as (
    select fy as ry, fp as rfp, start_date as rs, end_date as re
    from calendar
    where period_type = 'Regular'
),

period_dates as (
    select
        c.fy as fy,
        c.fp as fp,
        multiIf(
            c.period_type = 'Regular', c.start_date,
            c.period_type = 'Closing' and countIf(r.ry = c.fy) > 0, argMaxIf(r.rs, r.rfp, r.ry = c.fy),
            countIf((r.ry, r.rfp) > (c.fy, c.fp)) > 0, argMinIf(r.rs, (r.ry, r.rfp), (r.ry, r.rfp) > (c.fy, c.fp)),
            addDays(c.end_date, 1)
        ) as s_date,
        multiIf(
            c.period_type = 'Regular', c.end_date,
            c.period_type = 'Closing' and countIf(r.ry = c.fy) > 0, argMaxIf(r.re, r.rfp, r.ry = c.fy),
            countIf((r.ry, r.rfp) < (c.fy, c.fp)) > 0, argMaxIf(r.re, (r.ry, r.rfp), (r.ry, r.rfp) < (c.fy, c.fp)),
            subtractDays(c.start_date, 1)
        ) as e_date
    from calendar as c
    cross join regular as r
    group by c.fy, c.fp, c.period_type, c.start_date, c.end_date
),

periods_needed as (
    select distinct
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        pd.s_date as s_date,
        pd.e_date as e_date,
        greatest(pd.s_date, pd.e_date) as r_date
    from {{ ref('gold_trial_balance') }} as tb
    inner join period_dates as pd
        on pd.fy = toUInt16(tb.fiscal_year)
        and pd.fp = toUInt16(tb.fiscal_period)
),

ownership as (
    select
        consolidation_group,
        data_area_id,
        owner_group,
        owner_data_area_id,
        effective_date,
        end_date,
        toFloat64(ownership_pct) as ownership_pct,
        toUInt8(1) as hit
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
        p.s_date as s_date,
        p.e_date as e_date,
        p.r_date as r_date
    from {{ source('epm_staging', 'consolidation_ancestry') }} as a
    cross join periods_needed as p
    where a.consolidation_group != '' and a.data_area_id != ''
),

{# one row per link and period; join_use_nulls=0: a link with no Ownership Period reads hit = 0 #}
link_reads as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.path_id as path_id,
        ap.fiscal_year as fiscal_year,
        ap.fiscal_period as fiscal_period,
        any(ap.s_date) as s_d,
        any(ap.e_date) as e_d,
        any(ap.r_date) as r_d,
        countIf(o.hit = 1) as n_rows,
        countIf(o.hit = 1 and o.effective_date <= ap.r_date) as n_r,
        argMaxIf(o.end_date, o.effective_date, o.hit = 1 and o.effective_date <= ap.r_date) as end_r,
        argMaxIf(o.ownership_pct, o.effective_date, o.hit = 1 and o.effective_date <= ap.r_date) as pct_r,
        countIf(o.hit = 1 and o.effective_date <= ap.e_date) as n_e,
        argMaxIf(o.end_date, o.effective_date, o.hit = 1 and o.effective_date <= ap.e_date) as end_e
    from ancestry_periods as ap
    left join ownership as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.link_owner_group = o.owner_group
        and ap.link_owner_data_area_id = o.owner_data_area_id
    group by ap.consolidation_group, ap.data_area_id, ap.path_id, ap.fiscal_year, ap.fiscal_period,
             ap.link_group, ap.link_data_area_id, ap.link_owner_group, ap.link_owner_data_area_id
),

path_reads as (
    select
        consolidation_group,
        data_area_id,
        path_id,
        fiscal_year,
        fiscal_period,
        max(s_d > e_d) as boundary,
        min(n_r > 0 and end_r >= r_d) as held_r,
        min(n_r > 0 and end_r >= s_d) as counted_s,
        min(n_e > 0 and end_e >= e_d) as held_e,
        max(n_rows = 0) as unrecorded,
        countIf(pct_r = 0) as zero_links,
        exp(sum(log(pct_r / 100.0))) as path_pct
    from link_reads
    group by consolidation_group, data_area_id, path_id, fiscal_year, fiscal_period
),

oracle as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        max(boundary) as is_boundary,
        max(held_r) as any_held,
        max(held_e) as any_held_before,
        max(unrecorded) as any_unrecorded,
        sumIf(path_pct, held_r = 1) as held_sum,
        sumIf(path_pct, counted_s = 1) as counted_sum,
        sumIf(zero_links, held_r = 1) as held_zero,
        sumIf(zero_links, counted_s = 1) as counted_zero
    from path_reads
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

expected as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        multiIf(
            is_boundary = 1 and any_held_before = 0, 0.0,
            any_held = 1, held_sum,
            counted_sum
        ) as expected_pct,
        multiIf(
            is_boundary = 1 and any_held_before = 0, 'boundary, not held before it',
            any_held = 1, 'held at the read date',
            'ended inside the period'
        ) as branch,
        any_unrecorded,
        if(any_held = 1, held_zero, counted_zero) as zero_links
    from oracle
)

select
    eo.consolidation_group,
    eo.data_area_id,
    eo.fiscal_year,
    eo.fiscal_period,
    eo.effective_ownership_pct as model_pct,
    x.expected_pct as expected_pct,
    x.branch as branch
from {{ ref('gold_entity_ownership') }} as eo
inner join expected as x
    on eo.consolidation_group = x.consolidation_group
    and eo.data_area_id = x.data_area_id
    and eo.fiscal_year = x.fiscal_year
    and eo.fiscal_period = x.fiscal_period
where x.any_unrecorded = 0
  and x.zero_links = 0
  and abs(eo.effective_ownership_pct - x.expected_pct) > 0.000001
