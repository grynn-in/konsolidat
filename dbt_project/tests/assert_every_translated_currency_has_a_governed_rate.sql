{#
    konsolidat#93 / konsol#103: every currency the consolidated trial balance
    translates must have an APPROVED governed Closing and Average rate for its
    period, into the group's reporting currency. gold_consolidated_trial_balance
    itself refuses to build without one (throwIf); this names what is missing,
    in the shape a person fixes it: pre-fill or enter the rate in konsol's Group
    Exchange Rate and approve it. Never a 0, never the 1.0 parity fallback.

    The keys are recomputed from the model's inputs rather than read from the
    model (which a missing rate stops from building), with the model's own
    filters: resolved entity currencies, a complete ownership chain, line
    consolidation. The group's currency comes from its node, as in the model.
    NOT IN rather than a LEFT JOIN null test (join_use_nulls=0).
#}

with translated as (
    select distinct
        ec.accounting_currency as from_ccy,
        grp.reporting_currency as to_ccy,
        toUInt16(tb.fiscal_year) as fy,
        toUInt16(tb.fiscal_period) as fp
    from {{ ref('gold_trial_balance') }} as tb
    inner join (
        select data_area_id, accounting_currency
        from {{ ref('silver_entity_currencies') }}
        where accounting_currency != ''
    ) as ec
        on ec.data_area_id = tb.data_area_id
    inner join {{ ref('gold_entity_ownership') }} as eo
        on eo.data_area_id = tb.data_area_id
        and eo.fiscal_year = tb.fiscal_year
        and eo.fiscal_period = tb.fiscal_period
    left join (
        select consolidation_group, reporting_currency
        from {{ source('epm_gold', 'consolidation_groups') }}
        where data_area_id = ''
    ) as grp
        on grp.consolidation_group = eo.consolidation_group
    where eo.consolidation_method not in ('equity', 'none')
      and eo.has_complete_chain = 1
      and ec.accounting_currency != grp.reporting_currency
),

governed as (
    select
        from_currency as from_ccy,
        to_currency as to_ccy,
        toUInt16(fiscal_year) as fy,
        toUInt16(fiscal_period) as fp
    from {{ source('epm_staging', 'group_exchange_rates') }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
    having countIf(rate_type = 'Closing') > 0 and countIf(rate_type = 'Average') > 0
)

select
    from_ccy as from_currency,
    to_ccy as to_currency,
    fy as fiscal_year,
    fp as fiscal_period,
    'no approved governed Closing and Average rate (konsol Group Exchange Rate)' as problem
from translated
where (from_ccy, to_ccy, fy, fp) not in (select from_ccy, to_ccy, fy, fp from governed)
