-- konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X7: an entity that left a group by a bare
-- link end and re-enters it as a full subsidiary is carried at 100% of its balance, never at 100% plus what the
-- group carried before the exit. Design: konsol .claude/memory/active/tasks-p1-round2.md, T8.
-- Severity ERROR (the dbt default): a re-entered entity carried at 150% is a wrong consolidated balance sheet.
-- Fixture: test_fixtures/assert_reentry_carries_full_balance.gap_no_double_count.sql (the joint_operation_gap
-- shape: 50% proportional to 2025-12-31, a gap, then a 100% Business Combination from 2026-04-01).
--
-- An independent oracle: it never reads gold_ownership_exit_journal or repeats its rules. For every exit event
-- (G, E, P) of ownership_exits() (X1) and every later period Q in which gold_entity_ownership holds E in G as a
-- full subsidiary with a complete chain, each of E's non-equity balance-sheet accounts translated at the closing
-- rate (fx_method 'closing' or undeclared, the accounts #257 retranslates) must satisfy
--     sum over every layer of gold_fully_consolidated_tb for E, periods <= Q
--   = E's cumulative local balance to Q (gold_trial_balance_by_partner, every partner and dimension)
--     x the governed Closing rate of Q (rate_period_map(); 1.0 for a same-currency entity)
-- within materiality_floor(). Taken out of the FCTB sum, as assert_exit_derecognises_carried does: the
-- acquisition journal's investment, proceeds, costs and bargain_gain lines (the parent's investment and the
-- deal's settlement, not E's balances) and topside (gold_consolidation_adjustments).
-- Full only: a proportional re-entry carries translated x the share of each period, not one share of the
-- cumulative balance, so this formula does not hold for it after a share step.
{# a re-entry is live again at or after the exit's first period out (out_fiscal_*): between the exit period
   and it the entity can still be consolidated (a year-end boundary period, ownership_exits()) #}
with exits as (
    select consolidation_group, data_area_id, toUInt16(out_fiscal_year) as fiscal_year,
        toUInt16(out_fiscal_period) as fiscal_period
    {#- the events of ownership_exits(), materialised once (#335, X23): every fixture of this test builds it #}
    from {{ ref('gold_ownership_exits') }}
),

reentry_periods as (
    select distinct
        x.consolidation_group as consolidation_group,
        x.data_area_id as data_area_id,
        toUInt16(eo.fiscal_year) as check_year,
        toUInt16(eo.fiscal_period) as check_period
    from exits as x
    inner join {{ ref('gold_entity_ownership') }} as eo
        on eo.consolidation_group = x.consolidation_group and eo.data_area_id = x.data_area_id
    where eo.consolidation_method = 'full' and eo.has_complete_chain = 1
      and (toUInt16(eo.fiscal_year), toUInt16(eo.fiscal_period)) > (x.fiscal_year, x.fiscal_period)
),

closing_accounts as (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
    having max(is_balance_sheet) = 1 and max(is_equity) = 0 and any(fx_method) not in ('average', 'historical')
),

local_movements as (
    select tb.data_area_id as data_area_id, toUInt16(tb.fiscal_year) as fiscal_year,
        toUInt16(tb.fiscal_period) as fiscal_period, tb.main_account as main_account,
        toFloat64(tb.period_debit - tb.period_credit) as local_amount
    from {{ ref('gold_trial_balance_by_partner') }} as tb
    where tb.main_account in (select main_account_id from closing_accounts)
),

expected_local as (
    select r.consolidation_group as consolidation_group, r.data_area_id as data_area_id,
        r.check_year as check_year, r.check_period as check_period, m.main_account as main_account,
        sum(m.local_amount) as cumulative_local
    from reentry_periods as r
    inner join local_movements as m
        on m.data_area_id = r.data_area_id
    where (m.fiscal_year, m.fiscal_period) <= (r.check_year, r.check_period)
    group by r.consolidation_group, r.data_area_id, r.check_year, r.check_period, m.main_account
),

group_currency as (
    select consolidation_group, any(reporting_currency) as reporting_currency
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

closing_rates as (
    select from_currency, to_currency, toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period,
        anyIf(toFloat64(rate), rate_type = 'Closing') as closing_rate
    from {{ source('epm_staging', 'group_exchange_rates') }}
    {# konsol#348 S4-Q7 (a): the actuals Rate Set only, as the model reads #}
    where {{ actuals_rate_set_predicate() }}
    group by from_currency, to_currency, fiscal_year, fiscal_period
),

expected as (
    select
        e.consolidation_group as consolidation_group,
        e.data_area_id as data_area_id,
        e.check_year as check_year,
        e.check_period as check_period,
        e.main_account as main_account,
        e.cumulative_local
            * if(ec.accounting_currency = gc.reporting_currency, 1.0, cr.closing_rate) as expected_amount
    from expected_local as e
    inner join group_currency as gc
        on gc.consolidation_group = e.consolidation_group
    inner join {{ ref('silver_entity_currencies') }} as ec
        on ec.data_area_id = e.data_area_id
    left join {{ rate_period_map() }} as rpm
        on rpm.fiscal_year = e.check_year and rpm.fiscal_period = e.check_period
    left join closing_rates as cr
        on cr.from_currency = ec.accounting_currency and cr.to_currency = gc.reporting_currency
        and cr.fiscal_year = if(rpm.mapped = 1, rpm.rate_year, e.check_year)
        and cr.fiscal_period = if(rpm.mapped = 1, rpm.rate_period, e.check_period)
),

movements as (
    select consolidation_group, data_area_id, toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period, main_account, toFloat64(amount) as amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where data_area_id != ''

    union all

    select consolidation_group, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period), main_account,
        -toFloat64(adjustment_amount)
    from {{ ref('gold_business_combination_journal') }}
    where account_role in ('investment', 'proceeds', 'costs', 'bargain_gain')

    union all

    select consolidation_group, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period), main_account,
        -{{ cast_to_float64('net_amount') }}
    from {{ ref('gold_consolidation_adjustments') }}
),

actual as (
    select x.consolidation_group as consolidation_group, x.data_area_id as data_area_id,
        x.check_year as check_year, x.check_period as check_period, x.main_account as main_account,
        sum(m.amount) as carried_amount
    from expected as x
    inner join movements as m
        on m.consolidation_group = x.consolidation_group and m.data_area_id = x.data_area_id
        and m.main_account = x.main_account
    where (m.fiscal_year, m.fiscal_period) <= (x.check_year, x.check_period)
    group by x.consolidation_group, x.data_area_id, x.check_year, x.check_period, x.main_account
),

{# UNION + GROUP BY, not a LEFT JOIN (join_use_nulls = 0): an account the FCTB never carries reads 0 here #}
compared as (
    select consolidation_group, data_area_id, check_year, check_period, main_account,
        sum(exp_amt) as expected_amount, sum(act_amt) as carried_amount
    from (
        select consolidation_group, data_area_id, check_year, check_period, main_account,
            expected_amount as exp_amt, toFloat64(0) as act_amt
        from expected
        union all
        select consolidation_group, data_area_id, check_year, check_period, main_account,
            toFloat64(0), carried_amount
        from actual
    )
    group by consolidation_group, data_area_id, check_year, check_period, main_account
)

select 'carried after re-entry is not 100% at closing' as check_name, *,
    carried_amount - expected_amount as difference
from compared
where abs(carried_amount - expected_amount) > {{ materiality_floor() }}
