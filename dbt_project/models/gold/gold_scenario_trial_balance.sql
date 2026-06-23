{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

-- ACTUAL: from gold_trial_balance (GL-sourced)
select
    'ACTUAL' as scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    {{ dim_select(dims=get_budget_dimensions()) }},
    period_net_amount as amount,
    'gl' as data_source
from {{ ref('gold_trial_balance') }}

union all

-- BUDGET (from D365): from silver_budget_entries
select
    'BUDGET' as scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    '' as account_name,
    '' as account_type_name,
    {{ dim_select(dims=get_budget_dimensions()) }},
    accounting_currency_amount as amount,
    'd365_budget' as data_source
from {{ ref('silver_budget_entries') }}

union all

-- BUDGET/FORECAST from the canonical budget fact (annual-spread + manual
-- monthly, grynn-in/konsolidat#94). Replaces the empty epm_staging.budget_input
-- placeholder, which nothing populated — so app-entered budgets never reached
-- this scenario fact. gold_spread_budget scenario_ids (BUDGET_2024/2025,
-- FORECAST_*) are disjoint from the 'ACTUAL' and D365 'BUDGET' branches above,
-- so no double-count.
select
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    '' as account_name,
    '' as account_type_name,
    {{ dim_select(dims=get_budget_dimensions()) }},
    {{ cast_to_decimal128('period_amount', 2) }} as amount,
    'budget' as data_source
from {{ ref('gold_spread_budget') }}
