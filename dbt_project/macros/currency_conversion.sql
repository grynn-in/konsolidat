{% macro convert_currency(amount_column, from_currency_column, to_currency, rate_date_column, rate_type='Default') %}
    {{ amount_column }} * coalesce(
        (
            select er.exchange_rate
            from {{ ref('silver_exchange_rates') }} as er
            where er.from_currency = {{ from_currency_column }}
              and er.to_currency = '{{ to_currency }}'
              and er.valid_from <= {{ rate_date_column }}
              and er.valid_to >= {{ rate_date_column }}
              {% if rate_type != 'Default' %}
              and er.exchange_rate_type = '{{ rate_type }}'
              {% endif %}
            order by er.valid_from desc
            limit 1
        ),
        1.0  -- Default to 1.0 if no rate found (same currency)
    )
{% endmacro %}
