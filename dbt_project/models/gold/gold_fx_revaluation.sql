{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-2: CTA (Currency Translation Adjustment)
   CTA = plug that keeps BS balanced after translating BS at closing and PnL at average
   Per-period: CTA = sum(PnL local_amount × (closing_rate - average_rate) × ownership_pct) #}

with pnl_cta as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        reporting_currency,
        accounting_currency,
        {# P&L component: difference between translating at closing vs average #}
        sum(local_amount * (closing_rate - average_rate) * ownership_pct) as pnl_cta_component,
        any(closing_rate) as sample_closing_rate,
        any(average_rate) as sample_average_rate
    from {{ ref('gold_consolidated_trial_balance') }}
    where is_pnl = 1
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        reporting_currency,
        accounting_currency
)

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    reporting_currency,
    accounting_currency,
    'CTA' as adjustment_type,
    'CTA' as main_account,
    sample_closing_rate as closing_rate,
    sample_average_rate as average_rate,
    pnl_cta_component as cta_amount
from pnl_cta
