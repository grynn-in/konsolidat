-- Test: All exchange rates must be positive after silver cleaning
select
    from_currency,
    to_currency,
    valid_from,
    exchange_rate
from {{ ref('silver_exchange_rates') }}
where exchange_rate <= 0
