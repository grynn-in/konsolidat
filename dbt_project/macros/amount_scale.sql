{# The scale of a trial-balance amount (#256, option #256-1; Deepak Pai,
   11 Oct 2026): Decimal(38, 4), so every ISO 4217 currency (minor unit 0 to
   4: JPY 0, EUR 2, BHD/KWD/OMR/TND 3, CLF 4) keeps its amounts exactly from
   bronze to gold. Rejected: a scale per currency (#256-3). One definition: a
   cast, a typed zero or a column type on the TB path writes
   {{ amount_scale() }} (or {{ amount_type() }}), never a literal scale.

   Out of scope here: rates, percentages and the ERP staging tree (#221),
   which keeps its own scale; ClickHouse promotes a mix of the two scales to
   the wider one (UNION ALL, if, greatest, lagInFrame), so nothing narrows. #}
{% macro amount_scale() %}4{% endmacro %}

{% macro amount_type() %}Decimal(38, {{ amount_scale() }}){% endmacro %}

{# Pre-hook for an incremental model that holds TB amounts (#256). An append
   inserts into the target's EXISTING column types, and ClickHouse narrows a
   Decimal(38, 4) into a Decimal(38, 2) column by dropping the extra digits,
   without an error. So a table built before #256 must have its amount
   columns widened before the append, or it keeps truncating on every run.

   It reads the target's column types and widens only the named columns that
   are a Decimal with a scale below amount_scale(), keeping Nullable. So it is
   idempotent (a second run finds nothing to widen and renders nothing), it
   leaves a configured non-amount measure alone, and on a fresh build (not
   is_incremental) it renders nothing. #}
{% macro widen_amount_columns(columns) %}
{%- if execute and is_incremental() -%}
    {%- set rows = run_query(
        "select name, type from system.columns where database = '" ~ this.schema
        ~ "' and table = '" ~ this.identifier ~ "'") -%}
    {%- set pattern = modules.re.compile('^(Nullable\\()?Decimal\\((\\d+), (\\d+)\\)\\)?$') -%}
    {%- set widen = [] -%}
    {%- for r in rows -%}
        {%- set m = pattern.match(r[1]) -%}
        {%- if r[0] in columns and m and (m.group(3) | int) < (amount_scale() | int) -%}
            {%- do widen.append('MODIFY COLUMN ' ~ r[0] ~ ' ' ~ (('Nullable(' ~ amount_type() ~ ')') if m.group(1) else amount_type())) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- if widen -%}
ALTER TABLE {{ this }} {{ widen | join(', ') }}
    {%- endif -%}
{%- endif -%}
{% endmacro %}
