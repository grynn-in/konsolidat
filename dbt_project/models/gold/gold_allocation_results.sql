{{
    config(
        materialized='view'
    )
}}

{# Deprecated alias — PRD-ALLOCATED-LAYER PR1. Drop after one release cycle. #}
select
    allocation_rule_id,
    step_order,
    data_area_id,
    fiscal_year,
    fiscal_period,
    source_account,
    source_cost_center,
    target_cost_center,
    target_account,
    driver_type,
    pool_amount,
    driver_weight,
    allocated_amount
from {{ ref('alloc_results') }}
where scenario_id = 'ACTUAL'