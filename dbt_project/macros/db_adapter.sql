{# ============================================================
   Database Adapter Macros
   Abstract ClickHouse-specific SQL into overridable macros.
   To support a new database, override these in a package or
   project-level macro with the same name.
   ============================================================ #}

{% macro cast_to_string(expr) %}
    toString({{ expr }})
{% endmacro %}

{% macro cast_to_int64(expr) %}
    toInt64({{ expr }})
{% endmacro %}

{% macro cast_to_int8(expr) %}
    toInt8({{ expr }})
{% endmacro %}

{% macro cast_to_uint16(expr) %}
    toUInt16({{ expr }})
{% endmacro %}

{% macro cast_to_uint8(expr) %}
    toUInt8({{ expr }})
{% endmacro %}

{% macro cast_to_float64(expr) %}
    toFloat64({{ expr }})
{% endmacro %}

{% macro cast_to_date(expr) %}
    toDate({{ expr }})
{% endmacro %}

{% macro cast_to_datetime(expr) %}
    toDateTime({{ expr }})
{% endmacro %}

{% macro cast_to_decimal128(expr, scale) %}
    toDecimal128({{ expr }}, {{ scale }})
{% endmacro %}

{% macro extract_year(expr) %}
    toYear({{ expr }})
{% endmacro %}

{% macro extract_month(expr) %}
    toMonth({{ expr }})
{% endmacro %}

{% macro build_date_from_year_period(year_expr, period_expr) %}
    toDate(concat(toString({{ year_expr }}), '-', lpad(toString({{ period_expr }}), 2, '0'), '-01'))
{% endmacro %}

{% macro latest_value_by(val_expr, key_expr) %}
    argMax({{ val_expr }}, {{ key_expr }})
{% endmacro %}

{% macro string_pad_left(expr, len, ch) %}
    lpad({{ expr }}, {{ len }}, {{ ch }})
{% endmacro %}
