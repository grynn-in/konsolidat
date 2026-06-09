{% macro allocation_engine_reciprocal() %}
{#
    PRD-18: Reciprocal (circular) allocation engine.
    Uses iterative convergence (10 iterations max) where each iteration
    feeds allocated amounts back as input until delta < 0.01.
    Reciprocal rules are processed BEFORE step-down rules.
#}

{% set max_iterations = 10 %}

with reciprocal_rules as (
    select
        allocation_rule_id,
        rule_name,
        step_order,
        source_account,
        source_cost_center,
        driver_type,
        target_account
    from {{ source('epm_staging', 'allocation_rules') }}
    where allocation_method = 'reciprocal'
),

{# Base trial balance amounts #}
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

{# Driver weights from unified driver lookup #}
driver_weights as (
    select
        driver_type,
        data_area_id,
        cost_center,
        fiscal_year,
        fiscal_period,
        driver_value,
        driver_value / nullIf(sum(driver_value) over (
            partition by driver_type, data_area_id, fiscal_year, fiscal_period
        ), 0) as driver_weight
    from {{ source('epm_staging', 'allocation_drivers') }}
    where driver_value > 0
),

{# Iteration 0: initial pool from TB base #}
iter0_pool as (
    select
        r.allocation_rule_id,
        tb.data_area_id,
        tb.fiscal_year,
        tb.fiscal_period,
        r.source_cost_center,
        r.source_account,
        r.driver_type,
        r.target_account,
        {{ cast_to_float64('sum(tb.amount)') }} as pool_amount
    from tb_base as tb
    inner join reciprocal_rules as r
        on tb.main_account = r.source_account
        and tb.{{ get_allocation_cost_center_dim() }} = r.source_cost_center
    group by r.allocation_rule_id, tb.data_area_id, tb.fiscal_year, tb.fiscal_period,
             r.source_cost_center, r.source_account, r.driver_type, r.target_account
),

{# Iteration 0 allocation #}
iter0_allocated as (
    select
        p.allocation_rule_id,
        p.data_area_id,
        p.fiscal_year,
        p.fiscal_period,
        p.source_cost_center,
        p.source_account,
        d.cost_center as target_cost_center,
        p.target_account,
        p.driver_type,
        p.pool_amount,
        d.driver_weight,
        p.pool_amount * d.driver_weight as allocated_amount,
        0 as iteration
    from iter0_pool as p
    inner join driver_weights as d
        on p.data_area_id = d.data_area_id
        and p.fiscal_year = d.fiscal_year
        and p.fiscal_period = d.fiscal_period
        and p.driver_type = d.driver_type
    where d.cost_center != p.source_cost_center
),

{# Iterations 1..N: feed back allocated amounts as additional pool #}
{% for iter in range(1, max_iterations + 1) %}
iter{{ iter }}_feedback as (
    select
        r.allocation_rule_id,
        prev.data_area_id,
        prev.fiscal_year,
        prev.fiscal_period,
        r.source_cost_center,
        r.source_account,
        r.driver_type,
        r.target_account,
        sum(prev.allocated_amount) as feedback_amount
    from iter{{ iter - 1 }}_allocated as prev
    inner join reciprocal_rules as r
        on prev.target_cost_center = r.source_cost_center
        and prev.target_account = r.source_account
    group by r.allocation_rule_id, prev.data_area_id, prev.fiscal_year, prev.fiscal_period,
             r.source_cost_center, r.source_account, r.driver_type, r.target_account
),

iter{{ iter }}_allocated as (
    select
        fb.allocation_rule_id,
        fb.data_area_id,
        fb.fiscal_year,
        fb.fiscal_period,
        fb.source_cost_center,
        fb.source_account,
        d.cost_center as target_cost_center,
        fb.target_account,
        fb.driver_type,
        fb.feedback_amount as pool_amount,
        d.driver_weight,
        fb.feedback_amount * d.driver_weight as allocated_amount,
        {{ iter }} as iteration
    from iter{{ iter }}_feedback as fb
    inner join driver_weights as d
        on fb.data_area_id = d.data_area_id
        and fb.fiscal_year = d.fiscal_year
        and fb.fiscal_period = d.fiscal_period
        and fb.driver_type = d.driver_type
    where d.cost_center != fb.source_cost_center
      and abs(fb.feedback_amount) > 0.01  {# convergence check #}
),
{% endfor %}

{# Union all iterations #}
all_reciprocal as (
    {% for iter in range(0, max_iterations + 1) %}
    select
        allocation_rule_id,
        data_area_id,
        fiscal_year,
        fiscal_period,
        source_cost_center,
        source_account,
        target_cost_center,
        target_account,
        driver_type,
        pool_amount,
        driver_weight,
        allocated_amount,
        iteration
    from iter{{ iter }}_allocated
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

{# Aggregate per target: sum across all iterations for final allocation #}
reciprocal_results as (
    select
        allocation_rule_id,
        data_area_id,
        fiscal_year,
        fiscal_period,
        source_cost_center,
        source_account,
        target_cost_center,
        target_account,
        driver_type,
        sum(allocated_amount) as allocated_amount,
        max(iteration) as final_iteration,
        'reciprocal' as allocation_method
    from all_reciprocal
    group by allocation_rule_id, data_area_id, fiscal_year, fiscal_period,
             source_cost_center, source_account, target_cost_center, target_account, driver_type
)

select * from reciprocal_results

{% endmacro %}
