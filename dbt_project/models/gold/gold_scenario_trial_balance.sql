{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

-- ACTUAL: from gold_trial_balance (GL-sourced), stamped with the site's declared
-- actual scenario: the single active scenario_definitions row of type 'actual'
-- (PR #211 review 2, konsolidat#206). With none or several declared, the rows
-- keep 'ACTUAL', and assert_scenario_rows_declared names the problem instead of
-- this model failing.
select
    sd.actual_scenario_id as scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    period_net_amount as amount,
    'gl' as data_source
from {{ ref('gold_trial_balance') }}
cross join (
    select
        if(uniqExact(scenario_id) = 1, any(scenario_id), 'ACTUAL') as actual_scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'actual'
      and is_active = 1
) as sd

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
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    accounting_currency_amount as amount,
    'd365_budget' as data_source
from {{ ref('silver_budget_entries') }}

union all

-- BUDGET/FORECAST from the canonical budget fact (annual-spread + manual
-- monthly, grynn-in/konsolidat#94). Replaces the empty epm_staging.budget_input
-- placeholder, which nothing populated — so app-entered budgets never reached
-- this scenario fact. gold_spread_budget scenario_ids (BUDGET_2024/2025,
-- FORECAST_*) are disjoint from the declared actual and D365 'BUDGET' branches
-- above, so no double-count.
-- gold_spread_budget now carries one row per layer (base/challenge/management/
-- board); the scenario TB is the FINAL budget, so layers are summed back to one
-- row per (scenario, entity, period, account, dims) here.
select
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    '' as account_name,
    '' as account_type_name,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    {{ cast_to_decimal128('sum(period_amount)', 2) }} as amount,
    'budget' as data_source
from {{ ref('gold_spread_budget') }}
group by
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account
    {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
