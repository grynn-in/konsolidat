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

{# Returns the name of the dimension a site declares as its cost-centre dimension,
   or '' when none does.

   konsolidat#220: this used to fall back to the literal 'dim_cost_center', which
   asserted one site's configuration as a fact. On a site that declares no
   dimensions — the starting state of every new site (konsol#230) — or one whose
   cost-centre dimension is spelled differently and carries no allocation_role,
   that literal rendered into the allocation engine and the build died far from
   its cause with `Code: 47 … Unknown expression identifier 'dim_cost_center'`.

   CALLERS MUST HANDLE ''. `allocation_engine_multistep` renders a row-less result
   in that case; `tests/assert_cascade_increases_pool` asserts nothing. The three
   unreferenced engines (allocation_engine, _reciprocal, _tiered) have no callers
   anywhere in models, tests or macros, so they never render — if one is ever
   wired up, it needs the same guard. Decision recorded on konsolidat#220 (PR #222). #}
{% macro get_allocation_cost_center_dim() %}
    {% for d in var('dimensions') %}
        {% if d.get('allocation_role', '') == 'cost_center' %}
            {{ return(d.name) }}
        {% endif %}
    {% endfor %}
    {{ return('') }}
{% endmacro %}

{# konsolidat#220 — the `trailing` parameter.
   These macros emit their own INTERNAL separators, so a list renders as
   `a, b, c` with no trailing comma. A call site that is followed by more
   columns therefore used to write its own literal comma — which dangles into
   malformed SQL when the site declares NO dimensions (the starting state of
   every new site since konsol#230). Pass `trailing=true` at those call sites
   and drop the literal comma: the comma is then emitted only when the
   rendered list is non-empty. It defaults to false so a call site that is
   LAST in its list (and correctly has no comma) is unaffected by this
   parameter existing.

   konsolidat#220 — the `leading` parameter, for the OTHER shape of the same
   defect. A call site that is LAST in its list carries no comma of its own, but
   the column before it does — `partition by data_area_id, main_account,` then
   the macro, then `order by`. With NO dimensions that preceding comma is left
   ending the clause, and `trailing` cannot help: the comma belongs to the
   previous column. Pass `leading=true` at those sites and drop the literal
   comma from the line above; the comma is then emitted immediately BEFORE the
   rendered list, and only when that list is non-empty. Like `trailing` it
   defaults to false, so no existing call site changes behaviour. #}

{# SELECT list of dimension columns with optional table prefix #}
{% macro dim_select(prefix='', dims=none, trailing=false, leading=false) %}
    {%- set dimensions = dims if dims is not none else var('dimensions') %}
    {{- ',' if leading and dimensions | length > 0 }}
    {% for d in dimensions %}
    {{ prefix }}{{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
    {{- ',' if trailing and dimensions | length > 0 }}
{% endmacro %}

{# GROUP BY list of dimension columns with optional table prefix #}
{% macro dim_group_by(prefix='', dims=none, trailing=false, leading=false) %}
    {%- set dimensions = dims if dims is not none else var('dimensions') %}
    {{- ',' if leading and dimensions | length > 0 }}
    {% for d in dimensions %}
    {{ prefix }}{{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
    {{- ',' if trailing and dimensions | length > 0 }}
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
{% macro dim_partition_by(prefix='', dims=none, trailing=false, leading=false) %}
    {%- set dimensions = dims if dims is not none else var('dimensions') %}
    {{- ',' if leading and dimensions | length > 0 }}
    {% for d in dimensions %}
    {{ prefix }}{{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
    {{- ',' if trailing and dimensions | length > 0 }}
{% endmacro %}

{# Empty string literals for non-entity layers (IC eliminations, CTA, etc.) #}
{% macro dim_empty_strings(dims=none, trailing=false, leading=false) %}
    {%- set dimensions = dims if dims is not none else var('dimensions') %}
    {{- ',' if leading and dimensions | length > 0 }}
    {% for d in dimensions %}
    '' as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
    {{- ',' if trailing and dimensions | length > 0 }}
{% endmacro %}

{# ============================================================
   Dimension Harmonization (Phase 3)
   Crosswalk raw, ERP-local dimension values to canonical values
   via the `dimension_mappings` seed, keyed by
   (dimension, erp_source, source_value). Unmapped values pass
   through unchanged (coalesce fallback) so onboarding a new value
   is non-blocking.

   Applied centrally in canonical staging models: wrap the per-ERP UNION in a
   CTE, then harmonize keyed on the per-row erp_source column so every adapter
   is covered without restating columns:

       with unioned as ( ...union all of stg_<erp>__gl_entries... )
       select
           erp_source, record_id, ..., ledger_account,
           {{ dim_harmonize_select(raw_alias='unioned') }}
           _loaded_at, _raw_id
       from unioned
       {{ dim_harmonize_joins('unioned.erp_source', raw_alias='unioned') }}

   Pass dims=get_budget_dimensions() for budget (no dim_business_unit).
   ============================================================ #}

{# Harmonized SELECT expressions: mapped canonical_value, else raw value passes
   through. Uses an empty-string check rather than coalesce because ClickHouse
   LEFT JOIN fills unmatched rows with the column default ('' for String), not
   NULL — so coalesce() would wrongly blank out unmapped values.
   Trailing comma slots this before the trailing _loaded_at/_raw_id. #}
{% macro dim_harmonize_select(raw_alias='unioned', map_prefix='dmap_', dims=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% for d in dimensions %}
    {# precedence: entity-specific mapping beats the ERP-wide default (entity='')
       beats passthrough. Cost centre 100 can be Sales in USMF and Manufacturing
       in DEMF — konsol #111. #}
    multiIf({{ map_prefix }}{{ d.name }}.canonical_value != '', {{ map_prefix }}{{ d.name }}.canonical_value,
            {{ map_prefix }}{{ d.name }}_dflt.canonical_value != '', {{ map_prefix }}{{ d.name }}_dflt.canonical_value,
            {{ raw_alias }}.{{ d.name }}) as {{ d.name }},
    {%- endfor %}
{% endmacro %}

{# LEFT JOINs against the dimension_mappings seed, one per dimension.
   erp_source_col is a SQL expression — the per-row erp_source column
   (e.g. 'unioned.erp_source') so each source's values map correctly. #}
{% macro dim_harmonize_joins(erp_source_col, raw_alias='unioned', map_prefix='dmap_', dims=none, entity_col=none) %}
    {% set dimensions = dims if dims is not none else var('dimensions') %}
    {% set entity_expr = entity_col if entity_col is not none else raw_alias ~ '.entity_id' %}
    {% for d in dimensions %}
    {# TWO joins, not one OR-predicate: a value with BOTH an entity-specific row
       and a blank (ERP-wide) row would match twice through an OR and fan the
       fact rows out. The select's multiIf gives specific-beats-default. #}
    left join {{ source('epm_staging', 'dimension_mappings') }} as {{ map_prefix }}{{ d.name }}
        on {{ map_prefix }}{{ d.name }}.status = 'Published'
        and {{ map_prefix }}{{ d.name }}.dimension = '{{ d.name }}'
        and {{ map_prefix }}{{ d.name }}.erp_source = {{ erp_source_col }}
        and {{ map_prefix }}{{ d.name }}.entity = {{ entity_expr }}
        and {{ map_prefix }}{{ d.name }}.source_value = {{ raw_alias }}.{{ d.name }}
    left join {{ source('epm_staging', 'dimension_mappings') }} as {{ map_prefix }}{{ d.name }}_dflt
        on {{ map_prefix }}{{ d.name }}_dflt.status = 'Published'
        and {{ map_prefix }}{{ d.name }}_dflt.dimension = '{{ d.name }}'
        and {{ map_prefix }}{{ d.name }}_dflt.erp_source = {{ erp_source_col }}
        and {{ map_prefix }}{{ d.name }}_dflt.entity = ''
        and {{ map_prefix }}{{ d.name }}_dflt.source_value = {{ raw_alias }}.{{ d.name }}
    {%- endfor %}
{% endmacro %}

{# Bronze source mapping: casts source columns to dimension names #}
{% macro dim_select_from_source(prefix='', dims=none, trailing=false, leading=false) %}
    {%- set dimensions = dims if dims is not none else var('dimensions') %}
    {{- ',' if leading and dimensions | length > 0 }}
    {% for d in dimensions %}
    {{ cast_to_string("coalesce(" ~ prefix ~ d.source_column ~ ", '')") }} as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}
    {{- ',' if trailing and dimensions | length > 0 }}
{% endmacro %}
