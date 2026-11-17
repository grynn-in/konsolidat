{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-7: Variance analysis — actual vs budget with a three-state favourability.

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
   lost the entity and account of budget-only lines.

   CURRENCY (konsol#348 S3 B8, QB3 a): the currency joins the grain, so a
   budget row never nets against an actual in another currency. The actuals
   carry the entity's accounting currency and a budget line its own
   (gold_scenario_trial_balance, B6); where they differ, the grain comes out
   as two rows, one per currency, each with the other side missing.
   assert_variance_single_currency names such a grain; B7 refuses the line
   upstream. #}

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
        {{ dim_select(dims=budget_dims, trailing=true) }}
        currency,
        amount
    from {{ ref('gold_scenario_trial_balance') }}
    where scenario_id in (select scenario_id from actual_scenarios)
       or scenario_id in (select scenario_id from budget_scenarios)
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
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims, trailing=true) }}
        currency,
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
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims, trailing=true) }}
        currency,
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
        {{ dim_select(dims=budget_dims, trailing=true) }}
        currency,
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
             {{ dim_group_by(dims=budget_dims, trailing=true) }} currency, budget_scenario_id
),

{# Get account metadata for accounts that only appear in budget #}
account_meta as (
    select distinct
        main_account_id as main_account,
        account_name,
        account_type_name,
        is_pnl,
        normal_balance
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
        g.currency as currency,
        g.actual_amount as actual_amount,
        g.budget_amount as budget_amount,
        g.actual_amount - coalesce(g.budget_amount, 0) as variance_abs,
        case
            when g.budget_amount is not null and g.budget_amount != 0
            then (g.actual_amount - g.budget_amount) / abs(g.budget_amount) * 100
            else null
        end as variance_pct,
        {# Favourability by the account's normal balance (konsol#348 S3 B13 then
           S6 WB1, S6-Q4 a; BUD-7-a; konsolidat#214), read from the chart:
           silver_main_accounts.normal_balance, konsol's Main Account. Three
           states in one String, never a summable flag:
             'favourable'     the signed actual is below the signed budget;
             'unfavourable'   above it;
             'not_applicable' no favourable direction: a
                              balance-sheet account, an account whose normal
                              balance is not declared or that is not in the
                              chart (join_use_nulls=0 reads ''), and a zero
                              variance (the statement shows "On budget").
           No budget line is a budget of zero, never "no direction"
           ("Unbudgeted is unfavourable", Deepak Pai, 22 Sep 2026: budget 0,
           actual 10 is unfavourable 10), the zero variance_abs uses.
           Amounts are signed debit - credit (QB6 a), so a credit-normal
           account (revenue) is favourable when the actual is more credit than
           the budget, i.e. its signed actual is below its signed budget, and a
           debit-normal account (expense) when the actual is less debit, again
           below the budget. Both branches read "actual below budget" under
           debit-positive signs; normal_balance decides only whether a
           direction is declared (BUD-7-a: an undeclared account is reported,
           not refused). assert_variance_favourability_follows_normal_balance
           checks it from the chart and the amounts. #}
        multiIf(
            coalesce(am.is_pnl, 0) = 0, 'not_applicable',
            am.normal_balance not in ('Credit', 'Debit'), 'not_applicable',
            g.actual_amount < coalesce(g.budget_amount, 0), 'favourable',
            g.actual_amount > coalesce(g.budget_amount, 0), 'unfavourable',
            'not_applicable'
        ) as variance_favourability,
        g.budget_scenario_id as budget_scenario_id
    from grouped as g
    left join account_meta as am
        on g.main_account = am.main_account
)

select * from combined
