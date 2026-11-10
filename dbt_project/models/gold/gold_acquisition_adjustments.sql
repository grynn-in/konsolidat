{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsolidat#171 step 2c (T6): the acquisition's partial-period P&L, by the treatment the group declares.
   Decided by Deepak Pai: 18 Sep 2026 (mid-period P&L follows the group root's partial_period_treatment:
   Whole period | Pro-rate by days | Stub trial balance, no default), 10 Nov 2026 Q1 A (an undeclared
   treatment with a mid-period deal is a build ERROR: assert_partial_period_treatment_declared).
   Rejected: the month arithmetic this model used (prorate_period_amount over calendar months, in local
   currency, one-sided, keyed on ownership_periods.acquisition_date).

   The deal is the submitted Business Combination (epm_staging.business_combinations), never the Ownership
   Period: an Ownership Period row per owner link would repeat the proration once per link. Its period is
   the lowest Regular period whose declared span holds the acquisition date (deal_period_holds(), as
   gold_business_combination_journal picks it).

   Only a group whose root row declares exactly 'Pro-rate by days' produces rows, and only for a deal
   dated after the period's start. 'Whole period', 'Stub trial balance' (the uploaded period is the stub,
   used unscaled) and a deal on the first day of the period produce none.

   For each P&L account (silver_main_accounts.is_pnl) of the acquired entity in the deal period of
   gold_consolidated_trial_balance, in group currency:
       adjustment_amount = -group_amount * partial_period_removed_fraction('acquisition', ...)
   (an acquisition on the 11th of a 31-day month removes 10/31 of the period: days 1 to 10).
   One balancing line per (group, entity, year, period) on the chart's retained-earnings account
   (silver_main_accounts.is_retained_earnings = 1, the lowest code if several, as
   gold_nci_attribution_journal picks it) carries the opposite sum, so the rows sum to 0 and
   assert_end_to_end_bs_balances holds. A chart that flags no retained-earnings account gets the balancing
   line on account '' (the account the pre-acquisition-profit line of gold_business_combination_journal
   also uses), which assert_acquisition_accounts_declared names.

   Both lines keep adjustment_type 'pnl_proration': gold_consolidation_waterfall sums that type into its
   acquisition/disposal layer, where the two lines net to 0 (the P&L shift and its counter-entry), so the
   layer does not double count; gold_fully_consolidated_tb sums each account's rows to the account grain.

   Fixtures: assert_partial_period_pnl_matches_treatment.acquisition_*.sql. #}

with {# the group root row declares the treatment #}
treatment as (
    select
        consolidation_group,
        any(partial_period_treatment) as partial_period_treatment
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

{# the deal period: the lowest Regular tuple whose declared span holds the acquisition date #}
deals as (
    select
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as data_area_id,
        bc.acquisition_date as acquisition_date,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period,
        argMin(fp.start_date, (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as period_start,
        argMin(fp.end_date, (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as period_end
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where {{ deal_period_holds('fp', 'bc.acquisition_date') }}
    group by bc.consolidation_group, bc.acquired_entity, bc.acquisition_date
),

mid_period_deals as (
    select
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.acquisition_date as acquisition_date,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        {{ partial_period_removed_fraction('acquisition', 'd.acquisition_date', 'd.period_start', 'd.period_end') }} as removed_fraction
    from deals as d
    inner join treatment as t
        on t.consolidation_group = d.consolidation_group
    where t.partial_period_treatment = 'Pro-rate by days'
      and d.acquisition_date > d.period_start
),

pnl_accounts as (
    select main_account_id from {{ ref('silver_main_accounts') }} where is_pnl = 1
),

pnl_lines as (
    select
        m.consolidation_group as consolidation_group,
        m.data_area_id as data_area_id,
        m.fiscal_year as fiscal_year,
        m.fiscal_period as fiscal_period,
        ctb.main_account as main_account,
        any(ctb.account_name) as account_name,
        -(sum(coalesce(ctb.group_amount, 0.0)) * any(m.removed_fraction)) as adjustment_amount,
        any(m.acquisition_date) as acquisition_date
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join mid_period_deals as m
        on m.consolidation_group = ctb.consolidation_group
        and m.data_area_id = ctb.data_area_id
        and m.fiscal_year = toUInt16(ctb.fiscal_year)
        and m.fiscal_period = toUInt16(ctb.fiscal_period)
    where ctb.main_account in (select main_account_id from pnl_accounts)
    group by m.consolidation_group, m.data_area_id, m.fiscal_year, m.fiscal_period, ctb.main_account
    having abs(adjustment_amount) > {{ materiality_floor() }}
),

{# the balancing line: the chart's retained-earnings account, '' when it flags none #}
balancing_line as (
    select
        p.consolidation_group as consolidation_group,
        p.data_area_id as data_area_id,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        (select min(main_account_id) from {{ ref('silver_main_accounts') }} where is_retained_earnings = 1) as main_account,
        (select argMin(account_name, main_account_id) from {{ ref('silver_main_accounts') }} where is_retained_earnings = 1) as account_name,
        -sum(p.adjustment_amount) as adjustment_amount,
        any(p.acquisition_date) as acquisition_date
    from pnl_lines as p
    group by p.consolidation_group, p.data_area_id, p.fiscal_year, p.fiscal_period
)

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    main_account, account_name,
    'pnl_proration' as adjustment_type,
    adjustment_amount, acquisition_date
from pnl_lines

union all

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    main_account, account_name,
    'pnl_proration' as adjustment_type,
    adjustment_amount, acquisition_date
from balancing_line
