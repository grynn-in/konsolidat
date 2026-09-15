{# konsolidat#206 (PR #211 review 3): an actual is compared only with the budget
   scenarios that budget its entity and fiscal year. A variance row that pairs a
   budget scenario with a (data_area_id, fiscal_year) where that scenario has no
   budget line would show the whole actual as variance against a budget that
   does not exist. An actual grain no budget scenario covers comes out once,
   under budget_scenario_id ''.

   PR #211 review 2, point 1: the '' (uncovered) rows are checked too. They
   never sit in an entity-year some active budget scenario budgets, and every
   actual grain of an uncovered entity-year has its '' row with the grain's
   actual amount (the running total to date in gold_variance_ytd). Each model
   groups by budget_scenario_id, so a grain cannot have two '' rows.

   Checked on each variance model (its period column in brackets):
   gold_variance_analysis (fiscal_period), gold_variance_quarterly
   (fiscal_quarter, through gold_period_hierarchy as the model maps it),
   gold_variance_ytd (fiscal_period).

   One row per problem:
     unbudgeted_year       - a (budget_scenario_id, data_area_id, fiscal_year) in
                             the model where the scenario has no budget line;
     blank_beside_scenario - a '' (data_area_id, fiscal_year) that some active
                             budget scenario has budget lines for;
     uncovered_missing     - an actual grain of an entity-year no active budget
                             scenario covers with no '' row, or whose '' row
                             carries another actual amount. #}

-- depends_on: {{ ref('gold_variance_analysis') }}
-- depends_on: {{ ref('gold_variance_quarterly') }}
-- depends_on: {{ ref('gold_variance_ytd') }}

{% set budget_dims = get_budget_dimensions() %}
{% set variance_models = [
    ('gold_variance_analysis', 'fiscal_period', 'actual_amount', false),
    ('gold_variance_quarterly', 'fiscal_quarter', 'actual_amount', false),
    ('gold_variance_ytd', 'fiscal_period', 'ytd_actual', true),
] %}

{# every CTE column carries a prefix: a select-list alias that repeats a source
   column name would make ClickHouse resolve the WHERE / GROUP BY to the alias #}
with budget_years as (
    select distinct
        t.scenario_id as y_scenario_id,
        t.data_area_id as y_data_area_id,
        t.fiscal_year as y_fiscal_year
    from {{ ref('gold_scenario_trial_balance') }} as t
    inner join (
        select distinct scenario_id
        from {{ source('epm_gold', 'scenario_definitions') }}
        where scenario_type = 'budget'
          and is_active = 1
    ) as s
        on t.scenario_id = s.scenario_id
),

{# the actual lines, from every active actual-type scenario #}
actual_lines as (
    select
        t.data_area_id as l_data_area_id,
        t.fiscal_year as l_fiscal_year,
        t.fiscal_period as l_fiscal_period,
        ph.fiscal_quarter as l_fiscal_quarter,
        t.main_account as l_main_account,
        {% for d in budget_dims %}
        t.{{ d.name }} as l_{{ d.name }},
        {% endfor %}
        t.amount as l_amount
    from {{ ref('gold_scenario_trial_balance') }} as t
    inner join (
        select distinct scenario_id
        from {{ source('epm_gold', 'scenario_definitions') }}
        where scenario_type = 'actual'
          and is_active = 1
    ) as s
        on t.scenario_id = s.scenario_id
    left join {{ ref('gold_period_hierarchy') }} as ph
        on t.fiscal_period = ph.fiscal_period
),

{# the actual lines of the entity-years no active budget scenario budgets #}
uncovered_lines as (
    select *
    from actual_lines
    where (l_data_area_id, l_fiscal_year) not in (
        select y_data_area_id, y_fiscal_year from budget_years
    )
),

{% for model_name, period_col, actual_col, running in variance_models %}
unbudgeted_{{ loop.index }} as (
    select
        '{{ model_name }}' as p_model,
        'unbudgeted_year' as p_problem,
        v.budget_scenario_id as p_scenario_id,
        v.data_area_id as p_data_area_id,
        toString(v.fiscal_year) as p_fiscal_year,
        '' as p_period,
        '' as p_main_account,
        count() as p_variance_rows,
        toFloat64(0) as p_expected_actual,
        toFloat64(0) as p_variance_actual
    from {{ ref(model_name) }} as v
    where v.budget_scenario_id != ''
      and (v.budget_scenario_id, v.data_area_id, v.fiscal_year) not in (
          select y_scenario_id, y_data_area_id, y_fiscal_year from budget_years
      )
    group by v.budget_scenario_id, v.data_area_id, v.fiscal_year
),

{# the model's '' rows, per grain #}
blank_rows_{{ loop.index }} as (
    select
        v.data_area_id as r_data_area_id,
        v.fiscal_year as r_fiscal_year,
        v.{{ period_col }} as r_period,
        v.main_account as r_main_account,
        {% for d in budget_dims %}
        v.{{ d.name }} as r_{{ d.name }},
        {% endfor %}
        count() as r_rows,
        sum(v.{{ actual_col }}) as r_actual
    from {{ ref(model_name) }} as v
    where v.budget_scenario_id = ''
    group by r_data_area_id, r_fiscal_year, r_period, r_main_account
        {% for d in budget_dims %}, r_{{ d.name }}{% endfor %}
),

blank_beside_scenario_{{ loop.index }} as (
    select
        '{{ model_name }}' as p_model,
        'blank_beside_scenario' as p_problem,
        '' as p_scenario_id,
        r_data_area_id as p_data_area_id,
        toString(r_fiscal_year) as p_fiscal_year,
        '' as p_period,
        '' as p_main_account,
        sum(r_rows) as p_variance_rows,
        toFloat64(0) as p_expected_actual,
        toFloat64(0) as p_variance_actual
    from blank_rows_{{ loop.index }}
    where (r_data_area_id, r_fiscal_year) in (
        select y_data_area_id, y_fiscal_year from budget_years
    )
    group by r_data_area_id, r_fiscal_year
),

{# the uncovered actual grains in the model's grain, with their amount #}
uncovered_grain_{{ loop.index }} as (
    select
        g_data_area_id,
        g_fiscal_year,
        g_period,
        g_main_account,
        {% for d in budget_dims %}
        g_{{ d.name }},
        {% endfor %}
        {% if running %}
        sum(g_amount) over (
            partition by g_data_area_id, g_fiscal_year, g_main_account
                {% for d in budget_dims %}, g_{{ d.name }}{% endfor %}
            order by g_period
            rows between unbounded preceding and current row
        ) as g_expected
        {% else %}
        g_amount as g_expected
        {% endif %}
    from (
        select
            l_data_area_id as g_data_area_id,
            l_fiscal_year as g_fiscal_year,
            l_{{ period_col }} as g_period,
            l_main_account as g_main_account,
            {% for d in budget_dims %}
            l_{{ d.name }} as g_{{ d.name }},
            {% endfor %}
            sum(l_amount) as g_amount
        from uncovered_lines
        group by g_data_area_id, g_fiscal_year, g_period, g_main_account
            {% for d in budget_dims %}, g_{{ d.name }}{% endfor %}
    )
),

{# a missing '' row joins as 0 rows (join_use_nulls=0) #}
uncovered_missing_{{ loop.index }} as (
    select
        '{{ model_name }}' as p_model,
        'uncovered_missing' as p_problem,
        '' as p_scenario_id,
        g.g_data_area_id as p_data_area_id,
        toString(g.g_fiscal_year) as p_fiscal_year,
        toString(g.g_period) as p_period,
        g.g_main_account as p_main_account,
        toUInt64(r.r_rows) as p_variance_rows,
        toFloat64(g.g_expected) as p_expected_actual,
        toFloat64(r.r_actual) as p_variance_actual
    from uncovered_grain_{{ loop.index }} as g
    left join blank_rows_{{ loop.index }} as r
        on g.g_data_area_id = r.r_data_area_id
       and g.g_fiscal_year = r.r_fiscal_year
       and g.g_period = r.r_period
       and g.g_main_account = r.r_main_account
       {% for d in budget_dims %}
       and g.g_{{ d.name }} = r.r_{{ d.name }}
       {% endfor %}
    where r.r_rows = 0
       or abs(toFloat64(g.g_expected) - toFloat64(r.r_actual)) > {{ materiality_floor() }}
){% if not loop.last %},{% endif %}

{% endfor %}

{% for model_name, period_col, actual_col, running in variance_models %}
{% set model_index = loop.index %}
{% set last_model = loop.last %}
{% for cte in ['unbudgeted', 'blank_beside_scenario', 'uncovered_missing'] %}
select
    p_model as model,
    p_problem as problem,
    p_scenario_id as budget_scenario_id,
    p_data_area_id as data_area_id,
    p_fiscal_year as fiscal_year,
    p_period as period,
    p_main_account as main_account,
    toUInt64(p_variance_rows) as variance_rows,
    p_expected_actual as expected_actual,
    p_variance_actual as variance_actual
from {{ cte }}_{{ model_index }}
{% if not (loop.last and last_model) %}union all{% endif %}
{% endfor %}
{% endfor %}
