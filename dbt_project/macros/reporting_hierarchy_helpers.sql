{# ============================================================
   Reporting Hierarchy Helpers
   Roll up gold_trial_balance to management hierarchy nodes.
   ============================================================ #}

{# Unpivot published dimensions on trial balance for hierarchy joins. #}
{% macro tb_dimension_long_sql(tb_alias='tb') %}
    {% if var('dimensions') | length == 0 %}
    {# konsolidat#220: one branch per declared dimension means zero dimensions emits
       nothing at all, and the CTE that wraps this is then empty — not a SELECT query,
       which ClickHouse rejects outright (Code: 62) and takes every dependent with it.
       A site that declares no dimensions cannot have a dimension hierarchy, so no rows
       is the true answer here, not a degraded one: render the real select against a
       false predicate. `<alias>.*` derives the column contract from the source rather
       than restating it, which empty_relation() would require. The ref() must stay
       inside this branch so the model keeps its dependency edge at zero dimensions. #}
    select
        {{ tb_alias }}.*,
        '' as hierarchy_dimension,
        '' as dimension_member_code
    from {{ ref('gold_trial_balance') }} as {{ tb_alias }}
    where 0
    {% else %}
    {% for d in var('dimensions') %}
    select
        {{ tb_alias }}.*,
        '{{ d.name }}' as hierarchy_dimension,
        {{ tb_alias }}.{{ d.name }} as dimension_member_code
    from {{ ref('gold_trial_balance') }} as {{ tb_alias }}
    where {{ tb_alias }}.{{ d.name }} != ''
    {% if not loop.last %}
    union all
    {% endif %}
    {% endfor %}
    {% endif %}
{% endmacro %}

{# Unpivot budget dimensions on spread budget for hierarchy joins. #}
{% macro budget_dimension_long_sql(budget_alias='b') %}
    {% if get_budget_dimensions() | length == 0 %}
    {# Empty budget dimension list, same shape and same reason as tb_dimension_long_sql. #}
    select
        {{ budget_alias }}.*,
        '' as hierarchy_dimension,
        '' as dimension_member_code
    from {{ ref('gold_spread_budget') }} as {{ budget_alias }}
    where 0
    {% else %}
    {% for d in get_budget_dimensions() %}
    select
        {{ budget_alias }}.*,
        '{{ d.name }}' as hierarchy_dimension,
        {{ budget_alias }}.{{ d.name }} as dimension_member_code
    from {{ ref('gold_spread_budget') }} as {{ budget_alias }}
    where {{ budget_alias }}.{{ d.name }} != ''
    {% if not loop.last %}
    union all
    {% endif %}
    {% endfor %}
    {% endif %}
{% endmacro %}

{# Unpivot budget dimensions on variance for hierarchy joins. #}
{% macro variance_dimension_long_sql(var_alias='v') %}
    {% if get_budget_dimensions() | length == 0 %}
    {# Empty budget dimension list, same shape and same reason as tb_dimension_long_sql. #}
    select
        {{ var_alias }}.*,
        '' as hierarchy_dimension,
        '' as dimension_member_code
    from {{ ref('gold_variance_analysis') }} as {{ var_alias }}
    where 0
    {% else %}
    {% for d in get_budget_dimensions() %}
    select
        {{ var_alias }}.*,
        '{{ d.name }}' as hierarchy_dimension,
        {{ var_alias }}.{{ d.name }} as dimension_member_code
    from {{ ref('gold_variance_analysis') }} as {{ var_alias }}
    where {{ var_alias }}.{{ d.name }} != ''
    {% if not loop.last %}
    union all
    {% endif %}
    {% endfor %}
    {% endif %}
{% endmacro %}

{% macro hierarchy_measure_sums(prefix='') %}
    {% for m in var('base_measures') %}
    sum({{ prefix }}{{ m.name }}) as {{ m.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}

{% macro variance_measure_sums(prefix='') %}
    sum({{ prefix }}actual_amount) as actual_amount,
    sum({{ prefix }}budget_amount) as budget_amount,
    sum({{ prefix }}variance_abs) as variance_abs
{% endmacro %}