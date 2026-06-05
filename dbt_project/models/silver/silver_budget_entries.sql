{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, transaction_date, main_account)',
        partition_by='toYYYYMM(transaction_date)'
    )
}}

select
    btl.recid,
    bre.data_area_id,
    btl.transaction_date,
    toYear(btl.transaction_date) as fiscal_year,
    toMonth(btl.transaction_date) as fiscal_period,
    btl.main_account,
    btl.accounting_currency_amount,
    btl.transaction_currency_amount,
    btl.transaction_currency,
    btl.dim_cost_center,
    btl.dim_department,
    bre.budget_model_id,
    bre.budget_transaction_code,
    bre.budget_status,
    bre.document_date as register_date,
    btl.include_in_cash_flow
from {{ ref('bronze_budget_transaction_lines') }} as btl
inner join {{ ref('bronze_budget_register_entries') }} as bre
    on btl.budget_register_entry_recid = bre.recid
where bre.budget_status in ('Completed', 'Approved', '2', '3')  -- Only posted budgets
