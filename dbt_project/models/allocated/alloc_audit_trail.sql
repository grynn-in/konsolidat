{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-21 + PRD-ALLOCATED-LAYER PR1: run traceability over epm_allocated.alloc_results #}

with allocation_runs as (
    select
        allocation_run_id,
        fiscal_year,
        fiscal_period,
        status,
        run_by,
        run_at,
        reversal_of
    from {{ source('epm_staging', 'allocation_runs') }}
),

audit_trail as (
    select
        res.scenario_id,
        ar.allocation_run_id,
        ar.status as run_status,
        ar.run_by,
        ar.run_at,
        ar.reversal_of,
        res.allocation_rule_id,
        res.step_order,
        res.data_area_id,
        res.fiscal_year as fiscal_year,
        res.fiscal_period as fiscal_period,
        res.source_account,
        res.source_cost_center,
        res.target_cost_center,
        res.target_account,
        res.driver_type,
        res.pool_amount,
        res.driver_weight,
        case
            when ar.status = 'Reversed' then -res.allocated_amount
            else res.allocated_amount
        end as allocated_amount
    from allocation_runs as ar
    inner join {{ ref('alloc_results') }} as res
        on ar.fiscal_year = res.fiscal_year
        and ar.fiscal_period = res.fiscal_period
)

select * from audit_trail