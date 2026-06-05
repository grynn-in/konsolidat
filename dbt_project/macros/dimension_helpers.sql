{# ============================================================
   Dimension Helper Macros
   Drive dimension columns from vars.dimensions config in
   dbt_project.yml. All dimension references in models should
   use these macros instead of hardcoded column names.
   ============================================================ #}

{% macro get_dimensions() %}
    {{ return(var('dimensions')) }}
{% endmacro %}

{% macro get_budget_dimensions() %}
    {% set result = [] %}
    {% for d in var('dimensions') %}
        {% if d.in_budget %}
            {% do result.append(d) %}
        {% endif %}
    {% endfor %}
    {{ return(result) }}
{% endmacro %}

{% macro get_allocation_cost_center_dim() %}
    {% for d in var('dimensions') %}
        {% if d.get('allocation_role', '') == 'cost_center' %}
            {{ return(d.name) }}
        {% endif %}
    {% endfor %}
    {{ return('dim_cost_center') }}
{% endmacro %}

{# SELECT list of dimension columns with optional table prefix #}
{% macro dim_select(prefix='', dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    {{ prefix }}{{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}

{# GROUP BY list of dimension columns with optional table prefix #}
{% macro dim_group_by(prefix='', dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    {{ prefix }}{{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}

{# JOIN conditions for matching dimensions between two aliases #}
{% macro dim_join_on(left, right, dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    and {{ left }}.{{ d.name }} = {{ right }}.{{ d.name }}
    {%- endfor %}
{% endmacro %}

{# COALESCE for FULL OUTER JOIN selects #}
{% macro dim_coalesce(left, right, dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    coalesce({{ left }}.{{ d.name }}, {{ right }}.{{ d.name }}) as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}

{# PARTITION BY clause for window functions #}
{% macro dim_partition_by(prefix='', dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    {{ prefix }}{{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}

{# Empty string literals for non-entity layers (IC eliminations, CTA, etc.) #}
{% macro dim_empty_strings(dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    '' as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}

{# Bronze source mapping: casts source columns to dimension names #}
{% macro dim_select_from_source(prefix='', dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    {{ cast_to_string("coalesce(" ~ prefix ~ d.source_column ~ ", '')") }} as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
{% endmacro %}
