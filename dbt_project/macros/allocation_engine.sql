{% macro allocation_engine(rule_id, driver_seed) %}
{#
    Generic allocation engine macro.
    1. Reads the allocation rule from seed
    2. Gets the source pool amount from gold_trial_balance
    3. Computes driver weights from the driver seed
    4. Distributes pool proportionally across targets
#}

with rule as (
    select *
    from {{ ref('allocation_rules') }}
    where allocation_rule_id = '{{ rule_id }}'
),

source_pool as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        sum(tb.period_net_amount) as pool_amount
    from {{ ref('gold_trial_balance') }} as tb
    cross join rule as r
    where tb.main_account = {{ cast_to_string('r.source_account') }}
      and tb.{{ get_allocation_cost_center_dim() }} = r.source_cost_center
    group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period
),

drivers as (
    select
        data_area_id,
        cost_center,
        fiscal_year,
        fiscal_period,
        driver_value,
        driver_value / sum(driver_value) over (
            partition by data_area_id, fiscal_year, fiscal_period
        ) as driver_weight
    from {{ ref(driver_seed) }}
),

allocated as (
    select
        r.allocation_rule_id as allocation_rule_id,
        sp.data_area_id as data_area_id,
        sp.fiscal_year as fiscal_year,
        sp.fiscal_period as fiscal_period,
        {{ cast_to_string('r.source_account') }} as source_account,
        d.cost_center as target_cost_center,
        {{ cast_to_string('r.target_account') }} as target_account,
        r.driver_type as driver_type,
        sp.pool_amount as pool_amount,
        d.driver_weight as driver_weight,
        sp.pool_amount * d.driver_weight as allocated_amount
    from source_pool as sp
    cross join rule as r
    inner join drivers as d
        on sp.data_area_id = d.data_area_id
        and sp.fiscal_year = {{ cast_to_uint16('d.fiscal_year') }}
        and sp.fiscal_period = {{ cast_to_uint8('d.fiscal_period') }}
    where d.cost_center != r.source_cost_center  {# Don't allocate back to source #}
)

select * from allocated

{% endmacro %}
