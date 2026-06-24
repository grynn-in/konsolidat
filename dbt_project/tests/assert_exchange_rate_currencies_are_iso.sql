-- grynn-in/konsolidat#91: every currency code used in FX must be a known ISO 4217
-- code present in the currencies seed. from_currency / to_currency are otherwise
-- unvalidated free strings — a typo or an unmapped code silently mis-translates
-- (or drops to the 1.0 fallback) instead of failing the build.
--
-- Uses NOT IN (not a left-join null check): ClickHouse left joins fill a miss
-- with the column default ('') rather than NULL when join_use_nulls=0.

with used as (
    select from_currency as currency_code from {{ ref('silver_exchange_rates') }}
    union distinct
    select to_currency as currency_code from {{ ref('silver_exchange_rates') }}
)

select currency_code
from used
where currency_code != ''
  and currency_code not in (select currency_code from {{ ref('currencies') }})
