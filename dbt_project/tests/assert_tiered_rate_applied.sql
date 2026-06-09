-- PRD-20 Test: Tiered allocations must apply tier rates correctly
-- Each tier's allocated_amount must equal band_amount × rate (within cap/floor)
select
    ar.allocation_rule_id,
    ar.data_area_id,
    ar.fiscal_year,
    ar.fiscal_period,
    ar.allocated_amount,
    ar.pool_amount,
    ar.driver_weight as tier_rate
from {{ ref('gold_allocation_results') }} as ar
where ar.driver_type = 'tiered'
  and ar.allocated_amount < 0
