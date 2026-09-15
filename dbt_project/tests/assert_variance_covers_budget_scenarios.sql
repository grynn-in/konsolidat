{# konsolidat#206: every active budget-type scenario (its scenario_type declared in
   epm_gold.scenario_definitions) that has rows in gold_scenario_trial_balance has
   variance rows of its own (budget_scenario_id) in each variance model. A model
   that does not yet carry budget_scenario_id covers no scenario, so the test
   fails on it rather than erroring. One row per (model, uncovered scenario). #}

{% set variance_models = ['gold_variance_analysis', 'gold_variance_quarterly', 'gold_variance_ytd'] %}
{# the refs below sit behind `execute`, so declare them for the DAG #}
{% for m in variance_models %}
-- depends_on: {{ ref(m) }}
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

covered as (
    {% for m in variance_models %}
    {% set cols = [] %}
    {% if execute %}
        {% set cols = adapter.get_columns_in_relation(ref(m)) | map(attribute='name') | list %}
    {% endif %}
    {% if 'budget_scenario_id' in cols %}
    select '{{ m }}' as model_name, budget_scenario_id as scenario_id
    from {{ ref(m) }}
    group by budget_scenario_id
    {% else %}
    select '{{ m }}' as model_name, '' as scenario_id
    where 0
    {% endif %}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select
    m.model_name as model_name,
    b.scenario_id as scenario_id,
    b.scenario_rows as scenario_rows
from budget_scenarios as b
cross join (
    select arrayJoin([{% for m in variance_models %}'{{ m }}'{{ ', ' if not loop.last }}{% endfor %}]) as model_name
) as m
where (m.model_name, b.scenario_id) not in (
    select model_name, scenario_id from covered
)
