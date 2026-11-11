{# konsolidat#171 step 2c (T4): mid-period profit and loss follows the treatment the group root declares.
   Decided by Deepak Pai: 18 Sep 2026 (mid-period P&L follows partial_period_treatment: Whole period |
   Pro-rate by days | Stub trial balance), 10 Nov 2026 Q2 C (the disposal period is inside the window and its
   P&L follows the treatment too, IFRS 10.B88).

   The expectation is computed here from the sources, never through partial_period_removed_fraction() or
   deal_period_holds(): the deal's Regular period is re-derived from epm_staging.fiscal_periods (the lowest
   tuple whose declared span holds the date), so the model and this test cannot share a mistake.

   Sign convention: an adjustment is ADDED to the consolidated amount, so it removes the share of the
   period that the group did not hold:
       adjustment = -group_amount * removed_fraction      (on every P&L account of the deal period)
   acquisition: removed_fraction = days from the period start up to the day before the deal date, over the
       period's days (an acquisition on the 11th of a 31-day month removes 10/31); none when the deal is on
       the first day.
   full disposal: removed_fraction = days after the deal date to the period end, over the period's days; none
       when the deal is on the last day. The deal day belongs to the group on both sides.
   Expected 0 (no adjustment at all) for 'Whole period', 'Stub trial balance' (the uploaded period is the
   stub, used unscaled), an undeclared treatment, every other period, and a deal on a boundary day.

   The model's amount is the P&L lines of gold_acquisition_adjustments (pnl_proration) plus the lines of
   gold_business_disposal_journal with account_role 'post_disposal_pnl' (line_no 105). A model line counts
   only on a P&L account (silver_main_accounts.is_pnl), so the retained-earnings line that balances the
   adjustment is not judged as an amount.

   Faults, one row each:
     amount differs          per (group, entity, year, period, account), model minus expected is more than
                             0.01 (expected_amount, model_amount)
     acquisition unbalanced  gold_acquisition_adjustments does not sum to 0 for a (group, entity, year,
                             period): the proration must balance through a retained-earnings line
   Fixtures: assert_partial_period_pnl_matches_treatment.*.sql. #}
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

{# the deal period: lowest Regular tuple whose declared span holds the deal date #}
acquisitions as (
    select
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as data_area_id,
        argMin(c.fy, (c.fy, c.fp)) as fy,
        argMin(c.fp, (c.fy, c.fp)) as fp,
        argMin(c.start_date, (c.fy, c.fp)) as period_start,
        argMin(c.end_date, (c.fy, c.fp)) as period_end,
        bc.acquisition_date as deal_date
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join calendar as c
    where c.start_date <= bc.acquisition_date
      and c.end_date >= bc.acquisition_date
    group by bc.consolidation_group, bc.acquired_entity, bc.acquisition_date
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
      {# review F2: the journal posts a disposal whole or not at all (a disposal with no governed Closing rate posts
         nothing, and assert_deal_rate_resolved names the rate), so a disposal with no journal row in its period has
         no line 105 to expect. Any row of the journal counts; a posted disposal that lacks line 105 still flags. #}
      and (bd.consolidation_group, bd.disposed_entity, c.fy, c.fp) in (
          select consolidation_group, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period)
          from {{ ref('gold_business_disposal_journal') }}
      )
    group by bd.consolidation_group, bd.disposed_entity, bd.disposal_date
),

deals as (
    select
        consolidation_group, data_area_id, fy, fp,
        if(deal_date > period_start,
           toFloat64(dateDiff('day', period_start, deal_date)) / (dateDiff('day', period_start, period_end) + 1),
           0.0) as removed_fraction
    from acquisitions

    union all

    select
        consolidation_group, data_area_id, fy, fp,
        if(deal_date < period_end,
           toFloat64(dateDiff('day', deal_date, period_end)) / (dateDiff('day', period_start, period_end) + 1),
           0.0) as removed_fraction
    from disposals
),

pnl_amounts as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        toUInt16(ctb.fiscal_year) as fy,
        toUInt16(ctb.fiscal_period) as fp,
        ctb.main_account as main_account,
        sum(coalesce(ctb.group_amount, 0.0)) as group_amount
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    where ctb.is_pnl = 1
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period, ctb.main_account
),

expected as (
    select
        p.consolidation_group as consolidation_group,
        p.data_area_id as data_area_id,
        p.fy as fy,
        p.fp as fp,
        p.main_account as main_account,
        -(p.group_amount * d.removed_fraction) as expected_amount,
        0.0 as model_amount
    from pnl_amounts as p
    inner join deals as d
        on d.consolidation_group = p.consolidation_group
        and d.data_area_id = p.data_area_id
        and d.fy = p.fy
        and d.fp = p.fp
    where p.consolidation_group in (
        select consolidation_group from treatment where partial_period_treatment = 'Pro-rate by days'
    )
),

pnl_accounts as (
    select main_account_id from {{ ref('silver_main_accounts') }} where is_pnl = 1
),

modelled as (
    select
        consolidation_group, data_area_id,
        toUInt16(fiscal_year) as fy, toUInt16(fiscal_period) as fp,
        main_account,
        0.0 as expected_amount,
        toFloat64(adjustment_amount) as model_amount
    from {{ ref('gold_acquisition_adjustments') }}
    where adjustment_type = 'pnl_proration'
      and main_account in (select main_account_id from pnl_accounts)

    union all

    select
        consolidation_group, data_area_id,
        toUInt16(fiscal_year) as fy, toUInt16(fiscal_period) as fp,
        main_account,
        0.0 as expected_amount,
        toFloat64(adjustment_amount) as model_amount
    from {{ ref('gold_business_disposal_journal') }}
    where account_role = 'post_disposal_pnl'
      and main_account in (select main_account_id from pnl_accounts)
),

compared as (
    select
        consolidation_group, data_area_id, fy, fp, main_account,
        sum(expected_amount) as expected_amount,
        sum(model_amount) as model_amount
    from (
        select * from expected
        union all
        select * from modelled
    )
    group by consolidation_group, data_area_id, fy, fp, main_account
)

select
    'amount differs' as fault,
    consolidation_group,
    data_area_id,
    fy as fiscal_year,
    fp as fiscal_period,
    main_account,
    expected_amount,
    model_amount
from compared
where abs(model_amount - expected_amount) > 0.01

union all

select
    'acquisition adjustments do not balance' as fault,
    consolidation_group,
    data_area_id,
    toUInt16(fiscal_year) as fiscal_year,
    toUInt16(fiscal_period) as fiscal_period,
    '' as main_account,
    0.0 as expected_amount,
    sum(toFloat64(adjustment_amount)) as model_amount
from {{ ref('gold_acquisition_adjustments') }}
group by consolidation_group, data_area_id, fiscal_year, fiscal_period
having abs(sum(toFloat64(adjustment_amount))) > 0.01
