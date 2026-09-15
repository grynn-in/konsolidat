{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-7: Variance analysis — actual vs budget with favorable/unfavorable logic.

   konsolidat#206: which scenario is the actual and which are budgets is what
   each site declares on konsol's Scenario doctype (epm_gold.scenario_definitions
   .scenario_type, active only), never a scenario code. Every active
   budget-type scenario gets its own set of variance rows, keyed by
   budget_scenario_id: the actuals are repeated against each budget, and two
   budgets are never summed. With no budget scenario at all, the actuals come
   out once with budget_scenario_id '' and no budget.

   One stream plus conditional aggregation rather than a full outer join:
   under join_use_nulls=0 the unmatched side of a join fills '' and 0, which
   lost the entity and account of budget-only lines. #}

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

grouped as (
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
        {# no budget line for this grain in this scenario: null, not 0 #}
        if(countIf(scenario_type = 'budget') > 0,
           sumIf(amount, scenario_type = 'budget'),
           null) as budget_amount
    from paired
    group by data_area_id, fiscal_year, fiscal_period, main_account,
             {{ dim_group_by(dims=budget_dims) }}, budget_scenario_id
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
        g.data_area_id as data_area_id,
        g.fiscal_year as fiscal_year,
        g.fiscal_period as fiscal_period,
        g.main_account as main_account,
        if(g.account_name != '', g.account_name, am.account_name) as account_name,
        if(g.account_type_name != '', g.account_type_name, am.account_type_name) as account_type_name,
        coalesce(am.is_pnl, 0) as is_pnl,
        {% for d in budget_dims %}
        g.{{ d.name }} as {{ d.name }},
        {% endfor %}
        g.actual_amount as actual_amount,
        g.budget_amount as budget_amount,
        g.actual_amount - coalesce(g.budget_amount, 0) as variance_abs,
        case
            when g.budget_amount is not null and g.budget_amount != 0
            then (g.actual_amount - g.budget_amount) / abs(g.budget_amount) * 100
            else null
        end as variance_pct,
        {# Favorable logic: revenue up = good, expense down = good #}
        case
            when g.budget_amount is null then false
            when coalesce(am.is_pnl, 0) = 0 then false
            {# The konsol group chart's account_type vocabulary (konsol#182).
               The generic 'Profit and loss' type has no favourable direction
               by design: it falls to the else. #}
            when if(g.account_type_name != '', g.account_type_name, am.account_type_name) = 'Revenue'
                then g.actual_amount > g.budget_amount
            when if(g.account_type_name != '', g.account_type_name, am.account_type_name) = 'Expense'
                then g.actual_amount < g.budget_amount
            else false
        end as variance_favorable,
        g.budget_scenario_id as budget_scenario_id
    from grouped as g
    left join account_meta as am
        on g.main_account = am.main_account
)

select * from combined
