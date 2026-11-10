{#
    konsol#117: the effective share is the SUM over paths of the PRODUCT of each
    path's dated link percentages. Replaces assert_effective_ownership_is_chain_product,
    which took one product over every link of a (group, entity) and so would have
    multiplied two paths into each other (shape 1: 0.8 x 0.6 x 0.2 = 0.096 instead of
    0.48 + 0.20 = 0.68).

    An independent oracle (PR #345 reviews). It shares no macro with gold_entity_ownership:
    the period dates come straight from epm_staging.fiscal_periods, the disposals straight
    from epm_staging.business_disposals, each link's Ownership Period is picked with ONE
    argMaxIf over a plain join (the model uses an ASOF join), so its end date, share and
    method come from the same row, and each path is a product of exp(log) (the model uses
    arrayProduct). The rule, restated:

      the dates a period is read on, from the calendar source:
        Regular                 its declared start S and end E
        Closing                 its year's last Regular period's S and E
        Opening, Adjustment     E = end of the latest Regular period before it,
                                S = start of the earliest Regular period after it:
                                a BOUNDARY period (S > E), between two Regular periods
      A link's Ownership Period is the latest one that started by E.
        held at E               it has not ended before E; and, in a boundary period,
                                it was not ended by a disposal: a full disposal
                                (retained interest 0, as gold_business_disposal_journal
                                posts it) of the entity in the group, dated on its end
                                date. A boundary period carries the state of the
                                period before it: a change dated E + 1 posts in the
                                next Regular period and is not seen yet, a disposal
                                dated on or before E has already been derecognised.
        some path held at E     sum the held paths
        no path held at E       sum the paths whose links had not ended before S
                                (a full disposal inside a Regular period stays in it)
      For a (group, entity, period) reached by exactly one counted path, the method is
      that path's weakest link (full < proportional < equity < anything else).

    Fails loudly, never silently: a trial-balance period the calendar gives no dates
    (its year, and every other, has no Regular period to read it against) is a row
    ('no Regular period to read the period on'). assert_trial_balance_period_declared
    only checks that the period is declared, not that a Regular period exists.
    Skipped: a (group, entity, period) with a link that has no Ownership Period at all
    (assert_ownership_chain_complete's case) or a zero link on a counted path (log(0)).

    Fixtures: assert_effective_ownership_is_path_sum.*.sql, and every window fixture
    builds this test too.
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

tb_periods as (
    select distinct
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp
    from {{ ref('gold_trial_balance') }}
),

periods_needed as (
    select
        tp.fy as fy,
        tp.fp as fp,
        pd.s_date as s_date,
        pd.e_date as e_date
    from tb_periods as tp
    inner join period_dates as pd
        on pd.fy = tp.fy
        and pd.fp = tp.fp
),

ownership as (
    select
        o.consolidation_group as consolidation_group,
        o.data_area_id as data_area_id,
        o.owner_group as owner_group,
        o.owner_data_area_id as owner_data_area_id,
        o.effective_date as effective_date,
        o.end_date as end_date,
        toFloat64(o.ownership_pct) as ownership_pct,
        o.consolidation_method as consolidation_method,
        toUInt8((o.consolidation_group, o.data_area_id, o.end_date) in (
            select consolidation_group, disposed_entity, disposal_date
            from {{ source('epm_staging', 'business_disposals') }}
            where toFloat64(retained_interest_pct) <= 0.0
        )) as ended_by_disposal,
        toUInt8(1) as hit
    from {{ source('epm_staging', 'ownership_periods') }} as o
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
        p.fy as fy,
        p.fp as fp,
        p.s_date as s_date,
        p.e_date as e_date
    from {{ source('epm_staging', 'consolidation_ancestry') }} as a
    cross join periods_needed as p
    where a.consolidation_group != '' and a.data_area_id != ''
),

{# one row per link and period: the ONE Ownership Period read (the latest started by E); join_use_nulls=0, so a
   link with no Ownership Period reads hit = 0 #}
link_reads as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.path_id as path_id,
        ap.fy as fy,
        ap.fp as fp,
        any(ap.s_date) as s_d,
        any(ap.e_date) as e_d,
        countIf(o.hit = 1) as n_rows,
        countIf(o.hit = 1 and o.effective_date <= ap.e_date) as n_read,
        argMaxIf(
            (o.end_date, o.ownership_pct, o.consolidation_method, o.ended_by_disposal),
            o.effective_date,
            o.hit = 1 and o.effective_date <= ap.e_date
        ) as read_row
    from ancestry_periods as ap
    left join ownership as o
        on ap.link_group = o.consolidation_group
        and ap.link_data_area_id = o.data_area_id
        and ap.link_owner_group = o.owner_group
        and ap.link_owner_data_area_id = o.owner_data_area_id
    group by ap.consolidation_group, ap.data_area_id, ap.path_id, ap.fy, ap.fp,
             ap.link_group, ap.link_data_area_id, ap.link_owner_group, ap.link_owner_data_area_id
),

link_states as (
    select
        consolidation_group,
        data_area_id,
        path_id,
        fy,
        fp,
        n_rows,
        tupleElement(read_row, 2) as link_pct,
        multiIf(
            tupleElement(read_row, 3) = 'full', 1,
            tupleElement(read_row, 3) = 'proportional', 2,
            tupleElement(read_row, 3) = 'equity', 3,
            4
        ) as link_rank,
        toUInt8(n_read > 0 and tupleElement(read_row, 1) >= e_d
                and not (s_d > e_d and tupleElement(read_row, 4) = 1)) as held_e,
        toUInt8(n_read > 0 and tupleElement(read_row, 1) >= s_d) as counted_s
    from link_reads
),

path_reads as (
    select
        consolidation_group,
        data_area_id,
        path_id,
        fy,
        fp,
        min(held_e) as path_held,
        min(counted_s) as path_counted,
        max(n_rows = 0) as unrecorded,
        countIf(link_pct = 0) as zero_links,
        max(link_rank) as path_rank,
        exp(sum(log(link_pct / 100.0))) as path_pct
    from link_states
    group by consolidation_group, data_area_id, path_id, fy, fp
),

oracle as (
    select
        consolidation_group,
        data_area_id,
        fy,
        fp,
        max(path_held) as any_held,
        max(unrecorded) as any_unrecorded,
        sumIf(path_pct, path_held = 1) as held_sum,
        sumIf(path_pct, path_counted = 1) as counted_sum,
        sumIf(zero_links, path_held = 1) as held_zero,
        sumIf(zero_links, path_counted = 1) as counted_zero,
        countIf(path_held = 1) as n_held,
        countIf(path_counted = 1) as n_counted,
        anyIf(path_rank, path_held = 1) as held_rank,
        anyIf(path_rank, path_counted = 1) as counted_rank
    from path_reads
    group by consolidation_group, data_area_id, fy, fp
),

expected as (
    select
        consolidation_group,
        data_area_id,
        fy,
        fp,
        if(any_held = 1, held_sum, counted_sum) as expected_pct,
        if(any_held = 1, 'held at E', 'ended inside the period') as branch,
        any_unrecorded,
        if(any_held = 1, held_zero, counted_zero) as zero_links,
        if(any_held = 1, n_held, n_counted) as n_paths,
        multiIf(
            if(any_held = 1, held_rank, counted_rank) = 1, 'full',
            if(any_held = 1, held_rank, counted_rank) = 2, 'proportional',
            if(any_held = 1, held_rank, counted_rank) = 3, 'equity',
            'none'
        ) as expected_method
    from oracle
)

select
    eo.consolidation_group as consolidation_group,
    eo.data_area_id as data_area_id,
    toUInt16(eo.fiscal_year) as fiscal_year,
    toUInt16(eo.fiscal_period) as fiscal_period,
    eo.effective_ownership_pct as model_pct,
    x.expected_pct as expected_pct,
    concat(x.branch, if(abs(eo.effective_ownership_pct - x.expected_pct) > 0.000001, '', ': method ')) as fault
from {{ ref('gold_entity_ownership') }} as eo
inner join expected as x
    on eo.consolidation_group = x.consolidation_group
    and eo.data_area_id = x.data_area_id
    and toUInt16(eo.fiscal_year) = x.fy
    and toUInt16(eo.fiscal_period) = x.fp
where x.any_unrecorded = 0
  and x.zero_links = 0
  and (
        abs(eo.effective_ownership_pct - x.expected_pct) > 0.000001
        {# one counted path: the method is its weakest link (the model's 'link' rule) #}
        or (x.n_paths = 1 and x.expected_pct > 0 and eo.method_source = 'link'
            and eo.consolidation_method != x.expected_method)
  )

union all

select
    '' as consolidation_group,
    '' as data_area_id,
    tp.fy as fiscal_year,
    tp.fp as fiscal_period,
    0.0 as model_pct,
    0.0 as expected_pct,
    'no Regular period to read the period on' as fault
from tb_periods as tp
where (tp.fy, tp.fp) in (select fy, fp from calendar)
  and (tp.fy, tp.fp) not in (select fy, fp from period_dates)
