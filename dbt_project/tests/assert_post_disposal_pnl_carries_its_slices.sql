{# konsolidat#245 Q2 A, decided by Deepak Pai on 21 Nov 2026: disposal line 105 (post_disposal_pnl, the
   entity's P&L after the disposal date) INHERITS the dimension slices of the P&L it removes, the same as
   pnl_proration. It extends the 3 Oct 2026 rule "inherit where derivable": line 105 is the entity's P&L by
   account times the removed fraction, the derivation pnl_proration already slices. Rejected: B, keep it
   blank under the deal-journal rule, which leaves the post-disposal P&L in each segment and offsets it only on
   the blank slice, so segment P&L is overstated by exactly that amount.

   Judged on gold_fully_consolidated_tb, where segment P&L is read, per (group, entity, year, period, P&L
   account, slice):
       expected = -group_amount of that slice in gold_consolidated_trial_balance x removed_fraction
       modelled = the 'disposal' layer on that account and slice, less the journal's gain_loss line (199),
                  which is blank and is the only other disposal line a P&L account can carry
   removed_fraction is re-derived from the sources exactly as assert_partial_period_pnl_matches_treatment
   derives it (days after the disposal date to the period end, over the period's days; the deal period is
   the lowest Regular tuple whose span holds the date), so the model and this test cannot share a mistake.
   Only groups whose root declares 'Pro-rate by days' and full disposals the journal posted are judged;
   that sibling test judges the account totals and every other treatment.

   On the base, a revenue of -3,000 on two cost centres (-1,800 / -1,200), disposed on the 20th of a 30-day
   period, posted +1,000 on the blank slice: each cost centre kept its whole P&L. A difference of more than
   0.01 on any slice is one row.

   Error severity: a segment carrying P&L the group did not hold is a wrong consolidated number that every
   account total accepts. #}
{% set dims = var('dimensions') %}
with calendar as (
    select
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        start_date,
        end_date
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
),

treatment as (
    select
        consolidation_group,
        any(partial_period_treatment) as partial_period_treatment
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

disposals as (
    select
        bd.consolidation_group as consolidation_group,
        bd.disposed_entity as data_area_id,
        argMin(c.fy, (c.fy, c.fp)) as fy,
        argMin(c.fp, (c.fy, c.fp)) as fp,
        argMin(c.start_date, (c.fy, c.fp)) as period_start,
        argMin(c.end_date, (c.fy, c.fp)) as period_end,
        bd.disposal_date as deal_date
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join calendar as c
    where c.start_date <= bd.disposal_date
      and c.end_date >= bd.disposal_date
      and toFloat64(bd.retained_interest_pct) <= 0.0
      and (bd.consolidation_group, bd.disposed_entity, c.fy, c.fp) in (
          select consolidation_group, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period)
          from {{ ref('gold_business_disposal_journal') }}
      )
      and bd.consolidation_group in (
          select consolidation_group from treatment where partial_period_treatment = 'Pro-rate by days'
      )
    group by bd.consolidation_group, bd.disposed_entity, bd.disposal_date
),

deals as (
    select
        consolidation_group, data_area_id, fy, fp,
        if(deal_date < period_end,
           toFloat64(dateDiff('day', deal_date, period_end)) / (dateDiff('day', period_start, period_end) + 1),
           0.0) as removed_fraction
    from disposals
),

pnl_accounts as (
    select main_account_id from {{ ref('silver_main_accounts') }} where is_pnl = 1
),

expected as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        toUInt16(ctb.fiscal_year) as fy,
        toUInt16(ctb.fiscal_period) as fp,
        ctb.main_account as main_account,
        {{ dim_select(prefix='ctb.', trailing=true) }}
        -(sum(coalesce(ctb.group_amount, 0.0)) * any(d.removed_fraction)) as expected_amount,
        0.0 as model_amount
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join deals as d
        on d.consolidation_group = ctb.consolidation_group
        and d.data_area_id = ctb.data_area_id
        and d.fy = toUInt16(ctb.fiscal_year)
        and d.fp = toUInt16(ctb.fiscal_period)
    where ctb.is_pnl = 1
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period, ctb.main_account
             {{ dim_group_by(prefix='ctb.', leading=true) }}
),

modelled as (
    select
        consolidation_group,
        data_area_id,
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        main_account,
        {{ dim_select(trailing=true) }}
        0.0 as expected_amount,
        toFloat64(amount) as model_amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type = 'disposal'
      and main_account in (select main_account_id from pnl_accounts)
      and (consolidation_group, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period)) in (
          select consolidation_group, data_area_id, fy, fp from deals
      )

    union all

    {# the gain or loss (199) is the journal's counterpart, blank by decision; take it out of the blank slice #}
    select
        consolidation_group,
        data_area_id,
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp,
        main_account,
        {{ dim_empty_strings(trailing=true) }}
        0.0 as expected_amount,
        -toFloat64(adjustment_amount) as model_amount
    from {{ ref('gold_business_disposal_journal') }}
    where account_role = 'gain_loss'
      and main_account in (select main_account_id from pnl_accounts)
      and (consolidation_group, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period)) in (
          select consolidation_group, data_area_id, fy, fp from deals
      )
),

compared as (
    select
        consolidation_group, data_area_id, fy, fp, main_account,
        {{ dim_select(trailing=true) }}
        sum(expected_amount) as expected_total,
        sum(model_amount) as model_total
    from (
        select * from expected
        union all
        select * from modelled
    )
    group by consolidation_group, data_area_id, fy, fp, main_account
             {{ dim_group_by(leading=true) }}
)

select
    consolidation_group,
    data_area_id,
    fy as fiscal_year,
    fp as fiscal_period,
    main_account,
    {{ dim_select(trailing=true) }}
    expected_total as expected_amount,
    model_total as model_amount
from compared
where abs(model_total - expected_total) > 0.01
