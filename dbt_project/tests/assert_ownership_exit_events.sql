{#
    konsolidat#335, option A (Deepak Pai, 14 Nov 2026), task X1: the exit events of macros/ownership_exits().

    An exit event (G, E, P): E is live in G (complete chain, method full, proportional or equity) in the
    previous declared period, is not live in P, and was not ended by a full Business Disposal. A successor
    period or an owner-to-owner transfer keeps E live, so it is not an exit (konsol#305-Q1-1).

    One check, one row per failure. ORACLE: for every entity whose chain is a single direct link (no
    sub-group above it) the exit events are recomputed here from epm_staging.ownership_periods, business_disposals and the fiscal
    calendar directly, never through ownership_resolution or declared_periods(): the window dates
    (Regular, Closing = its year's last Regular, Opening/Adjustment = between two Regulars), the
    held-at-end then not-ended-before-the-start reading, and the previous declared period. An event
    the macro has and the oracle has not, or the other way, is a row. Oracle limit: it reads one link
    per entity, so a chain with an owner above is outside it.
#}

with cal as (
    select toUInt16(fiscal_year) as cfy, toUInt16(fiscal_period) as cfp,
      any(period_type) as cty, min(start_date) as cs, max(end_date) as ce
    from {{ source('epm_staging', 'fiscal_periods') }}
    group by cfy, cfp
),

regs as (
    select cfy as rfy, cfp as rfp, cs as rs, ce as re from cal where cty = 'Regular'
),

win_raw as (
    select
        c.cfy as wfy, c.cfp as wfp, c.cty as wty, c.cs as wcs, c.ce as wce,
        countIf((r.rfy, r.rfp) < (c.cfy, c.cfp)) as n_before,
        argMaxIf(r.re, (r.rfy, r.rfp), (r.rfy, r.rfp) < (c.cfy, c.cfp)) as end_before,
        countIf((r.rfy, r.rfp) > (c.cfy, c.cfp)) as n_after,
        argMinIf(r.rs, (r.rfy, r.rfp), (r.rfy, r.rfp) > (c.cfy, c.cfp)) as start_after,
        countIf(r.rfy = c.cfy) as n_year,
        argMaxIf(r.rs, r.rfp, r.rfy = c.cfy) as year_last_start,
        argMaxIf(r.re, r.rfp, r.rfy = c.cfy) as year_last_end
    from cal as c
    cross join regs as r
    group by c.cfy, c.cfp, c.cty, c.cs, c.ce
),

win as (
    select
        wfy, wfp,
        multiIf(wty = 'Regular', wcs, wty = 'Closing' and n_year > 0, year_last_start,
           n_after > 0, start_after, addDays(wce, 1)) as ws,
        multiIf(wty = 'Regular', wce, wty = 'Closing' and n_year > 0, year_last_end,
           n_before > 0, end_before, subtractDays(wcs, 1)) as we
    from win_raw
),

links as (
    select consolidation_group as g, data_area_id as ent, link_group, link_data_area_id,
      link_owner_group, link_owner_data_area_id
    from {{ source('epm_staging', 'consolidation_ancestry') }}
    where depth = 1 and link_depth = 1 and consolidation_group != ''
      and (consolidation_group, data_area_id) not in (
     select consolidation_group, data_area_id
     from {{ source('epm_staging', 'consolidation_ancestry') }}
     where depth > 1
      )
),

own as (
    select
        consolidation_group as og, data_area_id as oe, owner_group as oog, owner_data_area_id as ooe,
        effective_date as o_from, end_date as o_to, consolidation_method as o_method,
        toUInt8(is_disposal = 1 and (consolidation_group, data_area_id, end_date) in (
       select consolidation_group, disposed_entity, disposal_date
       from {{ source('epm_staging', 'business_disposals') }}
       where toFloat64(retained_interest_pct) <= 0.0
        )) as o_disposed
    from {{ source('epm_staging', 'ownership_periods') }}
),

live as (
    select
        l.g as lg, l.ent as le, w.wfy as lfy, w.wfp as lfp, w.ws as lws, w.we as lwe,
        toUInt8(
       maxIf(1, o.o_from <= w.we and o.o_to >= w.we and o.o_method in ('full', 'proportional', 'equity')
                and not (w.ws > w.we and o.o_to = w.we and o.o_disposed = 1))
       or maxIf(1, o.o_from <= w.we and o.o_to >= w.ws and o.o_method in ('full', 'proportional', 'equity'))
        ) as is_live
    from links as l
    cross join win as w
    left join own as o
        on o.og = l.link_group and o.oe = l.link_data_area_id
        and o.oog = l.link_owner_group and o.ooe = l.link_owner_data_area_id
    group by l.g, l.ent, w.wfy, w.wfp, w.ws, w.we
),

chained as (
    select
        *,
        lagInFrame(is_live, 1, toUInt8(0)) over w2 as p_live,
        lagInFrame(lfy, 1, toUInt16(0)) over w2 as p_fy,
        lagInFrame(lfp, 1, toUInt16(0)) over w2 as p_fp,
        lagInFrame(lws, 1, toDate('1970-01-01')) over w2 as p_ws,
        lagInFrame(lwe, 1, toDate('1970-01-01')) over w2 as p_we
    from live
    window w2 as (partition by lg, le order by lfy, lfp rows between unbounded preceding and current row)
),

candidates as (
    select lg, le, lfy, lfp, lwe, p_fy, p_fp, least(p_ws, p_we) as p_from
    from chained
    where is_live = 0 and p_live = 1
),

oracle as (
    select c.lg as g, c.le as ent, c.lfy as fy, c.lfp as fp, c.p_fy as pfy, c.p_fp as pfp
    from candidates as c
    left join (
        select l.g as dg, l.ent as de, o.o_to as d_end
        from links as l
        inner join own as o
       on o.og = l.link_group and o.oe = l.link_data_area_id
       and o.oog = l.link_owner_group and o.ooe = l.link_owner_data_area_id
        where o.o_disposed = 1
    ) as d
        on d.dg = c.lg and d.de = c.le
    group by c.lg, c.le, c.lfy, c.lfp, c.p_fy, c.p_fp, c.p_from, c.lwe
    {# ended by a full disposal inside the window of the exit; join_use_nulls=0: a miss reads d_end = 1970-01-01 #}
    having countIf(d.dg != '' and d.d_end >= c.p_from and d.d_end < c.lwe) = 0
),

macro as (
    select consolidation_group as g, data_area_id as ent, fiscal_year as fy, fiscal_period as fp,
      previous_fiscal_year as pfy, previous_fiscal_period as pfp, end_date as ended
    from {{ ownership_exits() }}
)

select 'macro event the oracle does not have' as problem, concat(g, ' ', ent, ' FY', toString(fy), ' P', toString(fp)) as event
from macro
where (g, ent) in (select g, ent from links)
  and (g, ent, fy, fp, pfy, pfp) not in (select g, ent, fy, fp, pfy, pfp from oracle)

union all
select 'oracle event the macro does not have', concat(g, ' ', ent, ' FY', toString(fy), ' P', toString(fp))
from oracle
where (g, ent, fy, fp, pfy, pfp) not in (select g, ent, fy, fp, pfy, pfp from macro)
