{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, fiscal_period, main_account)'
    )
}}

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    dim_cost_center,
    dim_department,
    dim_business_unit,
    period_debit,
    period_credit,
    period_net_amount,
    -- Cumulative balance for BS accounts (running sum within year)
    sum(period_net_amount) over (
        partition by data_area_id, main_account, dim_cost_center, dim_department
        order by fiscal_year, fiscal_period
    ) as cumulative_balance,
    transaction_count
from {{ ref('gold_trial_balance') }}
where is_balance_sheet = 1
