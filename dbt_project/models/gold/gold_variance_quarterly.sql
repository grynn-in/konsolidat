{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Quarterly variance — actual vs budget per fiscal quarter.

   konsolidat#206: which scenario is the actual and which are budgets is what
   each site declares on konsol's Scenario doctype (epm_gold.scenario_definitions
   .scenario_type, active only), never a scenario code. Every active
   budget-type scenario gets its own set of variance rows, keyed by
   budget_scenario_id: the actuals are repeated against each budget that has
   lines for their entity and fiscal year, and two budgets are never summed.
   An actual no budget scenario covers comes out once with budget_scenario_id
   '' and no budget.

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
        if(stb.scenario_id in (select scenario_id from actual_scenarios), 'actual', 'budget') as scenario_type,
        stb.scenario_id as scenario_id,
        stb.data_area_id as data_area_id,
        stb.fiscal_year as fiscal_year,
        ph.fiscal_quarter as fiscal_quarter,
        stb.main_account as main_account,
        stb.account_name as account_name,
        stb.account_type_name as account_type_name,
        {% for d in budget_dims %}
        stb.{{ d.name }} as {{ d.name }},
        {% endfor %}
        stb.amount as amount
    from {{ ref('gold_scenario_trial_balance') }} as stb
    left join {{ ref('gold_period_hierarchy') }} as ph
        on stb.fiscal_period = ph.fiscal_period
    where stb.scenario_id in (select scenario_id from actual_scenarios)
       or stb.scenario_id in (select scenario_id from budget_scenarios)
),

{# the (entity, fiscal year)s each budget scenario has lines for #}
budget_years as (
    select distinct
        scenario_id as pair_scenario_id,
        data_area_id as pair_data_area_id,
        fiscal_year as pair_fiscal_year
    from typed
    where scenario_type = 'budget'
),

{# PR #211 review 3: an actual (entity, fiscal year) is compared only with the
   budget scenarios that budget that entity and year; with none, it comes out
   once under '' (never once per scenario, never against another year's budget) #}
actual_years as (
    select distinct
        data_area_id as pair_data_area_id,
        fiscal_year as pair_fiscal_year
    from typed
    where scenario_type = 'actual'
),

pairings as (
    select
        a.pair_data_area_id as pair_data_area_id,
        a.pair_fiscal_year as pair_fiscal_year,
        coalesce(b.pair_scenario_id, '') as budget_scenario_id
    from actual_years as a
    left join budget_years as b
        on a.pair_data_area_id = b.pair_data_area_id
       and a.pair_fiscal_year = b.pair_fiscal_year
),

paired as (
    select
        scenario_type,
        data_area_id,
        fiscal_year,
        fiscal_quarter,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims) }},
        amount,
        budget_scenario_id
    from typed
    inner join pairings
        on typed.data_area_id = pairings.pair_data_area_id
       and typed.fiscal_year = pairings.pair_fiscal_year
    where scenario_type = 'actual'

    union all

    select
        scenario_type,
        data_area_id,
        fiscal_year,
        fiscal_quarter,
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
        fiscal_quarter,
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
    group by data_area_id, fiscal_year, fiscal_quarter, main_account,
             {{ dim_group_by(dims=budget_dims) }}, budget_scenario_id
)

select
    data_area_id,
    fiscal_year,
    fiscal_quarter,
    main_account,
    account_name,
    account_type_name,
    {{ dim_select(dims=budget_dims) }},
    actual_amount,
    budget_amount,
    actual_amount - coalesce(budget_amount, 0) as variance_abs,
    case
        when budget_amount is not null and budget_amount != 0
        then (actual_amount - budget_amount) / abs(budget_amount) * 100
        else null
    end as variance_pct,
    budget_scenario_id
from grouped
