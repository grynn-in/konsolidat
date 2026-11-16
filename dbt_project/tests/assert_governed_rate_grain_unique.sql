{{ config(severity='warn') }}
{#
    konsol#103: one approved governed rate per (group reporting currency,
    from-currency, fiscal year, fiscal period, rate type, rate set). konsol
    refuses a second approval of a key; a collision here would make the
    translation pick one quietly (anyIf), so it is named here. konsol#348 S4
    (S4-Q1 c): the Rate Set is part of the key, so the actuals and a budget's
    rate for one period are two rows, not a collision; this judges
    every Rate Set, each on its own. severity warn: an error-severity source
    test would make `dbt build` skip the model (konsolidat#176 review).
#}

select
    to_currency,
    from_currency,
    fiscal_year,
    fiscal_period,
    rate_type,
    rate_set,
    count() as approved_rows,
    groupArray(document) as documents
from {{ source('epm_staging', 'group_exchange_rates') }}
group by to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate_set
having count() > 1
