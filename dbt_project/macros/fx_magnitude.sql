{#
    The #138 magnitude rule: ONE formula, used by the ERP-feed test
    (assert_exchange_rate_sane_magnitude) and the governed-rate test
    (assert_governed_rate_sane). KEEP IN STEP with konsol's
    konsol.group_rates.magnitude_problem, which refuses the same rates when
    they are entered.

    Every ISO Currency carries usd_log10: roughly log10 of its units per 1 USD
    (published to epm_gold.currencies). A rate from F into T is implausible
    when it is more than 10x from what those imply:

        abs(log10(rate) - (usd_log10(T) - usd_log10(F))) > 1

    A currency with no reference value fails: an unknown magnitude cannot be
    checked. (A >50% move between periods only asks for a reason in konsol; it
    is a soft check and has no place here.)
#}

{# The currencies that have a reference magnitude. Use as a CTE: `ref_mag as {{ fx_reference_magnitudes() }}` #}
{% macro fx_reference_magnitudes() -%}
(select currency_code, toFloat64(usd_log10) as usd_log10
 from {{ source('epm_gold', 'currencies') }}
 where isFinite(usd_log10))
{%- endmacro %}

{# '' when the rate is plausible, else why not. The log10 columns come from
   LEFT JOINs to `refs`; a miss there is caught by the NOT IN checks first. #}
{% macro fx_magnitude_problem(rate, from_ccy, to_ccy, from_log10, to_log10, refs='ref_mag') -%}
multiIf(
    {{ rate }} <= 0, 'not positive',
    {{ from_ccy }} not in (select currency_code from {{ refs }}),
        concat('no reference magnitude for ', {{ from_ccy }}, ' (ISO Currency.usd_log10)'),
    {{ to_ccy }} not in (select currency_code from {{ refs }}),
        concat('no reference magnitude for ', {{ to_ccy }}, ' (ISO Currency.usd_log10)'),
    abs(log10({{ rate }}) - ({{ to_log10 }} - {{ from_log10 }})) > 1,
        'more than 10x from the reference magnitudes',
    ''
)
{%- endmacro %}
