-- PRD-14 Test: Equity income = net_income × ownership_pct × the period's governed Average rate
-- from the associate's accounting currency into the group's reporting currency (1.0 when they
-- are the same). The EQ_INCOME entry should match the formula.
-- 7 Nov 2026: the oracle translates, as the model does since the same day. It compared the entry
-- with net_income × ownership_pct in the associate's OWN currency, so it passed on a SEK associate
-- in a EUR group whose figure had never been translated (the defect it should have caught).
-- A Closing-type period reads its year's last Regular period's rate (rate_period_map(),
-- konsolidat#199 row D9), the same rule the model applies. join_use_nulls=0: an entry whose rate
-- key has no Average rate reads 0 here, so its expected value is 0 and the entry (never 0 itself,
-- the model drops |amount| <= 0.01) is flagged rather than excused.
-- Fixture: dbt_project/test_fixtures/assert_equity_method_journal_balances.sql.
with entries as (
    select
        ea.consolidation_group as consolidation_group,
        ea.data_area_id as data_area_id,
        ea.fiscal_year as fiscal_year,
        ea.fiscal_period as fiscal_period,
        ea.reporting_currency as reporting_currency,
        ea.amount as amount,
        if(rpm.mapped = 1, rpm.rate_year, toUInt16(ea.fiscal_year)) as rate_year,
        if(rpm.mapped = 1, rpm.rate_period, toUInt16(ea.fiscal_period)) as rate_period
    from {{ ref('gold_equity_method_associates') }} as ea
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = ea.fiscal_year
        and rpm.fiscal_period = ea.fiscal_period
    where ea.main_account = 'EQ_INCOME'
),

net_income as (
    select
        tb.data_area_id as data_area_id,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
        sum(tb.period_net_amount) as net_income
    from {{ ref('gold_trial_balance') }} as tb
    inner join {{ ref('silver_main_accounts') }} as ma
        on tb.main_account = ma.main_account_id
    where ma.is_pnl = 1
    group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period
),

average_rates as (
    select
        from_currency,
        to_currency,
        toUInt16(fiscal_year) as rate_year,
        toUInt16(fiscal_period) as rate_period,
        anyIf(toFloat64(rate), rate_type = 'Average') as average_rate
    from {{ source('epm_staging', 'group_exchange_rates') }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
)

select
    e.consolidation_group,
    e.data_area_id,
    e.fiscal_year,
    e.fiscal_period,
    e.amount as equity_income,
    ni.net_income,
    eo.effective_ownership_pct as ownership_pct,
    ec.accounting_currency,
    e.reporting_currency,
    if(ec.accounting_currency = e.reporting_currency, 1.0, r.average_rate) as average_rate,
    ni.net_income * eo.effective_ownership_pct
        * if(ec.accounting_currency = e.reporting_currency, 1.0, r.average_rate) as expected
from entries as e
inner join net_income as ni
    on e.data_area_id = ni.data_area_id
    and e.fiscal_year = ni.fiscal_year
    and e.fiscal_period = ni.fiscal_period
{# F2: the share is dated and per-group, so the oracle must be keyed the same
   way. It read the consolidation_groups seed on data_area_id alone, which held
   one percentage per entity for all time and ignored which group was
   consolidating it. #}
inner join {{ ref('gold_entity_ownership') }} as eo
    on e.consolidation_group = eo.consolidation_group
    and e.data_area_id = eo.data_area_id
    and e.fiscal_year = eo.fiscal_year
    and e.fiscal_period = eo.fiscal_period
inner join {{ ref('silver_entity_currencies') }} as ec
    on ec.data_area_id = e.data_area_id
left join average_rates as r
    on r.from_currency = ec.accounting_currency
    and r.to_currency = e.reporting_currency
    and r.rate_year = e.rate_year
    and r.rate_period = e.rate_period
where abs(e.amount - ni.net_income * eo.effective_ownership_pct
          * if(ec.accounting_currency = e.reporting_currency, 1.0, r.average_rate)) > 0.01
