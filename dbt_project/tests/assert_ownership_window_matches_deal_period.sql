{# konsolidat#171 / #252 / #278 (task 2b): the ownership window and the deal journals put a deal in the
   SAME period.

   gold_business_combination_journal posts an acquisition, and gold_business_disposal_journal a full
   disposal, in the Regular period whose declared span holds the deal date (deal_period_holds(), the one
   mapping rule; the lowest period tuple). The test checks the journals against that rule too: a journal
   posted in any other period is named ('journal posts in another period'), so the journals, the window and
   this test cannot use different rules. The acquisition
   journal's line (0) brings the balance sheet in up to the period BEFORE that one, so the entity's own
   movements must be consolidated from the acquisition period on. The disposal journal's line (0)
   derecognises the cumulative balances UP TO AND INCLUDING the disposal period, so the entity's movements
   must be consolidated up to and including the disposal period, and not after it.

   The expectation is computed here from the calendar source, by the journals' own span rule, and never
   through the window's macros. A Closing period is compared as its year's last Regular period (the rule
   rate_period_map() declares for rates): a year-end close posts in it, and it is consolidated exactly when
   that last Regular period is. Opening and Adjustment periods are compared by their own tuple, as the
   disposal journal's line (0) compares them: an Opening P0 is before P1, an Adjustment P14 after P12.

   Faults, one row each:
     acquisition period not consolidated   the entity has trial-balance rows in the acquisition period
                                           and gold_consolidated_trial_balance has none (#278: a deal
                                           dated 2024-06-15 lost June because the window was judged on
                                           1 June)
     consolidated before acquisition       consolidated rows in a period before the acquisition period,
                                           when no Ownership Period of the entity starts before the deal
     disposal period not consolidated      the entity has trial-balance rows in the disposal period and
                                           the consolidated trial balance has none (the journal would
                                           derecognise balances the group never carried)
     consolidated after disposal           consolidated rows in a period after the disposal period, when
                                           no later Business Combination re-acquires the entity
     journal posts in another period       a deal journal posted in a period other than the one
                                           deal_period_holds() gives its date
   Fixtures: assert_ownership_window_matches_deal_period.*.sql. #}
with calendar as (
    select
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        start_date,
        end_date,
        period_type
    from {{ source('epm_staging', 'fiscal_periods') }}
),

{# a Closing period compares as its year's last Regular period #}
last_regular as (
    select fy, max(fp) as last_fp
    from calendar
    where period_type = 'Regular'
    group by fy
),

compare_key as (
    select
        c.fy as fy,
        c.fp as fp,
        if(c.period_type = 'Closing' and lr.last_fp > 0, lr.last_fp, c.fp) as cmp_fp
    from calendar as c
    left join last_regular as lr
        on lr.fy = c.fy
),

acquisitions as (
    select
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as data_area_id,
        bc.acquisition_date as deal_date,
        argMin(c.fy, (c.fy, c.fp)) as fy,
        argMin(c.fp, (c.fy, c.fp)) as fp
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join calendar as c
    where {{ deal_period_holds('c', 'bc.acquisition_date') }}
    group by bc.consolidation_group, bc.acquired_entity, bc.acquisition_date
),

disposals as (
    select
        bd.consolidation_group as consolidation_group,
        bd.disposed_entity as data_area_id,
        bd.disposal_date as deal_date,
        argMin(c.fy, (c.fy, c.fp)) as fy,
        argMin(c.fp, (c.fy, c.fp)) as fp
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join calendar as c
    where {{ deal_period_holds('c', 'bd.disposal_date') }}
      and toFloat64(bd.retained_interest_pct) <= 0.0
    group by bd.consolidation_group, bd.disposed_entity, bd.disposal_date
),

consolidated as (
    select distinct
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        toUInt16(ctb.fiscal_year) as fy,
        toUInt16(ctb.fiscal_period) as fp,
        k.cmp_fp as cmp_fp
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join compare_key as k
        on k.fy = toUInt16(ctb.fiscal_year)
        and k.fp = toUInt16(ctb.fiscal_period)
),

entity_periods as (
    select distinct
        data_area_id,
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp
    from {{ ref('gold_trial_balance') }}
),

{# deals whose entity was held before the deal date (a step acquisition, or an earlier holding): the
   periods before the deal may be consolidated on their own right #}
held_before as (
    select a.consolidation_group, a.data_area_id, a.deal_date
    from acquisitions as a
    inner join {{ source('epm_staging', 'ownership_periods') }} as op
        on op.consolidation_group = a.consolidation_group
        and op.data_area_id = a.data_area_id
    where op.effective_date < a.deal_date
),

{# the period each deal journal actually posted in #}
journal_periods as (
    select
        consolidation_group,
        data_area_id,
        acquisition_date as deal_date,
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        'acquisition' as kind
    from {{ ref('gold_business_combination_journal') }}
    group by consolidation_group, data_area_id, acquisition_date, fiscal_year, fiscal_period

    union all

    select
        consolidation_group,
        data_area_id,
        disposal_date as deal_date,
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        'disposal' as kind
    from {{ ref('gold_business_disposal_journal') }}
    group by consolidation_group, data_area_id, disposal_date, fiscal_year, fiscal_period
),

deal_periods as (
    select consolidation_group, data_area_id, deal_date, fy, fp, 'acquisition' as kind from acquisitions
    union all
    select consolidation_group, data_area_id, deal_date, fy, fp, 'disposal' as kind from disposals
),

{# disposals followed by a re-acquisition of the same entity in the same group #}
reacquired as (
    select d.consolidation_group, d.data_area_id, d.deal_date
    from disposals as d
    inner join {{ source('epm_staging', 'business_combinations') }} as bc
        on bc.consolidation_group = d.consolidation_group
        and bc.acquired_entity = d.data_area_id
    where bc.acquisition_date > d.deal_date
)

select
    a.consolidation_group as consolidation_group,
    a.data_area_id as data_area_id,
    a.deal_date as deal_date,
    a.fy as fiscal_year,
    a.fp as fiscal_period,
    'acquisition period not consolidated' as fault
from acquisitions as a
inner join entity_periods as ep
    on ep.data_area_id = a.data_area_id
    and ep.fy = a.fy
    and ep.fp = a.fp
where (a.consolidation_group, a.data_area_id, a.fy, a.fp) not in (
    select consolidation_group, data_area_id, fy, fp from consolidated
)

union all

select
    a.consolidation_group,
    a.data_area_id,
    a.deal_date,
    c.fy,
    c.fp,
    'consolidated before acquisition'
from acquisitions as a
inner join consolidated as c
    on c.consolidation_group = a.consolidation_group
    and c.data_area_id = a.data_area_id
where (c.fy, c.cmp_fp) < (a.fy, a.fp)
  and (a.consolidation_group, a.data_area_id, a.deal_date) not in (
      select consolidation_group, data_area_id, deal_date from held_before
  )

union all

select
    d.consolidation_group,
    d.data_area_id,
    d.deal_date,
    d.fy,
    d.fp,
    'disposal period not consolidated'
from disposals as d
inner join entity_periods as ep
    on ep.data_area_id = d.data_area_id
    and ep.fy = d.fy
    and ep.fp = d.fp
where (d.consolidation_group, d.data_area_id, d.fy, d.fp) not in (
    select consolidation_group, data_area_id, fy, fp from consolidated
)

union all

select
    d.consolidation_group,
    d.data_area_id,
    d.deal_date,
    c.fy,
    c.fp,
    'consolidated after disposal'
from disposals as d
inner join consolidated as c
    on c.consolidation_group = d.consolidation_group
    and c.data_area_id = d.data_area_id
where (c.fy, c.cmp_fp) > (d.fy, d.fp)
  and (d.consolidation_group, d.data_area_id, d.deal_date) not in (
      select consolidation_group, data_area_id, deal_date from reacquired
  )

union all

select
    j.consolidation_group,
    j.data_area_id,
    j.deal_date,
    j.fy,
    j.fp,
    concat('journal posts in another period (', j.kind, ')')
from journal_periods as j
where (j.consolidation_group, j.data_area_id, j.deal_date, j.kind, j.fy, j.fp) not in (
    select consolidation_group, data_area_id, deal_date, kind, fy, fp from deal_periods
)
