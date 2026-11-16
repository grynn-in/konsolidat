-- konsol#348 S4 (W2, S4-Q1 c): every consolidated row that translates a foreign currency carries
-- the Closing and Average rate of the one Rate Set flagged Is Actuals (epm_staging.rate_sets), for
-- its rate period, and no other set's. A budget's set may hold a different rate for the same
-- (from, to, year, period) key; before the rate tables carried rate_set the model read every row
-- and a second set's rate was a duplicate that stopped the build, or, had the guard not caught it,
-- an arbitrary pick (anyIf). The model filters its rates through actuals_rate_set_predicate()
-- (macros/governed_rates.sql); this test resolves the expected rate from the same table with the
-- same predicate and compares, so a model that read the wrong set, or every set, is named here.
--
-- The rate period is the row's period mapped through rate_period_map() (a Closing-type period
-- translates at its year's last Regular period's rates, konsolidat#199 row D9), exactly as the model
-- maps it. Same-currency rows (accounting = reporting, rate 1.0 by definition) are not judged; a
-- row whose key has no actuals rate cannot exist in a built table (the guard refuses), so the join
-- is inner and a miss is a model that resolved a rate from somewhere else.
--
-- Fails (returns rows) when a translated row's closing_rate or average_rate differs from the
-- actuals set's rate for its key, or the key has no actuals rate.

with actuals_rates as (
    select
        from_currency,
        to_currency,
        toUInt16(fiscal_year) as rate_year,
        toUInt16(fiscal_period) as rate_period,
        anyIf(toFloat64(rate), rate_type = 'Closing') as closing_rate,
        anyIf(toFloat64(rate), rate_type = 'Average') as average_rate
    from {{ source('epm_staging', 'group_exchange_rates') }}
    where {{ actuals_rate_set_predicate() }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

translated as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        toUInt16(ctb.fiscal_year) as fy,
        toUInt16(ctb.fiscal_period) as fp,
        ctb.accounting_currency as accounting_currency,
        ctb.reporting_currency as reporting_currency,
        if(rpm.mapped = 1, rpm.rate_year, toUInt16(ctb.fiscal_year)) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, toUInt16(ctb.fiscal_period)) as rate_period,
        {# fresh aliases: an alias equal to a column it reads is a cyclic alias in ClickHouse #}
        ctb.closing_rate as model_closing_rate,
        ctb.average_rate as model_average_rate
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = toUInt16(ctb.fiscal_year)
        and rpm.fiscal_period = toUInt16(ctb.fiscal_period)
    where ctb.accounting_currency != ''
      and ctb.accounting_currency != ctb.reporting_currency
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period,
             ctb.accounting_currency, ctb.reporting_currency, rpm.mapped, rpm.rate_year, rpm.rate_period,
             ctb.closing_rate, ctb.average_rate
)

select
    t.consolidation_group,
    t.data_area_id,
    t.fy as fiscal_year,
    t.fp as fiscal_period,
    t.accounting_currency,
    t.reporting_currency,
    t.rate_year,
    t.rate_period,
    t.model_closing_rate,
    t.model_average_rate,
    r.closing_rate as actuals_closing_rate,
    r.average_rate as actuals_average_rate,
    multiIf(
        (t.accounting_currency, t.reporting_currency, t.rate_year, t.rate_period) not in (
            select from_currency, to_currency, rate_year, rate_period from actuals_rates), 'no actuals rate for this key',
        abs(t.model_closing_rate - r.closing_rate) > 1e-9, 'closing rate is not the actuals set''s',
        abs(t.model_average_rate - r.average_rate) > 1e-9, 'average rate is not the actuals set''s',
        ''
    ) as problem
from translated as t
left join actuals_rates as r
    on r.from_currency = t.accounting_currency
    and r.to_currency = t.reporting_currency
    and r.rate_year = t.rate_year
    and r.rate_period = t.rate_period
where problem != ''
