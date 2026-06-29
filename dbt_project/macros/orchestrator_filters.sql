{#
  Run-scope filters for orchestrator closes (konsol-exec Execute plane).

  Both macros are OPT-IN: with no var set they emit an empty string, so a normal
  full build is byte-for-byte unchanged. The orchestrator (konsol plan.py) passes
  fiscal_year / fiscal_period / entity_scope as dbt --vars; here they become real
  SQL predicates appended inside a `where 1 = 1 ...` block.

  - period_filter: single-period closes — narrows to one fiscal_year and/or
    fiscal_period (both numeric in the gold grain).
  - scope_filter: consolidate one entity or one group. Resolves the scope code
    against gold_consolidation_hierarchy so a GROUP code expands to every
    descendant entity (via the materialised `path`, e.g. GROUP_CORP/GROUP_EMEA/
    DEMF), while an entity data_area_id matches just itself.
#}

{% macro period_filter(year_col='fiscal_year', period_col='fiscal_period') %}
    {%- set fy = var('fiscal_year', '') -%}
    {%- set fp = var('fiscal_period', '') -%}
    {%- if fy is not none and (fy | string | trim) != '' %} and {{ year_col }} = {{ (fy | string | trim) | int }}{% endif -%}
    {%- if fp is not none and (fp | string | trim) != '' %} and {{ period_col }} = {{ (fp | string | trim) | int }}{% endif -%}
{% endmacro %}


{% macro scope_filter(data_area_col='data_area_id') %}
    {%- set scope = var('entity_scope', '') -%}
    {%- if scope is not none and (scope | string | trim) != '' -%}
        {#- Escape single quotes so the scope value can't break out of the SQL
            literal (entity_scope is orchestrator-set today; defence-in-depth). -#}
        {%- set s = (scope | string | trim) | replace("'", "''") %} and {{ data_area_col }} in (
        select data_area_id
        from {{ ref('gold_consolidation_hierarchy') }}
        where data_area_id = '{{ s }}'
           or consolidation_group = '{{ s }}'
           or path = '{{ s }}'
           or path like '{{ s }}/%'
           or path like '%/{{ s }}/%'
           or path like '%/{{ s }}'
    ){% endif -%}
{% endmacro %}
