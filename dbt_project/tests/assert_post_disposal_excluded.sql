-- PRD-12 Test: Post-disposal periods must have zero ownership (entity excluded)
-- When temporal ownership records a disposal, no consolidated TB rows should exist
-- for that entity in periods after the disposal
{# konsolidat#171 / #252: "after the disposal" means after the period whose DECLARED span holds the
   disposal date (epm_staging.fiscal_periods, Closing periods skipped, the lowest period tuple), the rule
   gold_business_disposal_journal posts by. Before, this test judged fiscal period P at the first of
   calendar month P, the same macro the model used. The disposal period itself is consolidated: the
   disposal journal derecognises the balances through it. A Closing period compares as its year's last
   Regular period. #}
with calendar as (
    select
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        start_date,
        end_date,
        period_type
    from {{ source('epm_staging', 'fiscal_periods') }}
),

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

disposal_period as (
    select
        op.consolidation_group as consolidation_group,
        op.data_area_id as data_area_id,
        op.disposal_date as disposal_date,
        argMin(c.fy, (c.fy, c.fp)) as fy,
        argMin(c.fp, (c.fy, c.fp)) as fp
    from {{ source('epm_staging', 'ownership_periods') }} as op
    cross join calendar as c
    where op.is_disposal = 1
      and c.start_date <= op.disposal_date
      and c.end_date >= op.disposal_date
      and c.period_type != 'Closing'
    group by op.consolidation_group, op.data_area_id, op.disposal_date
)

select
    ctb.consolidation_group,
    ctb.data_area_id,
    ctb.fiscal_year,
    ctb.fiscal_period,
    ctb.ownership_pct
from {{ ref('gold_consolidated_trial_balance') }} as ctb
inner join compare_key as k
    on k.fy = toUInt16(ctb.fiscal_year)
    and k.fp = toUInt16(ctb.fiscal_period)
inner join disposal_period as dp
    on ctb.consolidation_group = dp.consolidation_group
    and ctb.data_area_id = dp.data_area_id
where (k.fy, k.cmp_fp) > (dp.fy, dp.fp)
  and ctb.ownership_pct > 0
limit 10
