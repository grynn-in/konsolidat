-- konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X3: an ownership exit derecognises what the
-- group carried for the entity. Design: .claude/memory/active/tasks-p1-round2.md, T8 (konsol repo).
-- Severity ERROR (the dbt default): a bare link end that leaves the entity's balances in the group balance sheet
-- is a wrong consolidated figure, not a warning.
-- Fixture: test_fixtures/assert_exit_derecognises_carried.full_70pct.sql (a 70% full subsidiary with a business
-- combination and CTA, then a bare end).
--
-- For every exit event (G, E, P) of ownership_exits() (X1), and for every check period Q = P and each later period
-- gold_fully_consolidated_tb has for G, the cumulative amount to Q, summed over every layer of the fully
-- consolidated TB for data_area_id E, must be 0 (within materiality_floor()) on each of E's carried accounts:
--   - every non-equity balance-sheet account of E's layer 1 (gold_consolidated_trial_balance, is_balance_sheet = 1)
--     and of the acquisition journal's opening_balance lines; equity is the chart's silver_main_accounts.is_equity,
--     the classification gold_business_disposal_journal line (0) uses;
--   - 'CTA', and the root's goodwill_account, fair_value_adjustment_account and nci_account.
-- Two parts of the FCTB are not E's carried balances and are taken out of the sum, read from their own models:
--   - the acquisition journal's investment, proceeds, costs and bargain_gain lines: the parent's investment and the
--     deal's settlement, which the disposal journal does not derecognise either (its header, "Not here");
--   - topside (gold_consolidation_adjustments): the design does not reverse it on exit; a WARN names it (task X8).
-- Second check: every ownership_exit journal in the FCTB sums to 0 per (group, entity, period).
--
-- Every exit method is checked, not only 'full': a proportional or equity-method exit that leaves its balances is
-- flagged here until tasks X4 / X5 post its journal. Layer 2 (IC, data_area_id '') is outside E's rows.
with exits as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ownership_exits() }}
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
),

accounts as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account
    from carried_accounts
    where main_account != ''
),

check_periods as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period,
        fiscal_year as check_year, fiscal_period as check_period
    from exits

    union all

    select x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period,
        toUInt16(f.fiscal_year) as check_year, toUInt16(f.fiscal_period) as check_period
    from exits as x
    inner join (
        select distinct consolidation_group, fiscal_year, fiscal_period from {{ ref('gold_fully_consolidated_tb') }}
    ) as f
        on f.consolidation_group = x.consolidation_group
    where (toUInt16(f.fiscal_year), toUInt16(f.fiscal_period)) > (x.fiscal_year, x.fiscal_period)
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
