{# konsolidat#206 (PR #211 review 3): an actual is compared only with the budget
   scenarios that budget its entity and fiscal year. A variance row that pairs a
   budget scenario with a (data_area_id, fiscal_year) where that scenario has no
   budget line would show the whole actual as variance against a budget that
   does not exist. An actual grain no budget scenario covers comes out once,
   under budget_scenario_id ''.

   One row per problem:
     unbudgeted_year  - a (budget_scenario_id, data_area_id, fiscal_year) in the
                        model where the scenario has no budget line;
     duplicate_blank  - an actual grain under more than one '' row. #}

{% set budget_dims = get_budget_dimensions() %}

with budget_years as (
    select distinct
        t.scenario_id as budget_scenario_id,
        t.data_area_id as data_area_id,
        t.fiscal_year as fiscal_year
    from {{ ref('gold_scenario_trial_balance') }} as t
    inner join (
        select distinct scenario_id
        from {{ source('epm_gold', 'scenario_definitions') }}
        where scenario_type = 'budget'
          and is_active = 1
    ) as s
        on t.scenario_id = s.scenario_id
),

unbudgeted as (
    select
        'unbudgeted_year' as problem,
        v.budget_scenario_id as budget_scenario_id,
        v.data_area_id as data_area_id,
        v.fiscal_year as fiscal_year,
        count() as variance_rows
    from {{ ref('gold_variance_analysis') }} as v
    where v.budget_scenario_id != ''
      and (v.budget_scenario_id, v.data_area_id, v.fiscal_year) not in (
          select budget_scenario_id, data_area_id, fiscal_year from budget_years
      )
    group by v.budget_scenario_id, v.data_area_id, v.fiscal_year
),

{# filter the '' rows in a subquery: a select-list alias `'' as budget_scenario_id`
   next to `where budget_scenario_id = ''` would make ClickHouse compare the alias
   (always true), not the column #}
blank_rows as (
    select *
    from {{ ref('gold_variance_analysis') }}
    where budget_scenario_id = ''
),

duplicate_blank as (
    select
        'duplicate_blank' as problem,
        '' as budget_scenario_id,
        data_area_id,
        fiscal_year,
        count() as variance_rows
    from blank_rows
    group by data_area_id, fiscal_year, fiscal_period, main_account,
             {{ dim_group_by(dims=budget_dims) }}
    having count() > 1
)

select problem, budget_scenario_id, data_area_id, fiscal_year, variance_rows from unbudgeted
union all
select problem, budget_scenario_id, data_area_id, fiscal_year, variance_rows from duplicate_blank
