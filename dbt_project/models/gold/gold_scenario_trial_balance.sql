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

-- BUDGET/FORECAST from write-back API (staging table)
select
    scenario_id,
    legal_entity_id as data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    '' as account_name,
    '' as account_type_name,
    {{ dim_select(dims=get_budget_dimensions()) }},
    amount,
    'api_input' as data_source
from {{ source('epm_staging', 'budget_input') }}
