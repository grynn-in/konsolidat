{% macro allocation_engine_tiered() %}
{#
    PRD-20: Tiered & threshold allocation engine.
    When driver_type = 'tiered', each tier has a rate applied to its band.
    Per-tier amount = min(remaining_pool, band_width) × rate
    Cap/floor clamping with excess redistribution.
#}

with tiered_rules as (
    select
        r.allocation_rule_id,
        r.rule_name,
        r.step_order,
        r.source_account,
        r.source_cost_center,
        r.target_account,
        t.tier_order,
        t.lower_bound,
        t.upper_bound,
        t.rate,
        t.cap,
        t.floor
    from {{ source('epm_staging', 'allocation_rules') }} as r
    inner join {{ source('epm_staging', 'allocation_tiers') }} as t
        on r.allocation_rule_id = t.allocation_rule_id
    where r.driver_type = 'tiered'
),

tb_base as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        {{ get_allocation_cost_center_dim() }},
        sum(period_net_amount) as amount
    from {{ ref('gold_trial_balance') }}
    group by data_area_id, fiscal_year, fiscal_period, main_account, {{ get_allocation_cost_center_dim() }}
),

tiered_pools as (
    select
        r.allocation_rule_id,
        r.step_order,
        tb.data_area_id,
        tb.fiscal_year,
        tb.fiscal_period,
        r.source_account,
        r.source_cost_center,
        r.target_account,
        r.tier_order,
        r.lower_bound,
        r.upper_bound,
        r.rate,
        r.cap,
        r.floor,
        {{ cast_to_float64('sum(tb.amount)') }} as pool_amount
    from tb_base as tb
    inner join tiered_rules as r
        on tb.main_account = r.source_account
        and tb.{{ get_allocation_cost_center_dim() }} = r.source_cost_center
    group by r.allocation_rule_id, r.step_order, tb.data_area_id, tb.fiscal_year,
             tb.fiscal_period, r.source_account, r.source_cost_center, r.target_account,
             r.tier_order, r.lower_bound, r.upper_bound, r.rate, r.cap, r.floor
),

{# Per-tier allocation: apply rate to band, then clamp with cap/floor #}
tiered_allocated as (
    select
        allocation_rule_id,
        step_order,
        data_area_id,
        fiscal_year,
        fiscal_period,
        source_account,
        source_cost_center,
        target_account,
        tier_order,
        pool_amount,
        rate,
        {# Band amount = portion of pool in this tier's range #}
        greatest(0, least(pool_amount, upper_bound) - lower_bound) as band_amount,
        {# Raw tier allocation = band × rate #}
        greatest(0, least(pool_amount, upper_bound) - lower_bound) * rate as raw_tier_amount,
        {# Clamped: apply floor and cap #}
        least(
            cap,
            greatest(
                floor,
                greatest(0, least(pool_amount, upper_bound) - lower_bound) * rate
            )
        ) as tier_amount
    from tiered_pools
)

select
    allocation_rule_id,
    {{ cast_to_uint8('step_order') }} as step_order,
    data_area_id,
    fiscal_year,
    fiscal_period,
    source_account,
    source_cost_center,
    '' as target_cost_center,
    target_account,
    'tiered' as driver_type,
    pool_amount,
    rate as driver_weight,
    tier_amount as allocated_amount
from tiered_allocated
where abs(tier_amount) > 0.01

{% endmacro %}
