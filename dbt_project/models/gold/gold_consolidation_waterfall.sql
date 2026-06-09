{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-22: Consolidation waterfall — single-row build-up per group per period
   entity → IC elim → CTA → topside → equity method → acq/disposal → final #}

with layer_amounts as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        adjustment_type,
        sum(amount) as layer_amount
    from {{ ref('gold_fully_consolidated_tb') }}
    group by consolidation_group, fiscal_year, fiscal_period, adjustment_type
),

waterfall as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        sum(case when adjustment_type = 'entity' then layer_amount else 0 end) as entity_amount,
        sum(case when adjustment_type = 'ic_elimination' then layer_amount else 0 end) as ic_elimination_amount,
        sum(case when adjustment_type = 'cta' then layer_amount else 0 end) as cta_amount,
        sum(case when adjustment_type in ('topside', 'reclassification', 'auto_reversal') then layer_amount else 0 end) as topside_amount,
        sum(case when adjustment_type = 'equity_method' then layer_amount else 0 end) as equity_method_amount,
        sum(case when adjustment_type in ('pnl_proration', 'goodwill', 'fair_value_adjustment',
                                           'disposal_gain_loss', 'cta_recycling') then layer_amount else 0 end) as acq_disposal_amount,
        sum(layer_amount) as final_amount
    from layer_amounts
    group by consolidation_group, fiscal_year, fiscal_period
)

select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    entity_amount,
    entity_amount + ic_elimination_amount as after_ic_elim,
    entity_amount + ic_elimination_amount + cta_amount as after_cta,
    entity_amount + ic_elimination_amount + cta_amount + topside_amount as after_topside,
    entity_amount + ic_elimination_amount + cta_amount + topside_amount + equity_method_amount as after_equity_method,
    final_amount,
    ic_elimination_amount,
    cta_amount,
    topside_amount,
    equity_method_amount,
    acq_disposal_amount
from waterfall
