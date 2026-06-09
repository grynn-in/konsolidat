{# PRD-11: Prorate an amount to post-acquisition days only.
   Returns fraction = days_post_acquisition / days_in_period.
   If no acquisition in the period, returns 1.0.
   If acquisition_date is after period end, returns 0.0.
   acquisition_date: Date, fiscal_year: UInt16, fiscal_period: UInt8 #}

{% macro prorate_period_amount(amount_expr, acquisition_date_expr, year_expr, period_expr) %}
    {{ amount_expr }} * (
        case
            {# No acquisition constraint — full amount #}
            when {{ acquisition_date_expr }} <= toDate('1900-01-01') then 1.0
            {# Acquisition is before this period — full amount #}
            when {{ acquisition_date_expr }} < {{ build_date_from_year_period(year_expr, period_expr) }} then 1.0
            {# Acquisition is after this period end — zero #}
            when {{ acquisition_date_expr }} >= {{ build_date_from_year_period(year_expr, 'least(' ~ period_expr ~ ' + 1, 13)') }} then 0.0
            {# Acquisition is within this period — prorate #}
            else toFloat64(
                dateDiff('day', {{ acquisition_date_expr }},
                    {{ build_date_from_year_period(year_expr, 'least(' ~ period_expr ~ ' + 1, 13)') }}
                )
            ) / dateDiff('day',
                {{ build_date_from_year_period(year_expr, period_expr) }},
                {{ build_date_from_year_period(year_expr, 'least(' ~ period_expr ~ ' + 1, 13)') }}
            )
        end
    )
{% endmacro %}
