{#
    A non-identity FX rate of implausible magnitude is almost certainly a
    scaling error, not a market move.

    #138: rates were scaled by 100 twice — staging normalised to x100, silver
    divided unconditionally — so EUR->CHF landed at 0.00935 and a 41.9M USD
    subsidiary consolidated as 365K CHF. assert_exchange_rate_positive passed
    throughout, because 0.00935 is positive. This test is the one that would
    have caught it.

    Bounds are per magnitude class, because JPY-like currencies quote in the
    hundreds legitimately (USD->JPY ~150, JPY->USD ~0.0066):

      - both currencies "unit" class:  [0.05, 20]
      - any "cent" class currency:     [0.0001, 10000]

    The cent-class band is wide enough that it will NOT catch a 100x error on
    those pairs — a conscious trade against false alarms on real JPY rates.
    Extend CENT_CLASS when a new small-unit currency enters the data.
#}

{% set cent_class = "('JPY','KRW','IDR','VND','HUF','CLP','ISK')" %}

select
    from_currency,
    to_currency,
    exchange_rate,
    valid_from,
    if(from_currency in {{ cent_class }} or to_currency in {{ cent_class }},
       'outside [0.0001, 10000] for a cent-class pair',
       'outside [0.05, 20] for a unit-class pair') as problem
from {{ ref('silver_exchange_rates') }}
where from_currency != to_currency
  and (
        (from_currency not in {{ cent_class }}
         and to_currency not in {{ cent_class }}
         and (exchange_rate < 0.05 or exchange_rate > 20))
     or (exchange_rate < 0.0001 or exchange_rate > 10000)
  )
