{#
  Run-scope filters for orchestrator closes (konsol-exec Execute plane).

  Both macros are OPT-IN: with no var set they emit an empty string, so a normal
  full build is byte-for-byte unchanged. The orchestrator (konsol plan.py) passes
  fiscal_year / fiscal_period / entity_scope as dbt --vars; here they become real
  SQL predicates appended inside a `where 1 = 1 ...` block.

  - period_filter: single-period closes — narrows to one fiscal_year and/or
    fiscal_period (both numeric in the gold grain). Pass include_period=false on
    cumulative models (e.g. YTD) that need every prior period within the year:
    the fiscal_year predicate is still applied (safe, year-bounded), but the
    single-period predicate is suppressed.
  - scope_filter: consolidate one entity or one group. Resolves the scope code
    against gold_consolidation_hierarchy so a GROUP code expands to every
    descendant entity (via the materialised `path`, e.g. GROUP_CORP/GROUP_EMEA/
    DEMF), while an entity data_area_id matches just itself.
#}


{#- Validate that an orchestrator var is a non-negative integer. Fiscal year and
    period are always non-negative integers in the gold grain, so a non-numeric
    value is a misconfigured run and must fail LOUDLY rather than be silently
    coerced to 0 by `| int` (which yields an empty, wrong result set). -#}
{% macro _require_period_int(val, name) %}
    {%- set sval = val | string | trim -%}
    {%- if not sval.isdigit() -%}
        {{ exceptions.raise_compiler_error("orchestrator_filters: var '" ~ name ~ "' must be a non-negative integer, got '" ~ sval ~ "'") }}
    {%- endif -%}
    {{- return(sval | int) -}}
{% endmacro %}


{% macro period_filter(year_col='fiscal_year', period_col='fiscal_period', include_period=true) %}
    {%- set fy = var('fiscal_year', '') -%}
    {%- set fp = var('fiscal_period', '') -%}
    {%- if fy is not none and (fy | string | trim) != '' %} and {{ year_col }} = {{ _require_period_int(fy, 'fiscal_year') }}{% endif -%}
    {%- if include_period and fp is not none and (fp | string | trim) != '' %} and {{ period_col }} = {{ _require_period_int(fp, 'fiscal_period') }}{% endif -%}
{% endmacro %}


{% macro scope_filter(data_area_col='data_area_id') %}
    {%- set scope = var('entity_scope', '') -%}
    {%- if scope is not none and (scope | string | trim) != '' -%}
        {#- Escape single quotes so the scope value can't break out of the SQL
            literal (entity_scope is orchestrator-set today; defence-in-depth). -#}
        {%- set s = (scope | string | trim) | replace("'", "''") -%}
        {#- LIKE-escaped variant: `_` and `%` are LIKE metacharacters and entity /
            group codes contain `_` (e.g. GROUP_CORP), so an un-escaped `_` would
            match ANY character and over-select. ClickHouse LIKE has NO `ESCAPE`
            clause (it's a syntax error) — backslash is the BUILT-IN escape char.
            Escape the backslash first, then the metacharacters. Each escape is
            DOUBLED in the literal so ClickHouse's string parser yields a single
            backslash for LIKE (e.g. '\\_' in SQL -> '\_' to LIKE -> literal '_').
            Equality comparisons below use the un-escaped `s` (no LIKE involved). -#}
        {%- set like_s = s | replace('\\', '\\\\\\\\') | replace('%', '\\\\%') | replace('_', '\\\\_') %} and {{ data_area_col }} in (
        select data_area_id
        from {{ ref('gold_consolidation_hierarchy') }}
        where data_area_id = '{{ s }}'
           or consolidation_group = '{{ s }}'
           or path = '{{ s }}'
           {#- A group code matches descendants at ANY depth: the slash-bounded
               patterns cover the code as the first / a middle / the last segment
               of the full materialised path, so grandchildren are included. The
               slash boundaries prevent prefix collisions (GROUP_COR vs GROUP_CORP).
               The seed-fallback path is intrinsically 2-segment (group/entity) and
               flat, so it has no grandchildren to miss. -#}
           or path like '{{ like_s }}/%'
           or path like '%/{{ like_s }}/%'
           or path like '%/{{ like_s }}'
    ){% endif -%}
{% endmacro %}
