{#
    konsol#103 / #138: a governed rate is a positive, true rate of plausible
    magnitude, of a governed type, between two different currencies. konsol
    refuses each of these at entry; this catches a row that reached the
    warehouse another way (a script, a restore). Bands: macros/fx_magnitude.sql.
#}

{% set wide_band = fx_wide_band() | trim %}

select
    to_currency,
    from_currency,
    fiscal_year,
    fiscal_period,
    rate_type,
    rate,
    document,
    multiIf(
        rate <= 0, 'not positive',
        from_currency = to_currency, 'a rate from a currency into itself',
        rate_type not in ('Closing', 'Average'), 'not a governed rate type',
        'outside the #138 magnitude band for the pair'
    ) as problem
from {{ source('epm_staging', 'group_exchange_rates') }}
where rate <= 0
   or from_currency = to_currency
   or rate_type not in ('Closing', 'Average')
   or rate < if(from_currency in {{ wide_band }} or to_currency in {{ wide_band }}, 0.0001, 0.05)
   or rate > if(from_currency in {{ wide_band }} or to_currency in {{ wide_band }}, 10000.0, 20.0)
