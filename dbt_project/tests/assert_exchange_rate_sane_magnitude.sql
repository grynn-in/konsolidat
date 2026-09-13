{{ config(severity='warn') }}
{#
    A non-identity FX rate of implausible magnitude is a scaling error, not a
    market move. This is the guard #138 lacked: assert_exchange_rate_positive
    passed throughout that bug, because 0.00935 is positive.

    The ERP feed is no longer what translation reads (konsolidat#93); it
    pre-fills drafts in konsol. It is still checked, with the same rule as the
    governed rates and konsol's entry guard (konsol.group_rates.magnitude_problem):
    macros/fx_magnitude.sql. A rate more than 10x from the currencies'
    reference magnitudes (ISO Currency.usd_log10) is named; so is a currency
    with no reference value, and a rate that is not a finite number. The old
    per-class bands ([0.05, 20] and [1e-4, 1e4]) refused real IDR/VND rates
    against the dollar and could not catch a 100x error on a wide-band pair.

    severity warn, as agreed in the #176 review. Until epm_gold.currencies has
    usd_log10 (konsol #174 adds it), this returns one warn row instead of
    erroring on the missing column.
#}
{%- set rates = ref('silver_exchange_rates') -%}
{%- set currencies = source('epm_gold', 'currencies') -%}

{% if not fx_reference_column_present() %}

select 'usd_log10 not present yet in epm_gold.currencies: run the konsol migration from #174' as problem

{% else %}

with ref_mag as {{ fx_reference_magnitudes() }},

checked as (
    select
        r.from_currency as from_currency,
        r.to_currency as to_currency,
        r.exchange_rate as exchange_rate,
        r.exchange_rate_type as exchange_rate_type,
        r.valid_from as valid_from,
        {{ fx_magnitude_problem('r.exchange_rate', 'r.from_currency', 'r.to_currency', 'f.usd_log10', 't.usd_log10') }} as problem
    from {{ rates }} as r
    left join ref_mag as f on f.currency_code = r.from_currency
    left join ref_mag as t on t.currency_code = r.to_currency
    where r.from_currency != r.to_currency
)

select * from checked where problem != ''

{% endif %}
