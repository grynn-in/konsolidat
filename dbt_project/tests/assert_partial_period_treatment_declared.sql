{# konsolidat#171 step 2c. Decisions: Deepak Pai, 18 Sep 2026 (mid-period P&L follows the group root's declared
   partial_period_treatment: Whole period | Pro-rate by days | Stub trial balance; no default, required once a
   business combination exists) and 10 Nov 2026 Q1 A (an undeclared treatment with a mid-period deal is a build
   ERROR naming the group and the deal, never a silent default).

   One row per submitted business combination, or full disposal (retained_interest_pct <= 0), that falls
   mid-period and whose group root row (epm_gold.consolidation_groups, data_area_id = '') does not carry one
   of the three exact values: blank, no root row, or a typo such as 'Pro rata'. The deal period is the Regular
   period deal_period_holds() gives (lowest tuple, as both deal journals pick it). Mid-period: an acquisition
   dated after the period's start_date; a full disposal dated before the period's end_date. A deal on the first
   day (acquisition) or last day (disposal) is a whole-period deal and needs no treatment. A partial disposal
   (control retained) is out of scope. A date no Regular period holds is not judged here:
   assert_acquisition_accounts_declared already names it.

   Fixtures: dbt_project/test_fixtures/assert_partial_period_treatment_declared.must_flag.sql (flags 3) and
   assert_partial_period_treatment_declared.sql (all three declared, passes). #}
with deals as (
    select
        bc.consolidation_group as consolidation_group,
        bc.name as deal,
        'Business Combination' as deal_type,
        bc.acquisition_date as deal_date,
        fp.fiscal_year as fiscal_year,
        fp.fiscal_period as fiscal_period,
        fp.start_date as start_date,
        fp.end_date as end_date,
        'acquisition after the first day of the period' as reason
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where {{ deal_period_holds('fp', 'bc.acquisition_date') }}
      and bc.acquisition_date > fp.start_date

    union all

    select
        bd.consolidation_group as consolidation_group,
        bd.name as deal,
        'Business Disposal' as deal_type,
        bd.disposal_date as deal_date,
        fp.fiscal_year as fiscal_year,
        fp.fiscal_period as fiscal_period,
        fp.start_date as start_date,
        fp.end_date as end_date,
        'full disposal before the last day of the period' as reason
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where {{ deal_period_holds('fp', 'bd.disposal_date') }}
      and toFloat64(bd.retained_interest_pct) <= 0.0
      and bd.disposal_date < fp.end_date
),

{# the first (lowest) Regular period per deal, as the journals take it #}
deal_period as (
    select
        consolidation_group,
        deal,
        any(deal_type) as deal_type,
        any(deal_date) as deal_date,
        min((fiscal_year, fiscal_period)) as fy_fp,
        any(reason) as reason
    from deals
    group by consolidation_group, deal
),

deal_span as (
    select
        d.consolidation_group as consolidation_group,
        d.deal as deal,
        d.deal_type as deal_type,
        d.deal_date as deal_date,
        d.fy_fp.1 as fiscal_year,
        d.fy_fp.2 as fiscal_period,
        min(x.start_date) as start_date,
        max(x.end_date) as end_date,
        d.reason as reason
    from deal_period as d
    inner join deals as x
        on x.deal = d.deal and x.consolidation_group = d.consolidation_group
        and x.fiscal_year = d.fy_fp.1 and x.fiscal_period = d.fy_fp.2
    group by d.consolidation_group, d.deal, d.deal_type, d.deal_date, d.fy_fp, d.reason
),

{# the group's root row, any() per column so a duplicated root cannot fan out (as the disposal journal) #}
root as (
    select
        consolidation_group,
        any(partial_period_treatment) as declared_value
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
)

select
    s.consolidation_group as consolidation_group,
    s.deal as deal,
    s.deal_type as deal_type,
    s.deal_date as deal_date,
    s.fiscal_year as fiscal_year,
    s.fiscal_period as fiscal_period,
    s.start_date as start_date,
    s.end_date as end_date,
    r.declared_value as declared_value,
    concat(s.reason, '; partial_period_treatment is not Whole period, Pro-rate by days or Stub trial balance') as reason
from deal_span as s
left join root as r on r.consolidation_group = s.consolidation_group
where r.declared_value not in ('Whole period', 'Pro-rate by days', 'Stub trial balance')
