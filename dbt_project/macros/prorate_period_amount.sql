{# PRD-11: Prorate an amount to post-acquisition days only.
   Returns fraction = days_post_acquisition / days_in_period.
   If no acquisition in the period, returns 1.0.
   If acquisition_date is after period end, returns 0.0.
   acquisition_date: Date, fiscal_year: UInt16, fiscal_period: UInt8
   The period ends where the next month begins: addMonths(period start, 1).
   It was the start of period p + 1 capped at 13, and 13 is no month: the
   date was 1970-01-01 (and December once the period was clamped, #177), so
   a mid-December acquisition prorated P12 to 0 (#176 review). #}

{% macro prorate_period_amount(amount_expr, acquisition_date_expr, year_expr, period_expr) %}
    {{ amount_expr }} * (
        case
            {# No acquisition constraint — full amount #}
            when {{ acquisition_date_expr }} <= toDate('1900-01-01') then 1.0
            {# Acquisition is before this period — full amount #}
            when {{ acquisition_date_expr }} < {{ build_date_from_year_period(year_expr, period_expr) }} then 1.0
            {# Acquisition is after this period end — zero #}
            when {{ acquisition_date_expr }} >= addMonths({{ build_date_from_year_period(year_expr, period_expr) }}, 1) then 0.0
            {# Acquisition is within this period — prorate #}
            else toFloat64(
                dateDiff('day', {{ acquisition_date_expr }},
                    addMonths({{ build_date_from_year_period(year_expr, period_expr) }}, 1)
                )
            ) / dateDiff('day',
                {{ build_date_from_year_period(year_expr, period_expr) }},
                addMonths({{ build_date_from_year_period(year_expr, period_expr) }}, 1)
            )
        end
    )
{% endmacro %}
