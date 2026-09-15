{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# YTD variance — actual vs budget as running totals through each fiscal period.

   konsolidat#206: which scenario is the actual and which are budgets is what
   each site declares on konsol's Scenario doctype (epm_gold.scenario_definitions
   .scenario_type, active only), never a scenario code. Every active
   budget-type scenario gets its own set of variance rows, keyed by
   budget_scenario_id: the actuals are repeated against each budget, and two
   budgets are never summed. With no budget scenario at all, the actuals come
   out once with budget_scenario_id '' and no budget.

   One stream plus conditional aggregation per period, then the running totals
   per (grain, budget_scenario_id), rather than a full outer join of two
   separately-accumulated sides: under join_use_nulls=0 the unmatched side of a
   join fills '' and 0, which lost the entity and account of budget-only lines. #}

{% set budget_dims = get_budget_dimensions() %}

with actual_scenarios as (
    select distinct scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'actual'
      and is_active = 1
),

budget_scenarios as (
    select distinct scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'budget'
      and is_active = 1
),

typed as (
    select
        if(scenario_id in (select scenario_id from actual_scenarios), 'actual', 'budget') as scenario_type,
        scenario_id,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims) }},
        amount
    from {{ ref('gold_scenario_trial_balance') }}
    where scenario_id in (select scenario_id from actual_scenarios)
       or scenario_id in (select scenario_id from budget_scenarios)
),

budget_ids as (
    select distinct scenario_id as budget_scenario_id
    from typed
    where scenario_type = 'budget'
),

{# the budgets the actuals are compared with; '' when there is none #}
pairings as (
    select budget_scenario_id from budget_ids
    union all
    select '' as budget_scenario_id
    where (select count() from budget_ids) = 0
),

paired as (
    select
        scenario_type,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims) }},
        amount,
        budget_scenario_id
    from typed
    cross join pairings
    where scenario_type = 'actual'

    union all

    select
        scenario_type,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims) }},
        amount,
        scenario_id as budget_scenario_id
    from typed
    where scenario_type = 'budget'
),

by_period as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        {{ dim_select(dims=budget_dims) }},
        budget_scenario_id,
        max(account_name) as account_name,
        max(account_type_name) as account_type_name,
        sumIf(amount, scenario_type = 'actual') as actual_amount,
        sumIf(amount, scenario_type = 'budget') as budget_amount,
        countIf(scenario_type = 'budget') as budget_lines
    from paired
    group by data_area_id, fiscal_year, fiscal_period, main_account,
             {{ dim_group_by(dims=budget_dims) }}, budget_scenario_id
),

running as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims) }},
        budget_scenario_id,
        sum(actual_amount) over w as ytd_actual,
        sum(budget_amount) over w as ytd_budget_sum,
        sum(budget_lines) over w as ytd_budget_lines
    from by_period
    window w as (
        partition by data_area_id, fiscal_year, main_account,
                     {{ dim_partition_by(dims=budget_dims) }}, budget_scenario_id
        order by fiscal_period
        rows between unbounded preceding and current row
    )
),

ytd as (
    select
        *,
        {# no budget line to date for this grain in this scenario: null, not 0 #}
        if(ytd_budget_lines > 0, ytd_budget_sum, null) as ytd_budget
    from running
)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    {{ dim_select(dims=budget_dims) }},
    ytd_actual,
    ytd_budget,
    ytd_actual - coalesce(ytd_budget, 0) as ytd_variance_abs,
    case
        when ytd_budget is not null and ytd_budget != 0
        then (ytd_actual - ytd_budget) / abs(ytd_budget) * 100
        else null
    end as ytd_variance_pct,
    budget_scenario_id
from ytd
