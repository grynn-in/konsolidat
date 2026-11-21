{#
    konsolidat#387 (IAS 21.47): the goodwill and the fair-value adjustments arising on the acquisition of a
    foreign operation are assets of that operation, expressed in ITS functional currency and translated at the
    closing rate of each reporting date; the difference goes to CTA. So at every period P from the acquisition
    period on:

        goodwill in group currency at P = goodwill in the entity's currency x Closing(P)
        FVA in group currency at P      = FVA in the entity's currency x Closing(P)

    The expectation is worked out here from the deal's SOURCE tables, not from the journal's formula:
        goodwill (entity currency) = consideration - (net assets at book + fair-value adjustments)
        net assets at book         = the acquired balances on non-equity accounts
        FVA (entity currency)      = the fair-value adjustments on the acquired balances
    and Closing(P) is the governed Closing rate of the actuals Rate Set for the period (the rate's own year and
    period: this rule is checked on calendar-mapped periods).

    The actual is the cumulative amount of the goodwill / fair-value-adjustment account in
    gold_fully_consolidated_tb up to P (it is a movement trial balance, every reader sums to date).

    Scope: 100% acquisitions with the consideration in the entity's own currency and a foreign entity. (A partial
    deal adds the NCI measurement to goodwill and a consideration in a third currency adds a second rate; both
    need their own oracle.) Deals with a rate-less period are skipped for that period.
#}

with deals as (
    select
        bc.name as deal,
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as data_area_id,
        e.accounting_currency as entity_currency,
        g.reporting_currency as reporting_currency,
        g.goodwill_account as goodwill_account,
        g.fair_value_adjustment_account as fva_account,
        toFloat64(bc.total_consideration) as consideration,
        toUInt32(toYear(bc.acquisition_date)) * 1000 + toMonth(bc.acquisition_date) as acquisition_ord
    from {{ source('epm_staging', 'business_combinations') }} as bc
    inner join {{ source('epm_staging', 'entities') }} as e
        on bc.acquired_entity = e.data_area_id
    inner join {{ source('epm_gold', 'consolidation_groups') }} as g
        on bc.consolidation_group = g.consolidation_group
        and g.data_area_id = ''
    where bc.share_acquired_pct = 100
      and bc.consideration_currency = e.accounting_currency
      and e.accounting_currency != g.reporting_currency
),

balances as (
    select
        ab.parent as deal,
        sumIf(toFloat64(ab.book_amount), a.is_equity = 0) as net_assets_book,
        sum(toFloat64(ab.fair_value_adjustment)) as fva_local
    from {{ source('epm_staging', 'business_combination_acquired_balances') }} as ab
    inner join {{ ref('silver_main_accounts') }} as a
        on ab.main_account = a.main_account_id
    group by ab.parent
),

local_figures as (
    select
        d.deal as deal,
        d.consolidation_group as consolidation_group,
        d.data_area_id as data_area_id,
        d.entity_currency as entity_currency,
        d.reporting_currency as reporting_currency,
        d.goodwill_account as goodwill_account,
        d.fva_account as fva_account,
        d.acquisition_ord as acquisition_ord,
        d.consideration - (b.net_assets_book + b.fva_local) as goodwill_local,
        b.fva_local as fva_local
    from deals as d
    inner join balances as b
        on d.deal = b.deal
),

closing as (
    select
        from_currency,
        to_currency,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        any(toFloat64(rate)) as closing_rate
    from {{ source('epm_staging', 'group_exchange_rates') }}
    where rate_type = 'Closing'
      and {{ actuals_rate_set_predicate() }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

expected as (
    select
        f.deal as deal,
        f.consolidation_group as consolidation_group,
        c.fiscal_year as fiscal_year,
        c.fiscal_period as fiscal_period,
        'goodwill' as item,
        f.goodwill_account as account,
        f.goodwill_local as local_amount,
        c.closing_rate as closing_rate,
        f.goodwill_local * c.closing_rate as expected_amount
    from local_figures as f
    inner join closing as c
        on f.entity_currency = c.from_currency
        and f.reporting_currency = c.to_currency
    where toUInt32(c.fiscal_year) * 1000 + c.fiscal_period >= f.acquisition_ord

    union all

    select
        f.deal,
        f.consolidation_group,
        c.fiscal_year,
        c.fiscal_period,
        'fair-value adjustment',
        f.fva_account,
        f.fva_local,
        c.closing_rate,
        f.fva_local * c.closing_rate
    from local_figures as f
    inner join closing as c
        on f.entity_currency = c.from_currency
        and f.reporting_currency = c.to_currency
    where toUInt32(c.fiscal_year) * 1000 + c.fiscal_period >= f.acquisition_ord
),

actual as (
    select
        x.deal as deal,
        x.fiscal_year as fiscal_year,
        x.fiscal_period as fiscal_period,
        x.account as account,
        sum(t.amount) as actual_amount
    from expected as x
    inner join {{ ref('gold_fully_consolidated_tb') }} as t
        on t.consolidation_group = x.consolidation_group
        and t.main_account = x.account
    where toUInt32(t.fiscal_year) * 1000 + t.fiscal_period <= toUInt32(x.fiscal_year) * 1000 + x.fiscal_period
    group by x.deal, x.fiscal_year, x.fiscal_period, x.account
)

select
    x.deal as deal,
    x.fiscal_year as fiscal_year,
    x.fiscal_period as fiscal_period,
    x.item as item,
    x.account as account,
    x.local_amount as local_amount,
    x.closing_rate as closing_rate,
    x.expected_amount as expected_amount,
    ifNull(a.actual_amount, 0) as actual_amount,
    concat(
        'deal ', x.deal, ' at FY', toString(x.fiscal_year), ' P', toString(x.fiscal_period),
        ': the ', x.item, ' on ', x.account, ' is ', toString(round(ifNull(a.actual_amount, 0), 2)),
        ' in group currency, but ', toString(round(x.local_amount, 2)), ' in the entity currency at the closing rate ',
        toString(x.closing_rate), ' is ', toString(round(x.expected_amount, 2)),
        ' (konsolidat#387, IAS 21.47: goodwill and fair-value adjustments of a foreign operation are retranslated at the closing rate).'
    ) as problem
from expected as x
left join actual as a
    on x.deal = a.deal
    and x.fiscal_year = a.fiscal_year
    and x.fiscal_period = a.fiscal_period
    and x.account = a.account
where abs(ifNull(a.actual_amount, 0) - x.expected_amount) > 0.01
