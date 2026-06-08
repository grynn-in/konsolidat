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

{% macro cast_to_decimal128(expr, scale) %}
    toDecimal128(assumeNotNull({{ expr }}), {{ scale }})
{% endmacro %}

{% macro extract_year(expr) %}
    toYear({{ expr }})
{% endmacro %}

{% macro extract_month(expr) %}
    toMonth({{ expr }})
{% endmacro %}

{% macro build_date_from_year_period(year_expr, period_expr) %}
    toDate(concat(toString(greatest({{ year_expr }}, 1900)), '-', lpad(toString(greatest({{ period_expr }}, 1)), 2, '0'), '-01'))
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
