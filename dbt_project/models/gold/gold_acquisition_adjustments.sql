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
   Rejected: the month arithmetic this model used (a calendar-month proration macro, in local
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
   (silver_main_accounts.is_retained_earnings = 1, read through retained_earnings_account(), konsolidat#316: '' when 0 or 2+ are flagged, named by assert_retained_earnings_account_unique;
   gold_nci_attribution_journal reads it the same way) carries the opposite sum, so the rows sum to 0 and
   assert_end_to_end_bs_balances holds. A chart that flags none, or several, gets the balancing
   line on account '' (the account the pre-acquisition-profit line of gold_business_combination_journal
   also uses), which assert_acquisition_accounts_declared names.

   Both lines keep adjustment_type 'pnl_proration': gold_consolidation_waterfall sums that type into its
   acquisition/disposal layer, where the two lines net to 0 (the P&L shift and its counter-entry), so the
   layer does not double count; gold_fully_consolidated_tb sums each account's rows to the account grain.

   Grain (review F1; decided by Deepak Pai, 3 Oct 2026: consolidation entry dimensions are hybrid, inherit
   where derivable): the proration is not a deal journal and its source row carries a dimension value and an
   intercompany partner, so each P&L line inherits both (one line per account, partner and dimension values of
   the source). The balancing line inherits the DIMENSIONS, one per (group, entity, year, period, dimensions),
   so every dimension slice nets to 0 and a dimension report shows the P&L and its counter-entry on the same
   member. It carries NO partner: retained earnings is not an intercompany account, and the partner on a P&L
   line only says whom the entity traded with (decision 2 Oct 2026: a partner on a non-IC account is reported).
   Fixtures: assert_partial_period_pnl_matches_treatment.acquisition_*.sql.

   Known limit: two Business Combinations for one entity in one period are not handled (deferred to konsolidat#348). #}

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
        ctb.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='ctb.', trailing=true) }}
        -(sum(coalesce(ctb.group_amount, 0.0)) * any(m.removed_fraction)) as adjustment_amount,
        any(m.acquisition_date) as acquisition_date
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join mid_period_deals as m
        on m.consolidation_group = ctb.consolidation_group
        and m.data_area_id = ctb.data_area_id
        and m.fiscal_year = toUInt16(ctb.fiscal_year)
        and m.fiscal_period = toUInt16(ctb.fiscal_period)
    where ctb.main_account in (select main_account_id from pnl_accounts)
    group by m.consolidation_group, m.data_area_id, m.fiscal_year, m.fiscal_period, ctb.main_account,
             ctb.partner_data_area_id{{ dim_group_by(prefix='ctb.', leading=true) }}
    having abs(adjustment_amount) > {{ materiality_floor() }}
),

{# the balancing line: the chart's single retained-earnings account, '' when it flags none or several (#316) #}
balancing_line as (
    select
        p.consolidation_group as consolidation_group,
        p.data_area_id as data_area_id,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        if(re.re_count = 1, re.retained_earnings_account, '') as main_account,
        if(re.re_count = 1, re_name.account_name, '') as account_name,
        '' as partner_data_area_id,
        {{ dim_select(prefix='p.', trailing=true) }}
        -sum(p.adjustment_amount) as adjustment_amount,
        any(p.acquisition_date) as acquisition_date
    from pnl_lines as p
    cross join {{ retained_earnings_account() }} as re
    left join (
        select main_account_id, any(account_name) as account_name
        from {{ ref('silver_main_accounts') }}
        group by main_account_id
    ) as re_name
        on re_name.main_account_id = re.retained_earnings_account
    group by p.consolidation_group, p.data_area_id, p.fiscal_year, p.fiscal_period{{ dim_group_by(prefix='p.', leading=true) }},
             re.re_count, re.retained_earnings_account, re_name.account_name
)

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    main_account, account_name,
    partner_data_area_id,
    {{ dim_select(trailing=true) }}
    'pnl_proration' as adjustment_type,
    adjustment_amount, acquisition_date
from pnl_lines

union all

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    main_account, account_name,
    partner_data_area_id,
    {{ dim_select(trailing=true) }}
    'pnl_proration' as adjustment_type,
    adjustment_amount, acquisition_date
from balancing_line
