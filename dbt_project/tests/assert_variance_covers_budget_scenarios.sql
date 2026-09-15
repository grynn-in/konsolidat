{# konsolidat#206: every active budget-type scenario (its scenario_type declared in
   epm_gold.scenario_definitions) that has rows in gold_scenario_trial_balance has
   variance rows of its own (budget_scenario_id) in each variance model. A model
   that does not yet carry budget_scenario_id covers no scenario, so the test
   fails on it rather than erroring.

   PR #211 review 4: and each budget scenario carries every actual grain of the
   (data_area_id, fiscal_year)s it budgets exactly once, with the actual amount
   of that grain (the running total to date in gold_variance_ytd): a model that
   repeats or sums the actuals across budget scenarios, or drops them, fails.
   The grain is the model's own: entity, fiscal year, period (fiscal_quarter in
   gold_variance_quarterly, through gold_period_hierarchy as the model maps it),
   main account and the budget dimensions.

   One row per problem:
     uncovered_scenario - a (model, budget scenario) with no variance rows;
     actual_not_once    - a (model, budget scenario, actual grain) with no row
                          or more than one;
     actual_amount      - the grain's row carries another actual amount. #}

{% set budget_dims = get_budget_dimensions() %}
{% set variance_models = [
    ('gold_variance_analysis', 'fiscal_period', 'actual_amount', false),
    ('gold_variance_quarterly', 'fiscal_quarter', 'actual_amount', false),
    ('gold_variance_ytd', 'fiscal_period', 'ytd_actual', true),
] %}
{# the refs below sit behind `execute`, so declare them for the DAG #}
{% for m, pc, ac, running in variance_models %}
-- depends_on: {{ ref(m) }}
{% endfor %}

{% set model_cols = {} %}
{% for m, pc, ac, running in variance_models %}
{% if execute %}
    {% do model_cols.update({m: adapter.get_columns_in_relation(ref(m)) | map(attribute='name') | list}) %}
{% endif %}
{% endfor %}

with budget_scenarios as (
    select
        t.scenario_id as scenario_id,
        count() as scenario_rows
    from {{ ref('gold_scenario_trial_balance') }} as t
    inner join (
        select distinct scenario_id
        from {{ source('epm_gold', 'scenario_definitions') }}
        where scenario_type = 'budget'
          and is_active = 1
    ) as s
        on t.scenario_id = s.scenario_id
    group by t.scenario_id
),

{# the (entity, fiscal year)s each budget scenario budgets #}
budget_years as (
    select distinct
        t.scenario_id as y_scenario_id,
        t.data_area_id as y_data_area_id,
        t.fiscal_year as y_fiscal_year
    from {{ ref('gold_scenario_trial_balance') }} as t
    inner join budget_scenarios as b
        on t.scenario_id = b.scenario_id
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

covered as (
    {% for m, pc, ac, running in variance_models %}
    {% if 'budget_scenario_id' in model_cols.get(m, []) %}
    select '{{ m }}' as model_name, budget_scenario_id as scenario_id
    from {{ ref(m) }}
    group by budget_scenario_id
    {% else %}
    select '{{ m }}' as model_name, '' as scenario_id
    where 0
    {% endif %}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

{% for m, pc, ac, running in variance_models %}
{# the actual grains in the model's grain, with their amount #}
actual_grain_{{ loop.index }} as (
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
            l_{{ pc }} as g_period,
            l_main_account as g_main_account,
            {% for d in budget_dims %}
            l_{{ d.name }} as g_{{ d.name }},
            {% endfor %}
            sum(l_amount) as g_amount
        from actual_lines
        group by g_data_area_id, g_fiscal_year, g_period, g_main_account
            {% for d in budget_dims %}, g_{{ d.name }}{% endfor %}
    )
),

{# each budget scenario must carry every actual grain of the years it budgets #}
expected_{{ loop.index }} as (
    select
        y.y_scenario_id as e_scenario_id,
        g.g_data_area_id as e_data_area_id,
        g.g_fiscal_year as e_fiscal_year,
        g.g_period as e_period,
        g.g_main_account as e_main_account,
        {% for d in budget_dims %}
        g.g_{{ d.name }} as e_{{ d.name }},
        {% endfor %}
        g.g_expected as e_actual
    from actual_grain_{{ loop.index }} as g
    inner join budget_years as y
        on g.g_data_area_id = y.y_data_area_id
       and g.g_fiscal_year = y.y_fiscal_year
),

model_rows_{{ loop.index }} as (
    {% if 'budget_scenario_id' in model_cols.get(m, []) %}
    select
        v.budget_scenario_id as r_scenario_id,
        v.data_area_id as r_data_area_id,
        v.fiscal_year as r_fiscal_year,
        v.{{ pc }} as r_period,
        v.main_account as r_main_account,
        {% for d in budget_dims %}
        v.{{ d.name }} as r_{{ d.name }},
        {% endfor %}
        count() as r_rows,
        sum(v.{{ ac }}) as r_actual
    from {{ ref(m) }} as v
    where v.budget_scenario_id != ''
    group by r_scenario_id, r_data_area_id, r_fiscal_year, r_period, r_main_account
        {% for d in budget_dims %}, r_{{ d.name }}{% endfor %}
    {% else %}
    {# no budget_scenario_id: uncovered_scenario already names the model #}
    select
        '' as r_scenario_id, '' as r_data_area_id, 0 as r_fiscal_year,
        {{ 'toUInt8(0)' if pc == 'fiscal_period' else "''" }} as r_period, '' as r_main_account,
        {% for d in budget_dims %}
        '' as r_{{ d.name }},
        {% endfor %}
        toUInt64(0) as r_rows, 0 as r_actual
    where 0
    {% endif %}
),

{# the model's rows for each expected grain: missing is 0 rows (join_use_nulls=0) #}
checked_{{ loop.index }} as (
    select
        '{{ m }}' as model_name,
        e.e_scenario_id as scenario_id,
        e.e_data_area_id as data_area_id,
        toString(e.e_fiscal_year) as fiscal_year,
        toString(e.e_period) as period,
        e.e_main_account as main_account,
        toFloat64(e.e_actual) as expected_actual,
        toUInt64(r.r_rows) as variance_rows,
        toFloat64(r.r_actual) as variance_actual
    from expected_{{ loop.index }} as e
    left join model_rows_{{ loop.index }} as r
        on e.e_scenario_id = r.r_scenario_id
       and e.e_data_area_id = r.r_data_area_id
       and e.e_fiscal_year = r.r_fiscal_year
       and e.e_period = r.r_period
       and e.e_main_account = r.r_main_account
       {% for d in budget_dims %}
       and e.e_{{ d.name }} = r.r_{{ d.name }}
       {% endfor %}
){{ ',' if not loop.last }}
{% endfor %}

select
    m.model_name as model_name,
    'uncovered_scenario' as problem,
    b.scenario_id as scenario_id,
    '' as data_area_id,
    '' as fiscal_year,
    '' as period,
    '' as main_account,
    toFloat64(0) as expected_actual,
    toUInt64(b.scenario_rows) as variance_rows,
    toFloat64(0) as variance_actual
from budget_scenarios as b
cross join (
    select arrayJoin([{% for m, pc, ac, running in variance_models %}'{{ m }}'{{ ', ' if not loop.last }}{% endfor %}]) as model_name
) as m
where (m.model_name, b.scenario_id) not in (
    select model_name, scenario_id from covered
)

{% for m, pc, ac, running in variance_models %}
union all

select
    model_name,
    if(variance_rows != 1, 'actual_not_once', 'actual_amount') as problem,
    scenario_id,
    data_area_id,
    fiscal_year,
    period,
    main_account,
    expected_actual,
    variance_rows,
    variance_actual
from checked_{{ loop.index }}
where variance_rows != 1
   or abs(expected_actual - variance_actual) > {{ materiality_floor() }}
{% endfor %}
