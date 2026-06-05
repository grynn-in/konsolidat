{# ============================================================
   Measure Helper Macros
   Drive measure aggregations from vars.base_measures config
   in dbt_project.yml.
   ============================================================ #}

{# Generates aggregate expressions for gold_trial_balance SELECT #}
{% macro measure_select() %}
    {% for m in var('base_measures') %}
    {{ m.expression }} as {{ m.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}

{# Column references for downstream models that passthrough measures #}
{% macro measure_passthrough(prefix='') %}
    {% for m in var('base_measures') %}
    {{ prefix }}{{ m.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}
