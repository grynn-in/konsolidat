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
    -- D365 account type enum to readable name
    case account_type
        when '0' then 'Profit and loss'
        when '1' then 'Revenue'
        when '2' then 'Expense'
        when '3' then 'Balance sheet'
        when '4' then 'Asset'
        when '5' then 'Liability'
        when '6' then 'Equity'
        when '7' then 'Total'
        when 'ProfitAndLoss' then 'Profit and loss'
        when 'Revenue' then 'Revenue'
        when 'Expense' then 'Expense'
        when 'BalanceSheet' then 'Balance sheet'
        when 'Asset' then 'Asset'
        when 'Liability' then 'Liability'
        when 'Equity' then 'Equity'
        when 'Total' then 'Total'
        else account_type
    end as account_type_name,
    -- Classification flags for filtering
    account_type in ('0', '1', '2', 'ProfitAndLoss', 'Revenue', 'Expense') as is_pnl,
    account_type in ('3', '4', '5', '6', 'BalanceSheet', 'Asset', 'Liability', 'Equity') as is_balance_sheet,
    main_account_category,
    debit_credit_default,
    chart_of_accounts,
    is_suspended
from {{ ref('bronze_main_accounts') }}
where account_type != '7' and account_type != 'Total'  -- Exclude total accounts
