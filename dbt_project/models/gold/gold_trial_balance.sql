{{
    config(
        engine='SummingMergeTree()',
        order_by='(data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department)'
    )
}}

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    is_balance_sheet,
    is_pnl,
    dim_cost_center,
    dim_department,
    dim_business_unit,
    sum(debit_amount) as period_debit,
    sum(credit_amount) as period_credit,
    sum(accounting_currency_amount) as period_net_amount,
    count(*) as transaction_count
from {{ ref('silver_gl_entries') }}
group by
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    is_balance_sheet,
    is_pnl,
    dim_cost_center,
    dim_department,
    dim_business_unit
