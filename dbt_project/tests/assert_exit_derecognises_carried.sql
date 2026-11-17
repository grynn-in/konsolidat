-- konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X3: an ownership exit derecognises what the
-- group carried for the entity. Design: .claude/memory/active/tasks-p1-round2.md, T8 (konsol repo).
-- Severity ERROR (the dbt default): a bare link end that leaves the entity's balances in the group balance sheet
-- is a wrong consolidated figure, not a warning.
-- Fixture: test_fixtures/assert_exit_derecognises_carried.full_70pct.sql (a 70% full subsidiary with a business
-- combination and CTA, then a bare end).
--
-- For every exit event (G, E, P) of ownership_exits() (X1), and for every check period Q = A and each later period
-- gold_fully_consolidated_tb has for G, the cumulative amount to Q, summed over every layer of the fully
-- consolidated TB for data_area_id E, must be 0 (within materiality_floor()) on each of E's carried accounts:
--   - every non-equity balance-sheet account of E's layer 1 (gold_consolidated_trial_balance, is_balance_sheet = 1)
--     and of the acquisition journal's opening_balance lines; equity is the chart's silver_main_accounts.is_equity,
--     the classification gold_business_disposal_journal line (0) uses;
--   - 'CTA', and the root's goodwill_account, fair_value_adjustment_account and nci_account;
--   - for an equity-method exit (task X5), EQ_INVEST: a pseudo-account outside the chart, so no list above holds it.
-- Two parts of the FCTB are not E's carried balances and are taken out of the sum, read from their own models:
--   - the acquisition journal's investment, proceeds, costs and bargain_gain lines: the parent's investment and the
--     deal's settlement, which the disposal journal does not derecognise either (its header, "Not here");
--   - topside (gold_consolidation_adjustments): the design does not reverse it on exit; a WARN names it (task X8).
-- A, the anchor (#358 review F1), is read here from the fiscal calendar, not from the macro: the Regular period
-- whose declared span holds the exit's end_date (lowest tuple), the period the group last held E in and so the
-- period by whose end control was lost (IFRS 10.25), as a full disposal's period holds its disposal_date. With no
-- end_date (a method change) or no Regular period holding it, A is the macro's exit period P.
-- Check periods stop at a re-entry (task X7): from the first later period in which E is live in G again, the group
-- carries E anew; assert_reentry_carries_full_balance checks that it carries 100%, not 100% plus the pre-exit share.
-- Second check: every ownership_exit journal in the FCTB sums to 0 per (group, entity, period).
--
-- Every exit method is checked, not only 'full': a proportional or equity-method exit that leaves its balances is
-- flagged here (fixtures .proportional_step, .equity). Layer 2 (IC, data_area_id '') is outside E's rows.
with exits as (
    select consolidation_group, data_area_id, toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period, method_before, end_date
    {#- the events of ownership_exits(), materialised once (#335, X23): every fixture of this test builds it #}
    from {{ ref('gold_ownership_exits') }}
),

{# the Regular period holding end_date, read from the calendar (header: A) #}
holding as (
    select x.consolidation_group as consolidation_group, x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year, x.fiscal_period as fiscal_period,
        count() as n_holding,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as holding_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as holding_period
    from exits as x
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where x.end_date is not null
      and fp.period_type = 'Regular' and fp.start_date <= x.end_date and fp.end_date >= x.end_date
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period
),

{# join_use_nulls = 0: no holding period reads n_holding = 0, and the anchor is the macro's period #}
anchors as (
    select x.consolidation_group as consolidation_group, x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year, x.fiscal_period as fiscal_period,
        if(h.n_holding = 0, x.fiscal_year, h.holding_year) as anchor_year,
        if(h.n_holding = 0, x.fiscal_period, h.holding_period) as anchor_period
    from exits as x
    left join holding as h
        on h.consolidation_group = x.consolidation_group and h.data_area_id = x.data_area_id
        and h.fiscal_year = x.fiscal_year and h.fiscal_period = x.fiscal_period
),

root as (
    select
        consolidation_group,
        any(goodwill_account) as goodwill_account,
        any(fair_value_adjustment_account) as fair_value_adjustment_account,
        any(nci_account) as nci_account
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
),

{# ARRAY JOIN on the root alone: ClickHouse reads ARRAY JOIN before JOIN and cannot fan out over joined columns #}
root_accounts as (
    select consolidation_group, acct as main_account
    from root
    array join ['CTA', goodwill_account, fair_value_adjustment_account, nci_account] as acct
),

equity_accounts as (
    select main_account_id, max(is_equity) as is_equity
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

layer1_accounts as (
    select distinct ctb.consolidation_group as consolidation_group, ctb.data_area_id as data_area_id,
        ctb.main_account as main_account
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    left join equity_accounts as ea
        on ea.main_account_id = ctb.main_account
    where ctb.is_balance_sheet = 1 and coalesce(ea.is_equity, 0) = 0
),

opening_accounts as (
    select distinct j.consolidation_group as consolidation_group, j.data_area_id as data_area_id,
        j.main_account as main_account
    from {{ ref('gold_business_combination_journal') }} as j
    left join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = j.main_account
    left join equity_accounts as ea
        on ea.main_account_id = j.main_account
    where j.account_role = 'opening_balance' and ma.is_balance_sheet = 1 and coalesce(ea.is_equity, 0) = 0
),

carried_accounts as (
    select x.consolidation_group as consolidation_group, x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year, x.fiscal_period as fiscal_period, a.main_account as main_account
    from exits as x
    inner join (select * from layer1_accounts union all select * from opening_accounts) as a
        on a.consolidation_group = x.consolidation_group and a.data_area_id = x.data_area_id

    union all

    select x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period, ra.main_account
    from exits as x
    inner join root_accounts as ra
        on ra.consolidation_group = x.consolidation_group
    union all

    {# task X5: an equity-method associate carries the reserved pseudo-account EQ_INVEST (the share of its results,
       gold_equity_method_associates), which is outside the chart: neither list above can see it #}
    select x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period, 'EQ_INVEST'
    from exits as x
    where x.method_before = 'equity'
),

accounts as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account
    from carried_accounts
    where main_account != ''
),

{# task X7: a re-entry ends the check. From the first later period in which gold_entity_ownership holds E live in G
   again (full, proportional or equity, complete chain) the group carries E's balances anew, and
   assert_reentry_carries_full_balance checks them instead. 0 = never re-entered (join_use_nulls = 0). #}
reentries as (
    select x.consolidation_group as consolidation_group, x.data_area_id as data_area_id,
        x.fiscal_year as fiscal_year, x.fiscal_period as fiscal_period,
        min(toUInt32(eo.fiscal_year) * 1000 + eo.fiscal_period) as reentry_ord
    from exits as x
    inner join {{ ref('gold_entity_ownership') }} as eo
        on eo.consolidation_group = x.consolidation_group and eo.data_area_id = x.data_area_id
    where eo.consolidation_method in ('full', 'proportional', 'equity') and eo.has_complete_chain = 1
      and (toUInt16(eo.fiscal_year), toUInt16(eo.fiscal_period)) > (x.fiscal_year, x.fiscal_period)
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period
),

check_periods_all as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
        anchor_year as check_year, anchor_period as check_period
    from anchors

    union all

    select x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period,
        toUInt16(f.fiscal_year) as check_year, toUInt16(f.fiscal_period) as check_period
    from anchors as x
    inner join (
        select distinct consolidation_group, fiscal_year, fiscal_period from {{ ref('gold_fully_consolidated_tb') }}
    ) as f
        on f.consolidation_group = x.consolidation_group
    where (toUInt16(f.fiscal_year), toUInt16(f.fiscal_period)) > (x.anchor_year, x.anchor_period)
),

check_periods as (
    select c.consolidation_group as consolidation_group, c.data_area_id as data_area_id,
        c.fiscal_year as fiscal_year, c.fiscal_period as fiscal_period,
        c.check_year as check_year, c.check_period as check_period
    from check_periods_all as c
    left join reentries as r
        on r.consolidation_group = c.consolidation_group and r.data_area_id = c.data_area_id
        and r.fiscal_year = c.fiscal_year and r.fiscal_period = c.fiscal_period
    where r.reentry_ord = 0 or toUInt32(c.check_year) * 1000 + c.check_period < r.reentry_ord
),

{# every signed amount on E's rows: the FCTB in full, less the two parts named in the header #}
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

carried as (
    select
        a.consolidation_group as consolidation_group,
        a.data_area_id as exited_entity,
        a.fiscal_year as exit_year,
        a.fiscal_period as exit_period,
        c.check_year as check_year,
        c.check_period as check_period,
        a.main_account as main_account,
        sum(m.amount) as cumulative_amount
    from accounts as a
    inner join check_periods as c
        on c.consolidation_group = a.consolidation_group and c.data_area_id = a.data_area_id
        and c.fiscal_year = a.fiscal_year and c.fiscal_period = a.fiscal_period
    inner join movements as m
        on m.consolidation_group = a.consolidation_group and m.data_area_id = a.data_area_id
        and m.main_account = a.main_account
    where (m.fiscal_year, m.fiscal_period) <= (c.check_year, c.check_period)
    group by a.consolidation_group, a.data_area_id, a.fiscal_year, a.fiscal_period, c.check_year, c.check_period,
        a.main_account
),

unbalanced_journals as (
    select
        consolidation_group,
        data_area_id as exited_entity,
        toUInt16(fiscal_year) as exit_year,
        toUInt16(fiscal_period) as exit_period,
        toUInt16(fiscal_year) as check_year,
        toUInt16(fiscal_period) as check_period,
        '(journal)' as main_account,
        sum(toFloat64(amount)) as cumulative_amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type = 'ownership_exit'
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
)

select 'carried after exit' as check_name, *
from carried
where abs(cumulative_amount) > {{ materiality_floor() }}

union all

select 'exit journal does not balance' as check_name, *
from unbalanced_journals
where abs(cumulative_amount) > {{ materiality_floor() }}
