{# konsolidat#206 (PR #211 review 3): an actual is compared only with the budget
   scenarios that budget its entity and fiscal year. A variance row that pairs a
   budget scenario with a (data_area_id, fiscal_year) where that scenario has no
   budget line would show the whole actual as variance against a budget that
   does not exist. An actual grain no budget scenario covers comes out once,
   under budget_scenario_id ''.

   Checked on each variance model (its period column in brackets):
   gold_variance_analysis (fiscal_period), gold_variance_quarterly
   (fiscal_quarter).

   One row per problem:
     unbudgeted_year  - a (budget_scenario_id, data_area_id, fiscal_year) in the
                        model where the scenario has no budget line;
     duplicate_blank  - an actual grain under more than one '' row. #}

-- depends_on: {{ ref('gold_variance_analysis') }}
-- depends_on: {{ ref('gold_variance_quarterly') }}

{% set budget_dims = get_budget_dimensions() %}
{% set variance_models = [
    ('gold_variance_analysis', 'fiscal_period'),
    ('gold_variance_quarterly', 'fiscal_quarter'),
] %}

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

{% for model_name, period_col in variance_models %}
unbudgeted_{{ loop.index }} as (
    select
        '{{ model_name }}' as model,
        'unbudgeted_year' as problem,
        v.budget_scenario_id as budget_scenario_id,
        v.data_area_id as data_area_id,
        v.fiscal_year as fiscal_year,
        count() as variance_rows
    from {{ ref(model_name) }} as v
    where v.budget_scenario_id != ''
      and (v.budget_scenario_id, v.data_area_id, v.fiscal_year) not in (
          select budget_scenario_id, data_area_id, fiscal_year from budget_years
      )
    group by v.budget_scenario_id, v.data_area_id, v.fiscal_year
),

{# filter the '' rows in a subquery: a select-list alias `'' as budget_scenario_id`
   next to `where budget_scenario_id = ''` would make ClickHouse compare the alias
   (always true), not the column #}
blank_rows_{{ loop.index }} as (
    select *
    from {{ ref(model_name) }}
    where budget_scenario_id = ''
),

duplicate_blank_{{ loop.index }} as (
    select
        '{{ model_name }}' as model,
        'duplicate_blank' as problem,
        '' as budget_scenario_id,
        data_area_id,
        fiscal_year,
        count() as variance_rows
    from blank_rows_{{ loop.index }}
    group by data_area_id, fiscal_year, {{ period_col }}, main_account,
             {{ dim_group_by(dims=budget_dims) }}
    having count() > 1
){% if not loop.last %},{% endif %}

{% endfor %}

{% for model_name, period_col in variance_models %}
select model, problem, budget_scenario_id, data_area_id, fiscal_year, variance_rows from unbudgeted_{{ loop.index }}
union all
select model, problem, budget_scenario_id, data_area_id, fiscal_year, variance_rows from duplicate_blank_{{ loop.index }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
