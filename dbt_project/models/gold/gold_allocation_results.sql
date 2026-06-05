{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, fiscal_period, allocation_rule_id, target_cost_center)'
    )
}}

-- IT Cost Allocation by headcount
{{ allocation_engine('ALLOC_001', 'allocation_drivers_headcount') }}

-- Additional allocation rules can be unioned here:
-- UNION ALL
-- {{ allocation_engine('ALLOC_002', 'allocation_drivers_sqm') }}
