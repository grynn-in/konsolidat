{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-11: Step acquisitions — P&L proration and goodwill calculation
   - Prorates P&L to post-acquisition months only
   - Calculates goodwill = acquisition_price - (net_assets × ownership%)
   - Generates fair value adjustment topside entries #}

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

{# Goodwill calculation per acquisition #}
net_assets as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        sum(case when ctb.is_balance_sheet = 1 then ctb.local_amount else 0 end) as total_net_assets
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join acquisition_periods as ap
        on ctb.consolidation_group = ap.consolidation_group
        and ctb.data_area_id = ap.data_area_id
    group by ctb.consolidation_group, ctb.data_area_id
),

goodwill as (
    select
        ap.consolidation_group as consolidation_group,
        ap.data_area_id as data_area_id,
        ap.acquisition_price as acquisition_price,
        na.total_net_assets as net_assets,
        ap.ownership_pct as ownership_pct,
        toFloat64(ap.acquisition_price) - (toFloat64(na.total_net_assets) * toFloat64(ap.ownership_pct) / 100.0) as goodwill_amount,
        ap.fair_value_adjustment as fair_value_adjustment,
        ap.acquisition_date as acquisition_date,
        'goodwill' as adjustment_type
    from acquisition_periods as ap
    left join net_assets as na
        on ap.consolidation_group = na.consolidation_group
        and ap.data_area_id = na.data_area_id
    where ap.is_first_acquisition = 1
      and ap.acquisition_price > 0
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
),

{# Output: goodwill topside journal entries #}
goodwill_entries as (
    select
        consolidation_group,
        data_area_id,
        toUInt16(toYear(acquisition_date)) as fiscal_year,
        toUInt8(toMonth(acquisition_date)) as fiscal_period,
        '1800' as main_account,
        'Goodwill on acquisition' as account_name,
        'goodwill' as adjustment_type,
        goodwill_amount as adjustment_amount,
        acquisition_date
    from goodwill
    where abs(goodwill_amount) > 0.01
),

{# Output: fair value adjustment entries #}
fva_entries as (
    select
        consolidation_group,
        data_area_id,
        toUInt16(toYear(acquisition_date)) as fiscal_year,
        toUInt8(toMonth(acquisition_date)) as fiscal_period,
        '1900' as main_account,
        'Fair value adjustment on acquisition' as account_name,
        'fair_value_adjustment' as adjustment_type,
        toFloat64(fair_value_adjustment) as adjustment_amount,
        acquisition_date
    from goodwill
    where abs(fair_value_adjustment) > 0.01
)

select * from proration_entries
union all
select * from goodwill_entries
union all
select * from fva_entries
