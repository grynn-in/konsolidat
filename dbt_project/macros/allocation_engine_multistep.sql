{% macro allocation_engine_multistep() %}
{#
    Multi-step cascading allocation engine.
    Processes rules in step_order sequence.
    Each step's pool = TB base + allocated amounts from prior steps into that cost center.
    Uses recursive CTE pattern unrolled into explicit steps via Jinja.
#}

{# Step 1: All rules ordered by step_order #}
{% set rules_query %}
    select allocation_rule_id, step_order, source_account, source_cost_center, driver_type, target_account
    from {{ ref('allocation_rules') }}
    order by step_order
{% endset %}

with all_rules as (
    select *
    from {{ ref('allocation_rules') }}
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

{# Driver lookup for headcount #}
drivers_headcount as (
    select
        data_area_id,
        cost_center,
        fiscal_year,
        fiscal_period,
        driver_value,
        driver_value / sum(driver_value) over (
            partition by data_area_id, fiscal_year, fiscal_period
        ) as driver_weight
    from {{ ref('allocation_drivers_headcount') }}
),

{# Driver lookup for sqm #}
drivers_sqm as (
    select
        data_area_id,
        cost_center,
        fiscal_year,
        fiscal_period,
        driver_value,
        driver_value / sum(driver_value) over (
            partition by data_area_id, fiscal_year, fiscal_period
        ) as driver_weight
    from {{ ref('allocation_drivers_sqm') }}
),

{# Driver lookup for revenue — exclude zero-value rows #}
drivers_revenue as (
    select
        data_area_id,
        cost_center,
        fiscal_year,
        fiscal_period,
        driver_value,
        driver_value / sum(driver_value) over (
            partition by data_area_id, fiscal_year, fiscal_period
        ) as driver_weight
    from {{ ref('allocation_drivers_revenue') }}
    where driver_value > 0
),

{# ---- STEP 1: IT Cost Allocation (ALLOC_001) ---- #}
step1_rule as (
    select * from all_rules where step_order = 1
),

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

step1_allocated as (
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
    from step1_pool as sp
    cross join step1_rule as r
    inner join drivers_headcount as d
        on sp.data_area_id = d.data_area_id
        and sp.fiscal_year = {{ cast_to_uint16('d.fiscal_year') }}
        and sp.fiscal_period = {{ cast_to_uint8('d.fiscal_period') }}
    where d.cost_center != r.source_cost_center
),

{# ---- STEP 2: Facility Allocation (ALLOC_002) ---- #}
{# Pool = TB base + any step 1 amounts landing in FACILITY cost center #}
step2_rule as (
    select * from all_rules where step_order = 2
),

step2_pool as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        {{ cast_to_float64('sum(tb.amount)') }} + coalesce(sum(s1.allocated_amount), 0) as pool_amount
    from tb_base as tb
    cross join step2_rule as r
    left join step1_allocated as s1
        on tb.data_area_id = s1.data_area_id
        and tb.fiscal_year = s1.fiscal_year
        and tb.fiscal_period = s1.fiscal_period
        and s1.target_cost_center = r.source_cost_center
        and {{ cast_to_string('s1.target_account') }} = {{ cast_to_string('r.source_account') }}
    where tb.main_account = {{ cast_to_string('r.source_account') }}
      and tb.{{ get_allocation_cost_center_dim() }} = r.source_cost_center
    group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period
),

step2_allocated as (
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
    from step2_pool as sp
    cross join step2_rule as r
    inner join drivers_sqm as d
        on sp.data_area_id = d.data_area_id
        and sp.fiscal_year = {{ cast_to_uint16('d.fiscal_year') }}
        and sp.fiscal_period = {{ cast_to_uint8('d.fiscal_period') }}
    where d.cost_center != r.source_cost_center
),

{# ---- STEP 3: Management Fee Allocation (ALLOC_003) ---- #}
{# Pool = TB base + any step 1+2 amounts landing in MGMT cost center #}
step3_rule as (
    select * from all_rules where step_order = 3
),

{# Sum of prior step amounts cascading into step 3's source cost center #}
prior_to_step3 as (
    select
        s.data_area_id as data_area_id,
        s.fiscal_year as fiscal_year,
        s.fiscal_period as fiscal_period,
        sum(s.allocated_amount) as cascade_amount
    from (
        select data_area_id, fiscal_year, fiscal_period, target_cost_center, target_account, allocated_amount from step1_allocated
        union all
        select data_area_id, fiscal_year, fiscal_period, target_cost_center, target_account, allocated_amount from step2_allocated
    ) as s
    inner join step3_rule as r
        on s.target_cost_center = r.source_cost_center
        and s.target_account = {{ cast_to_string('r.source_account') }}
    group by s.data_area_id, s.fiscal_year, s.fiscal_period
),

step3_pool as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        {{ cast_to_float64('sum(tb.amount)') }} + coalesce(max(p.cascade_amount), 0) as pool_amount
    from tb_base as tb
    cross join step3_rule as r
    left join prior_to_step3 as p
        on tb.data_area_id = p.data_area_id
        and tb.fiscal_year = p.fiscal_year
        and tb.fiscal_period = p.fiscal_period
    where tb.main_account = {{ cast_to_string('r.source_account') }}
      and tb.{{ get_allocation_cost_center_dim() }} = r.source_cost_center
    group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period
),

step3_allocated as (
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
    from step3_pool as sp
    cross join step3_rule as r
    inner join drivers_revenue as d
        on sp.data_area_id = d.data_area_id
        and sp.fiscal_year = {{ cast_to_uint16('d.fiscal_year') }}
        and sp.fiscal_period = {{ cast_to_uint8('d.fiscal_period') }}
    where d.cost_center != r.source_cost_center
),

{# ---- UNION all steps ---- #}
all_allocations as (
    select * from step1_allocated
    union all
    select * from step2_allocated
    union all
    select * from step3_allocated
)

select * from all_allocations

{% endmacro %}
