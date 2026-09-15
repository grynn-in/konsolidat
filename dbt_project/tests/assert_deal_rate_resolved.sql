-- konsolidat#198 (row J9; PR #203 review 3 + 4): a submitted deal that needs a governed Closing rate the group
-- has not published for its period. gold_business_combination_journal and gold_business_disposal_journal
-- INNER JOIN every rate they translate at, so such a deal posts NOTHING (never a 0: a LEFT JOIN miss read 0
-- under join_use_nulls = 0 and booked a false bargain gain, or goodwill = consideration, or a false disposal
-- loss). Silence is not an answer either: this test stops the build and names the pair. One row per submitted
-- deal and (from_currency, to_currency) it needs with no Closing rate for its period. Fixture:
-- dbt_project/test_fixtures/assert_deal_rate_resolved.must_flag.sql.
--
-- The currencies a deal needs, exactly the ones the journals translate:
--   the entity's accounting currency (epm_staging.entities; '' when the entity is not in the registry, and
--     that is reported as such): the acquired balances, the opening balances, the derecognised balances
--   each consideration / acquisition-costs / proceeds line's own currency
--   the header's consideration_currency / proceeds_currency, when the document has no consideration (proceeds)
--     lines and the header amount is not zero (the journals fall back to the header figure then). Row J13
--     (PR #203 second review 1): the acquisition-costs lines do NOT count here — the journal's
--     consideration_line_count reads only business_combination_consideration, so a combination with a header
--     amount, no consideration line and one cost line falls back to the header and needs its rate; counting
--     the cost row as "a line" left that header unchecked while the journal dropped the deal silently. Fixture:
--     dbt_project/test_fixtures/assert_deal_rate_resolved.header.must_flag.sql.
--   a combination's consideration_currency when it measures NCI at 'full' and share_acquired_pct < 100
--     (konsol#204, row M2b): the journal translates the declared NCI fair value at that currency's rate and
--     drops the deal when it is missing, even when every consideration line is in another currency. Row M4
--     (PR #205 review): whatever nci_fair_value says, exactly the journal's condition. Fixtures:
--     dbt_project/test_fixtures/assert_deal_rate_resolved.nci_fair_value.must_flag.sql,
--     dbt_project/test_fixtures/assert_deal_rate_resolved.nci_fair_value_zero.must_flag.sql.
-- into the group's reporting currency (the root row of epm_gold.consolidation_groups), for the deal's period:
-- epm_staging.fiscal_periods by start_date <= date <= end_date (Closing periods skipped), then
-- rate_period_map() (so a Closing period would ask for its year's last Regular period's rates, as every
-- trial-balance translation does). A currency equal to the group currency translates at 1 and needs no rate.
--
-- Scope follows the journals: every submitted Business Combination; a Business Disposal with
-- retained_interest_pct = 0 (a disposal that keeps an interest posts nothing and is named by
-- assert_disposal_gain_loss_exists). A deal whose group has no root row or whose date is outside the declared
-- calendar has no period to look a rate up for; assert_acquisition_accounts_declared names those.
-- Reported: deal, kind ('business_combination' | 'business_disposal'), from_currency, to_currency, and the
-- deal's fiscal_year / fiscal_period. NOT IN rather than a LEFT JOIN null test (join_use_nulls = 0).
with root as (
    select consolidation_group, any(reporting_currency) as reporting_currency
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

entity_currency as (
    select data_area_id, any(accounting_currency) as accounting_currency
    from {{ source('epm_staging', 'entities') }}
    group by data_area_id
),

closing_rates as (
    select
        from_currency,
        to_currency,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period
    from {{ source('epm_staging', 'group_exchange_rates') }}
    where rate_type = 'Closing'
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

-- the calendar period holding each deal's date, as the journals find it (span, never month)
combination_period as (
    select
        bc.name as deal,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bc.acquisition_date
      and fp.end_date >= bc.acquisition_date
      and fp.period_type != 'Closing'
    group by bc.name
),

disposal_period as (
    select
        bd.name as deal,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bd.disposal_date
      and fp.end_date >= bd.disposal_date
      and fp.period_type != 'Closing'
    group by bd.name
),

-- one row per deal in scope: its entity, header currency and amount, period, rate period, group currency
deals as (
    select
        bc.name as deal,
        'business_combination' as kind,
        bc.acquired_entity as entity,
        bc.consideration_currency as header_currency,
        toFloat64(bc.total_consideration) as header_amount,
        bc.nci_measurement as nci_measurement,
        toFloat64(bc.share_acquired_pct) as share_acquired_pct,
        toFloat64(bc.nci_fair_value) as nci_fair_value,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period,
        if(rpm.mapped = 1, rpm.rate_year, dp.fiscal_year) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, dp.fiscal_period) as rate_period,
        r.reporting_currency as to_currency
    from {{ source('epm_staging', 'business_combinations') }} as bc
    inner join root as r
        on r.consolidation_group = bc.consolidation_group
    inner join combination_period as dp
        on dp.deal = bc.name
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = dp.fiscal_year
        and rpm.fiscal_period = dp.fiscal_period

    union all

    select
        bd.name as deal,
        'business_disposal' as kind,
        bd.disposed_entity as entity,
        bd.proceeds_currency as header_currency,
        toFloat64(bd.total_proceeds) as header_amount,
        '' as nci_measurement,
        100.0 as share_acquired_pct,
        0.0 as nci_fair_value,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period,
        if(rpm.mapped = 1, rpm.rate_year, dp.fiscal_year) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, dp.fiscal_period) as rate_period,
        r.reporting_currency as to_currency
    from {{ source('epm_staging', 'business_disposals') }} as bd
    inner join root as r
        on r.consolidation_group = bd.consolidation_group
    inner join disposal_period as dp
        on dp.deal = bd.name
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = dp.fiscal_year
        and rpm.fiscal_period = dp.fiscal_period
    where toFloat64(bd.retained_interest_pct) <= 0.0
),

-- the currency of every line the journals translate, by document
line_currencies as (
    select parent as deal, 'business_combination' as kind, currency as from_currency
    from {{ source('epm_staging', 'business_combination_consideration') }}
    union all
    select parent as deal, 'business_combination' as kind, currency as from_currency
    from {{ source('epm_staging', 'business_combination_costs') }}
    union all
    select parent as deal, 'business_disposal' as kind, currency as from_currency
    from {{ source('epm_staging', 'business_disposal_proceeds') }}
),

-- the lines that switch the journals OFF the header fallback: exactly the tables their
-- consideration_line_count / proceeds_line_count read (costs are line (6), not consideration)
header_fallback_line_counts as (
    select parent as deal, 'business_combination' as kind, count() as n_lines
    from {{ source('epm_staging', 'business_combination_consideration') }}
    group by parent
    union all
    select parent as deal, 'business_disposal' as kind, count() as n_lines
    from {{ source('epm_staging', 'business_disposal_proceeds') }}
    group by parent
),

-- every (deal, from_currency) pair the journals need
needed as (
    select
        d.deal as deal,
        d.kind as kind,
        coalesce(ec.accounting_currency, '') as from_currency,
        d.to_currency as to_currency,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.rate_year as rate_year,
        d.rate_period as rate_period
    from deals as d
    left join entity_currency as ec
        on ec.data_area_id = d.entity

    union all

    select
        d.deal as deal,
        d.kind as kind,
        lc.from_currency as from_currency,
        d.to_currency as to_currency,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.rate_year as rate_year,
        d.rate_period as rate_period
    from deals as d
    inner join line_currencies as lc
        on lc.deal = d.deal
        and lc.kind = d.kind

    union all

    select
        d.deal as deal,
        d.kind as kind,
        d.header_currency as from_currency,
        d.to_currency as to_currency,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.rate_year as rate_year,
        d.rate_period as rate_period
    from deals as d
    left join header_fallback_line_counts as n
        on n.deal = d.deal
        and n.kind = d.kind
    where coalesce(n.n_lines, 0) = 0
      and abs(d.header_amount) > 0.005

    union all

    -- konsol#204 (row M2b): a partial-share 'full' deal's declared nci_fair_value, stated in the header's
    -- consideration_currency (the journal's nci_fair_value_rated), whatever currency its lines are in.
    -- Row M4 (PR #205 review): the journal's own condition, with no nci_fair_value > 0 test, so a deal that has
    -- not declared the figure yet is still checked for the rate (the J7 guard names the missing figure)
    select
        d.deal as deal,
        d.kind as kind,
        d.header_currency as from_currency,
        d.to_currency as to_currency,
        d.fiscal_year as fiscal_year,
        d.fiscal_period as fiscal_period,
        d.rate_year as rate_year,
        d.rate_period as rate_period
    from deals as d
    where d.kind = 'business_combination'
      and d.nci_measurement = 'full'
      and d.share_acquired_pct < 100.0
)

select distinct
    deal,
    kind,
    from_currency,
    to_currency,
    fiscal_year,
    fiscal_period
from needed
where from_currency != to_currency
  and (from_currency, to_currency, rate_year, rate_period) not in (
      select from_currency, to_currency, fiscal_year, fiscal_period from closing_rates
  )
order by deal, kind, from_currency
