{#
    A non-identity FX rate of implausible magnitude is a scaling error, not a
    market move. This is the guard #138 lacked — assert_exchange_rate_positive
    passed throughout that bug, because 0.00935 is positive.

    Bounds are per magnitude class. WIDE_BAND lists currencies that quote far
    from parity against the majors — small-unit currencies (JPY, KRW, IDR, VND)
    and mid-magnitude ones (INR ~88/USD, RUB, PHP, TRY, THB, CZK, HUF, CLP,
    ISK): real rates for these sit outside [0.05, 20], so they get [1e-4, 1e4].
    The wide band cannot catch a 100x error on those pairs — a conscious trade
    against failing the build on correct data. Extend WIDE_BAND when a new
    far-from-parity currency enters the data; everything else gets the tight
    band, where a 100x error always trips a bound.
#}

{% set wide_band = "('JPY','KRW','IDR','VND','HUF','CLP','ISK','INR','RUB','PHP','TRY','THB','CZK')" %}

with rates as (

    select
        from_currency,
        to_currency,
        exchange_rate,
        valid_from,
        (from_currency in {{ wide_band }} or to_currency in {{ wide_band }}) as is_wide,
        if(from_currency in {{ wide_band }} or to_currency in {{ wide_band }}, 0.0001, 0.05) as lo,
        if(from_currency in {{ wide_band }} or to_currency in {{ wide_band }}, 10000.0, 20.0) as hi
    from {{ ref('silver_exchange_rates') }}
    where from_currency != to_currency

)

select
    from_currency,
    to_currency,
    exchange_rate,
    valid_from,
    concat('outside [', toString(lo), ', ', toString(hi), '] for a ',
           if(is_wide, 'wide-band', 'tight-band'), ' pair') as problem
from rates
where exchange_rate < lo or exchange_rate > hi
