{{ config(severity='warn') }}
{#
    konsol#103 / #138: a governed rate is a positive, finite, true rate of
    plausible magnitude, of a governed type, between two different currencies.
    konsol refuses each of these at entry (konsol.group_rates.magnitude_problem
    for the magnitude); this names a row that reached the warehouse another way
    (a script, a restore). The magnitude rule is macros/fx_magnitude.sql. A
    zero, negative, non-finite or duplicate rate the translation needs also
    stops the model (governed_rate_guard); a merely implausible one is named
    here only.

    severity warn: an error-severity source test would make `dbt build` skip
    the model. Until epm_gold.currencies has usd_log10 (konsol #174 adds it),
    this returns one warn row instead of erroring on the missing column.
#}
{%- set governed = source('epm_staging', 'group_exchange_rates') -%}
{%- set currencies = source('epm_gold', 'currencies') -%}

{% if not fx_reference_column_present() %}

select 'usd_log10 not present yet in epm_gold.currencies: run the konsol migration from #174' as problem

{% else %}

with ref_mag as {{ fx_reference_magnitudes() }},

checked as (
    select
        g.to_currency as to_currency,
        g.from_currency as from_currency,
        g.fiscal_year as fiscal_year,
        g.fiscal_period as fiscal_period,
        g.rate_type as rate_type,
        g.rate as rate,
        g.document as document,
        multiIf(
            g.from_currency = g.to_currency, 'a rate from a currency into itself',
            g.rate_type not in ('Closing', 'Average'), 'not a governed rate type',
            {{ fx_magnitude_problem('g.rate', 'g.from_currency', 'g.to_currency', 'f.usd_log10', 't.usd_log10') }}
        ) as problem
    from {{ governed }} as g
    left join ref_mag as f on f.currency_code = g.from_currency
    left join ref_mag as t on t.currency_code = g.to_currency
)

select * from checked where problem != ''

{% endif %}
