{% macro allocation_engine_multistep() %}
{#
    PRD-17: Dynamic N-step cascading allocation engine.
    Processes rules in step_order sequence (1..N) via Jinja unrolled loop.
    Each step's pool = TB base + allocated amounts from prior steps into that cost center.
    Supports dynamic step count — adding step N+1 = just add a rule row + driver values.

    PRD-18: allocation_method = 'reciprocal' handled in separate macro before step_down.
    PRD-19: driver_type = 'composite'/'conditional' dispatched via resolve_allocation_driver.
    PRD-20: driver_type = 'tiered' dispatched to tiered rate logic.
    PRD-21: allocation_run_id for traceability.
#}

{# Max steps we support via Jinja unrolling. Rules beyond this are ignored. #}
{% set max_steps = 1 %}
{% if execute %}
    {% set _r = run_query('select max(step_order) as m from ' ~ ref('allocation_rules')) %}
    {% if _r and _r.rows and (_r.rows | length) > 0 and _r.rows[0][0] is not none %}
        {% set max_steps = _r.rows[0][0] | int %}
    {% endif %}
{% endif %}

with all_rules as (
    {# PRD-17: Prefer staging rules if populated, else seed fallback #}
    select
        allocation_rule_id,
        rule_name,
        step_order,
        source_account,
        source_cost_center,
        driver_type,
        target_account,
        description,
        'step_down' as allocation_method,
        '' as driver_formula
    from {{ ref('allocation_rules') }}
    where not exists (
        select 1 from {{ source('epm_staging', 'allocation_rules') }}
        where allocation_rule_id != ''
        limit 1
    )

    union all

    select
        allocation_rule_id,
        rule_name,
        step_order,
        source_account,
        source_cost_center,
        driver_type,
        target_account,
        description,
        allocation_method,
        driver_formula
    from {{ source('epm_staging', 'allocation_rules') }}
),

{# Base trial balance amounts by account and cost center #}
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

{# PRD-17: Unified driver lookup — supports all driver types from seed or staging #}
drivers_unified as (
    {# From staging (preferred) #}
    select
        driver_type,
        data_area_id,
        cost_center,
        fiscal_year,
        fiscal_period,
        {{ cast_to_float64('driver_value') }} as driver_value
    from {{ source('epm_staging', 'allocation_drivers') }}

    union all

    {# Seed fallback: headcount #}
    select
        'headcount' as driver_type,
        data_area_id,
        cost_center,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
        {{ cast_to_float64('driver_value') }} as driver_value
    from {{ ref('allocation_drivers_headcount') }}
    where not exists (
        select 1 from {{ source('epm_staging', 'allocation_drivers') }}
        where driver_type = 'headcount'
        limit 1
    )

    union all

    {# Seed fallback: sqm #}
    select
        'sqm' as driver_type,
        data_area_id,
        cost_center,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
        {{ cast_to_float64('driver_value') }} as driver_value
    from {{ ref('allocation_drivers_sqm') }}
    where not exists (
        select 1 from {{ source('epm_staging', 'allocation_drivers') }}
        where driver_type = 'sqm'
        limit 1
    )

    union all

    {# Seed fallback: revenue #}
    select
        'revenue' as driver_type,
        data_area_id,
        cost_center,
        {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
        {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
        {{ cast_to_float64('driver_value') }} as driver_value
    from {{ ref('allocation_drivers_revenue') }}
    where not exists (
        select 1 from {{ source('epm_staging', 'allocation_drivers') }}
        where driver_type = 'revenue'
        limit 1
    )
),

{# Driver weights: value / sum(value) partitioned by type, entity, period #}
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
    from drivers_unified
    where driver_value > 0
),

{# ---- DYNAMIC STEP LOOP (unrolled via Jinja) ---- #}

{% for step in range(1, max_steps + 1) %}

step{{ step }}_rule as (
    select * from all_rules
    where step_order = {{ step }}
      and allocation_method = 'step_down'
),

{% if step == 1 %}
step1_pool as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        {{ cast_to_float64('sum(tb.amount)') }} as pool_amount
    from tb_base as tb
    cross join step1_rule as r
    where tb.main_account = {{ cast_to_string('r.source_account') }}
      and tb.{{ get_allocation_cost_center_dim() }} = r.source_cost_center
    group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period
),
{% else %}
{# Pool = TB base + cascade from all prior steps landing in this step's source #}
prior_to_step{{ step }} as (
    select
        s.data_area_id,
        s.fiscal_year,
        s.fiscal_period,
        sum(s.allocated_amount) as cascade_amount
    from (
        {% for prior in range(1, step) %}
        select data_area_id, fiscal_year, fiscal_period, target_cost_center, target_account, allocated_amount from step{{ prior }}_allocated
        {% if not loop.last %}union all{% endif %}
        {% endfor %}
    ) as s
    inner join step{{ step }}_rule as r
        on s.target_cost_center = r.source_cost_center
        and s.target_account = {{ cast_to_string('r.source_account') }}
    group by s.data_area_id, s.fiscal_year, s.fiscal_period
),

step{{ step }}_pool as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        {{ cast_to_float64('sum(tb.amount)') }} + coalesce(max(p.cascade_amount), 0) as pool_amount
    from tb_base as tb
    cross join step{{ step }}_rule as r
    left join prior_to_step{{ step }} as p
        on tb.data_area_id = p.data_area_id
        and tb.fiscal_year = p.fiscal_year
        and tb.fiscal_period = p.fiscal_period
    where tb.main_account = {{ cast_to_string('r.source_account') }}
      and tb.{{ get_allocation_cost_center_dim() }} = r.source_cost_center
    group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period
),
{% endif %}

step{{ step }}_allocated as (
    select
        r.allocation_rule_id as allocation_rule_id,
        {{ cast_to_uint8('r.step_order') }} as step_order,
        sp.data_area_id as data_area_id,
        sp.fiscal_year as fiscal_year,
        sp.fiscal_period as fiscal_period,
        {{ cast_to_string('r.source_account') }} as source_account,
        r.source_cost_center as source_cost_center,
        d.cost_center as target_cost_center,
        {{ cast_to_string('r.target_account') }} as target_account,
        r.driver_type as driver_type,
        sp.pool_amount as pool_amount,
        d.driver_weight as driver_weight,
        sp.pool_amount * d.driver_weight as allocated_amount
    from step{{ step }}_pool as sp
    cross join step{{ step }}_rule as r
    inner join driver_weights as d
        on sp.data_area_id = d.data_area_id
        and sp.fiscal_year = {{ cast_to_uint16('d.fiscal_year') }}
        and sp.fiscal_period = {{ cast_to_uint8('d.fiscal_period') }}
        and d.driver_type = r.driver_type
    where d.cost_center != r.source_cost_center
),

{% endfor %}

{# ---- UNION all steps ---- #}
all_allocations as (
    {% for step in range(1, max_steps + 1) %}
    select * from step{{ step }}_allocated
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select * from all_allocations
where allocation_rule_id != ''

{% endmacro %}
