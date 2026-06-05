{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-7: Variance analysis — actual vs budget with favorable/unfavorable logic #}

{% set budget_dims = get_budget_dimensions() %}

with actuals as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims) }},
        sum(amount) as actual_amount
    from {{ ref('gold_scenario_trial_balance') }}
    where scenario_id = 'ACTUAL'
    group by data_area_id, fiscal_year, fiscal_period, main_account,
             account_name, account_type_name, {{ dim_group_by(dims=budget_dims) }}
),

budgets as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        {{ dim_select(dims=budget_dims) }},
        sum(amount) as budget_amount
    from {{ ref('gold_scenario_trial_balance') }}
    where scenario_id = 'BUDGET'
    group by data_area_id, fiscal_year, fiscal_period, main_account,
             {{ dim_group_by(dims=budget_dims) }}
),

{# Get account metadata for accounts that only appear in budget #}
account_meta as (
    select distinct
        main_account_id as main_account,
        account_name,
        account_type_name,
        is_pnl
    from {{ ref('silver_main_accounts') }}
),

combined as (
    select
        coalesce(a.data_area_id, b.data_area_id) as data_area_id,
        coalesce(a.fiscal_year, b.fiscal_year) as fiscal_year,
        coalesce(a.fiscal_period, b.fiscal_period) as fiscal_period,
        coalesce(a.main_account, b.main_account) as main_account,
        coalesce(a.account_name, am.account_name, '') as account_name,
        coalesce(a.account_type_name, am.account_type_name, '') as account_type_name,
        coalesce(am.is_pnl, 0) as is_pnl,
        {{ dim_coalesce('a', 'b', dims=budget_dims) }},
        coalesce(a.actual_amount, 0) as actual_amount,
        b.budget_amount as budget_amount,
        coalesce(a.actual_amount, 0) - coalesce(b.budget_amount, 0) as variance_abs,
        case
            when b.budget_amount is not null and b.budget_amount != 0
            then (coalesce(a.actual_amount, 0) - b.budget_amount) / abs(b.budget_amount) * 100
            else null
        end as variance_pct,
        {# Favorable logic: revenue up = good, expense down = good #}
        case
            when b.budget_amount is null then false
            when coalesce(am.is_pnl, 0) = 0 then false
            when coalesce(a.account_type_name, am.account_type_name, '') in ('Revenue', 'Income')
                then coalesce(a.actual_amount, 0) > b.budget_amount
            when coalesce(a.account_type_name, am.account_type_name, '') in ('Expense', 'Cost of goods sold')
                then coalesce(a.actual_amount, 0) < b.budget_amount
            else false
        end as variance_favorable
    from actuals as a
    full outer join budgets as b
        on a.data_area_id = b.data_area_id
        and a.fiscal_year = b.fiscal_year
        and a.fiscal_period = b.fiscal_period
        and a.main_account = b.main_account
        {{ dim_join_on('a', 'b', dims=budget_dims) }}
    left join account_meta as am
        on coalesce(a.main_account, b.main_account) = am.main_account
)

select * from combined
