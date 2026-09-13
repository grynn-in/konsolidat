{#
    konsol#103: one approved governed rate per (group reporting currency,
    from-currency, fiscal year, fiscal period, rate type). konsol refuses a
    second approval of a key; a collision here would make the translation pick
    one quietly (anyIf), so it fails the build instead.
#}

select
    to_currency,
    from_currency,
    fiscal_year,
    fiscal_period,
    rate_type,
    count() as approved_rows,
    groupArray(document) as documents
from {{ source('epm_staging', 'group_exchange_rates') }}
group by to_currency, from_currency, fiscal_year, fiscal_period, rate_type
having count() > 1
