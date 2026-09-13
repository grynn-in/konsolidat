{#
    The #138 magnitude bands, shared by the ERP-feed test
    (assert_exchange_rate_sane_magnitude) and the governed-rate test
    (assert_governed_rate_sane). KEEP IN STEP with konsol's group_rates.py
    (WIDE_BAND, TIGHT_BOUNDS, WIDE_BOUNDS), which applies the same guard when a
    rate is entered.

    Currencies that quote far from parity against the majors get the wide band
    [1e-4, 1e4]; everything else the tight band [0.05, 20].
#}
{% macro fx_wide_band() -%}
('JPY','KRW','IDR','VND','HUF','CLP','ISK','INR','RUB','PHP','TRY','THB','CZK')
{%- endmacro %}
