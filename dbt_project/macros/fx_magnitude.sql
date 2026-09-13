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

    A currency has NO reference when
        isNaN(usd_log10) OR (usd_log10 = 0 AND currency_code != 'USD')
    (USD is 0 by definition; a 0 anywhere else is an unset value). The same
    rule as konsol #174. A rate involving a currency with no reference is
    named by the tests; the model's guard does not refuse it. (A >50% move between periods only asks for a reason in konsol; it
    is a soft check and has no place here.)
#}

{# The currencies that HAVE a reference magnitude (the rule above). Use as a
   CTE: `ref_mag as {{ fx_reference_magnitudes() }}`. The guard in
   macros/governed_rates.sql and both magnitude tests read only this. #}
{% macro fx_reference_magnitudes() -%}
(select currency_code, toFloat64(usd_log10) as usd_log10
 from {{ source('epm_gold', 'currencies') }}
 where {{ fx_has_reference('currency_code', 'usd_log10') }})
{%- endmacro %}

{# THE magnitude rule: more than one decade (10x) from what the references
   imply. Exactly 10x is plausible. Used by fx_magnitude_problem (the warn
   tests) AND by the model's guard (governed_rate_gaps), so the shared case
   test (assert_fx_magnitude_cases) covers the rule that refuses builds. #}
{% macro fx_is_implausible(rate, from_log10, to_log10) -%}
(abs(log10({{ rate }}) - ({{ to_log10 }} - {{ from_log10 }})) > 1)
{%- endmacro %}

{# The "has a reference" rule itself, on any (code, usd_log10) pair. #}
{% macro fx_has_reference(code, usd_log10) -%}
not (isNaN({{ usd_log10 }}) or ({{ usd_log10 }} = 0 and {{ code }} != 'USD'))
{%- endmacro %}

{# '' when the rate is plausible, else why not. The log10 columns come from
   LEFT JOINs to `refs`; a miss there is caught by the NOT IN checks first. #}
{% macro fx_magnitude_problem(rate, from_ccy, to_ccy, from_log10, to_log10, refs='ref_mag') -%}
multiIf(
    not isFinite({{ rate }}), 'not a finite number',
    {{ rate }} <= 0, 'not positive',
    {{ from_ccy }} not in (select currency_code from {{ refs }}),
        concat('no reference magnitude for ', {{ from_ccy }}, ' (ISO Currency.usd_log10)'),
    {{ to_ccy }} not in (select currency_code from {{ refs }}),
        concat('no reference magnitude for ', {{ to_ccy }}, ' (ISO Currency.usd_log10)'),
    {{ fx_is_implausible(rate, from_log10, to_log10) }},
        'more than 10x from the reference magnitudes',
    ''
)
{%- endmacro %}

{# True when epm_gold.currencies carries usd_log10. CREATE TABLE IF NOT EXISTS
   never adds a column, so an existing volume has only the four old ones until
   konsol's migration (#174) adds it. A test that selected the missing column
   would ERROR, and an erroring test (unlike a failing warn one) makes
   `dbt build` skip every model downstream of its parents. The magnitude tests
   return one warn row instead. Callers must also call source('epm_gold',
   'currencies') at top level so the dependency is known at parse time. #}
{% macro fx_reference_column_present() -%}
    {%- if not execute -%}{{ return(false) }}{%- endif -%}
    {%- set cols = adapter.get_columns_in_relation(source('epm_gold', 'currencies')) -%}
    {{ return('usd_log10' in (cols | map(attribute='name') | list)) }}
{%- endmacro %}
