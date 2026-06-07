{{
    config(
        engine='MergeTree()',
        order_by='(main_account_id)'
    )
}}

select
    main_account_id,
    account_name,
    account_type,
    {{ map_account_type('account_type') }} as account_type_name,
    -- Classification flags for filtering
    account_type in ('0', '1', '2', 'ProfitAndLoss', 'Revenue', 'Expense') as is_pnl,
    account_type in ('3', '4', '5', '6', 'BalanceSheet', 'Asset', 'Liability', 'Equity') as is_balance_sheet,
    main_account_category,
    debit_credit_default,
    chart_of_accounts,
    is_suspended
from {{ ref('bronze_main_accounts') }}
where account_type != '7' and account_type != 'Total'  -- Exclude total accounts
