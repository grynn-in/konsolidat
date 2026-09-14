{# ============================================================
   Database Adapter Macros
   Abstract ClickHouse-specific SQL into overridable macros.
   To support a new database, override these in a package or
   project-level macro with the same name.
   ============================================================ #}

{% macro cast_to_string(expr) %}
    toString(assumeNotNull({{ expr }}))
{% endmacro %}

{% macro cast_to_int64(expr) %}
    toInt64(assumeNotNull({{ expr }}))
{% endmacro %}

{% macro cast_to_int8(expr) %}
    toInt8(assumeNotNull({{ expr }}))
{% endmacro %}

{% macro cast_to_uint16(expr) %}
    toUInt16(assumeNotNull({{ expr }}))
{% endmacro %}

{% macro cast_to_uint8(expr) %}
    toUInt8(assumeNotNull({{ expr }}))
{% endmacro %}

{% macro cast_to_float64(expr) %}
    toFloat64(assumeNotNull({{ expr }}))
{% endmacro %}

{% macro cast_to_date(expr) %}
    toDate(assumeNotNull({{ expr }}))
{% endmacro %}

{% macro cast_to_datetime(expr) %}
    toDateTime(assumeNotNull({{ expr }}))
{% endmacro %}

{# toDecimal128(Float64, scale) truncates the binary double toward zero, so a
   value like 0.29 (not exactly representable in binary) becomes 0.28
   (konsolidat#191). Going through toString first uses ClickHouse's
   shortest-round-trip decimal text for the float, which parses back to the
   exact value that was submitted; a Decimal or Nullable input passes
   through toString unchanged either way. #}
{% macro cast_to_decimal128(expr, scale) %}
    toDecimal128(toString(assumeNotNull({{ expr }})), {{ scale }})
{% endmacro %}

{% macro extract_year(expr) %}
    toYear({{ expr }})
{% endmacro %}

{% macro extract_month(expr) %}
    toMonth({{ expr }})
{% endmacro %}

{# The 1st of month P. P is clamped to 1..12: OPN (0) is January and CLS (13)
   December. Unclamped, toDate('2024-13-01') is 1970-01-01 on ClickHouse 24.8
   rather than an error, so a CLS row dated 1970 and missed its as-of joins
   (konsolidat#177). #}
{% macro build_date_from_year_period(year_expr, period_expr) %}
    toDate(concat(toString(greatest({{ year_expr }}, 1900)), '-', lpad(toString(least(greatest({{ period_expr }}, 1), 12)), 2, '0'), '-01'))
{% endmacro %}

{% macro latest_value_by(val_expr, key_expr) %}
    argMax({{ val_expr }}, {{ key_expr }})
{% endmacro %}

{% macro string_pad_left(expr, len, ch) %}
    lpad({{ expr }}, {{ len }}, {{ ch }})
{% endmacro %}

{# Returns engine config for ClickHouse targets, empty dict otherwise #}
{% macro epm_config(order_by='tuple()') %}
    {% if target.type == 'clickhouse' %}
        {{ return({'engine': "MergeTree()", 'order_by': order_by}) }}
    {% else %}
        {{ return({}) }}
    {% endif %}
{% endmacro %}
