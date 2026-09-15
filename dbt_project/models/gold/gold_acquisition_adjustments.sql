{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-11: Step acquisitions — P&L proration
   - Prorates P&L to post-acquisition months only.
   konsolidat#198: the goodwill and fair-value adjustment entries this model
   used to post (one-sided debits to the hardcoded accounts '1800'/'1900',
   from the Ownership Period's acquisition_price and net assets summed over
   every period) are gone. gold_business_combination_journal posts the
   balanced acquisition journal from the submitted Business Combination, to
   the accounts the group declares. Only the proration remains here. #}

with acquisition_periods as (
    select
        consolidation_group,
        data_area_id,
        effective_date,
        ownership_pct,
        consolidation_method,
        acquisition_date,
        is_first_acquisition,
        acquisition_price,
        fair_value_adjustment
    from {{ source('epm_staging', 'ownership_periods') }}
    where acquisition_date > toDate('1900-01-01')
),

{# P&L proration: exclude pre-acquisition P&L amounts #}
pnl_proration as (
    select
        ap.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        ctb.main_account as main_account,
        ctb.account_name as account_name,
        ctb.local_amount as original_amount,
        {# Prorate to post-acquisition only #}
        {{ prorate_period_amount(
            'ctb.local_amount',
            'ap.acquisition_date',
            'ctb.fiscal_year',
            'ctb.fiscal_period'
        ) }} as prorated_amount,
        ctb.local_amount - {{ prorate_period_amount(
            'ctb.local_amount',
            'ap.acquisition_date',
            'ctb.fiscal_year',
            'ctb.fiscal_period'
        ) }} as pre_acquisition_excluded,
        ap.acquisition_date as acquisition_date,
        'pnl_proration' as adjustment_type
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join acquisition_periods as ap
        on ctb.consolidation_group = ap.consolidation_group
        and ctb.data_area_id = ap.data_area_id
    where ctb.is_pnl = 1
      and {{ build_date_from_year_period('ctb.fiscal_year', 'ctb.fiscal_period') }}
          >= toDate(concat(toString(toYear(ap.acquisition_date)), '-01-01'))
      and {{ build_date_from_year_period('ctb.fiscal_year', 'ctb.fiscal_period') }}
          <= toDate(concat(toString(toYear(ap.acquisition_date)), '-12-31'))
),

{# Output: proration adjustments (negative entries to remove pre-acq P&L) #}
proration_entries as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        adjustment_type,
        -pre_acquisition_excluded as adjustment_amount,
        acquisition_date
    from pnl_proration
    where abs(pre_acquisition_excluded) > 0.01
)

select * from proration_entries
