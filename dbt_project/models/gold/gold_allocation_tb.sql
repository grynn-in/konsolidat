{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Allocation movements re-grained to trial-balance shape so K.EPM can read the
   allocation layer SEPARATELY from actuals (Dataset scenario_key 'allocated').

   alloc_results is at a rule/source->target grain (no main_account). Here each
   allocation posts two signed legs at TB grain:
     - target leg (debit, +): main_account = target_account, cost lands here
     - source leg (credit, -): main_account = source_account, cost leaves here
   So `allocated` on its own nets to ~0 per (entity, period); actuals + allocated
   = the post-allocation trial balance.

   Cost-center grain only: the engine allocates by cost center, so dim_department
   is not modelled. scenario_id is carried (alloc_results = 'ACTUAL') so the fact
   can expose has_scenario_id. #}

with alloc as (
    select * from {{ ref('alloc_results') }}
)

-- target leg (debit): cost lands here
select
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    toString(target_account) as main_account,
    target_cost_center as dim_cost_center,
    {{ cast_to_float64('sum(allocated_amount)') }} as period_net_amount
from alloc
group by scenario_id, data_area_id, fiscal_year, fiscal_period,
         target_account, target_cost_center

union all

-- source leg (credit): cost leaves here
select
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    toString(source_account) as main_account,
    source_cost_center as dim_cost_center,
    -1 * {{ cast_to_float64('sum(allocated_amount)') }} as period_net_amount
from alloc
group by scenario_id, data_area_id, fiscal_year, fiscal_period,
         source_account, source_cost_center
