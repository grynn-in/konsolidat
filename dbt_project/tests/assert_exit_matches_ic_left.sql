-- konsolidat#335, option A (decided 14 Nov 2026 by Deepak Pai), task X6: an ownership exit and the intercompany
-- 'left' row agree. Design: .claude/memory/active/tasks-p1-round2.md, T8 (konsol repo).
-- Severity ERROR: an exit that is not paired with the IC reconciliation either leaves an intercompany balance
-- eliminated against an entity that is no longer in the group, or reverses it twice.
-- Fixture: test_fixtures/assert_exit_matches_ic_left.receivable.sql.
--
-- For every exit event (G, E, P) of ownership_exits() and every intercompany pair that had E on one side and was
-- live before P (gold_ic_reconciliation rows for the pair in an earlier period that are not themselves 'left' rows):
--   left_missing          the reconciliation has no 'left' row for the pair at all;
--   left_in_other_period  it has a 'left' row, but not in P (the exit macro reads every declared period, the IC spine
--                         the periods present in gold_trial_balance, so an exit in an empty period can diverge);
--   double_reversal       in P, over every FCTB layer, E's IC account is not 0 (the exit journal reverses E's
--                         layer-1 balance once, and the layer-2 elimination is reversed by the 'left' row, so
--                         E's own rows net to 0), or the pair's elimination legs do not net to 0 on either
--                         account to P (the counterparty is then not left carrying its full, now external, balance).
-- The exit journal never reads layer 2 (design), so a non-zero E total means it reversed the IC layer too.
with exits as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ownership_exits() }}
),

{# each pair from the side of both of its entities: E, E's account, the counterparty and its account #}
sides as (
    select consolidation_group, fiscal_year, fiscal_period, pair_event,
        entity_a as side_entity, account_a as side_account, entity_b as other_entity, account_b as other_account
    from {{ ref('gold_ic_reconciliation') }}
    union all
    select consolidation_group, fiscal_year, fiscal_period, pair_event,
        entity_b, account_b, entity_a, account_a
    from {{ ref('gold_ic_reconciliation') }}
),

live_pairs as (
    select x.consolidation_group as consolidation_group, x.data_area_id as exited_entity,
        x.fiscal_year as exit_year, x.fiscal_period as exit_period,
        s.side_account as side_account, s.other_entity as other_entity, s.other_account as other_account
    from exits as x
    inner join sides as s
        on s.consolidation_group = x.consolidation_group and s.side_entity = x.data_area_id
    where (s.fiscal_year, s.fiscal_period) < (x.fiscal_year, x.fiscal_period) and s.pair_event != 'left'
    group by x.consolidation_group, x.data_area_id, x.fiscal_year, x.fiscal_period,
        s.side_account, s.other_entity, s.other_account
),

left_rows as (
    select consolidation_group, side_entity, side_account, other_entity, other_account,
        toUInt16(fiscal_year) as left_year, toUInt16(fiscal_period) as left_period
    from sides
    where pair_event = 'left'
),

{# per pair: how many 'left' rows, and how many of them in P #}
left_counts as (
    select p.consolidation_group as consolidation_group, p.exited_entity as exited_entity,
        p.exit_year as exit_year, p.exit_period as exit_period, p.side_account as side_account,
        p.other_entity as other_entity, p.other_account as other_account,
        countIf(l.left_year > 0) as n_left,
        countIf(l.left_year = p.exit_year and l.left_period = p.exit_period) as n_left_in_p
    from live_pairs as p
    left join left_rows as l
        on l.consolidation_group = p.consolidation_group and l.side_entity = p.exited_entity
        and l.side_account = p.side_account and l.other_entity = p.other_entity and l.other_account = p.other_account
    group by p.consolidation_group, p.exited_entity, p.exit_year, p.exit_period, p.side_account,
        p.other_entity, p.other_account
),

{# E's own rows on its IC account, every layer, to P #}
exited_totals as (
    select p.consolidation_group as consolidation_group, p.exited_entity as exited_entity,
        p.exit_year as exit_year, p.exit_period as exit_period, p.side_account as side_account,
        p.other_entity as other_entity, p.other_account as other_account,
        sum(toFloat64(f.amount)) as exited_total
    from live_pairs as p
    inner join {{ ref('gold_fully_consolidated_tb') }} as f
        on f.consolidation_group = p.consolidation_group and f.data_area_id = p.exited_entity
        and f.main_account = p.side_account
    where (toUInt16(f.fiscal_year), toUInt16(f.fiscal_period)) <= (p.exit_year, p.exit_period)
    group by p.consolidation_group, p.exited_entity, p.exit_year, p.exit_period, p.side_account,
        p.other_entity, p.other_account
),

{# the pair's elimination legs, net per account, to P: 0 on both once the pair has left #}
elimination_totals as (
    select p.consolidation_group as consolidation_group, p.exited_entity as exited_entity,
        p.exit_year as exit_year, p.exit_period as exit_period, p.side_account as side_account,
        p.other_entity as other_entity, p.other_account as other_account,
        sum(if(e.debit_account = p.side_account, toFloat64(e.debit_elimination), 0)
            + if(e.credit_account = p.side_account, toFloat64(e.credit_elimination), 0)) as side_legs,
        sum(if(e.debit_account = p.other_account, toFloat64(e.debit_elimination), 0)
            + if(e.credit_account = p.other_account, toFloat64(e.credit_elimination), 0)) as other_legs
    from live_pairs as p
    inner join {{ ref('gold_ic_eliminations') }} as e
        on e.consolidation_group = p.consolidation_group
    {# a join condition across both tables with OR is refused: filter the pair here #}
    where e.elimination_kind = 'matched'
      and ((e.entity_a = p.exited_entity and e.account_a = p.side_account
            and e.entity_b = p.other_entity and e.account_b = p.other_account)
        or (e.entity_b = p.exited_entity and e.account_b = p.side_account
            and e.entity_a = p.other_entity and e.account_a = p.other_account))
      and (toUInt16(e.fiscal_year), toUInt16(e.fiscal_period)) <= (p.exit_year, p.exit_period)
    group by p.consolidation_group, p.exited_entity, p.exit_year, p.exit_period, p.side_account,
        p.other_entity, p.other_account
)

select
    c.consolidation_group as consolidation_group,
    c.exited_entity as exited_entity,
    c.exit_year as exit_year,
    c.exit_period as exit_period,
    c.side_account as side_account,
    c.other_entity as other_entity,
    c.other_account as other_account,
    multiIf(
        c.n_left = 0, 'left_missing',
        c.n_left_in_p = 0, 'left_in_other_period',
        abs(t.exited_total) > {{ materiality_floor() }}
            or abs(el.side_legs) > {{ materiality_floor() }}
            or abs(el.other_legs) > {{ materiality_floor() }}, 'double_reversal',
        ''
    ) as reason,
    t.exited_total as exited_total,
    el.side_legs as side_legs,
    el.other_legs as other_legs
from left_counts as c
{# join_use_nulls=0: a pair with no rows below reads 0, and a 0 passes the checks above #}
left join exited_totals as t
    on t.consolidation_group = c.consolidation_group and t.exited_entity = c.exited_entity
    and t.exit_year = c.exit_year and t.exit_period = c.exit_period and t.side_account = c.side_account
    and t.other_entity = c.other_entity and t.other_account = c.other_account
left join elimination_totals as el
    on el.consolidation_group = c.consolidation_group and el.exited_entity = c.exited_entity
    and el.exit_year = c.exit_year and el.exit_period = c.exit_period and el.side_account = c.side_account
    and el.other_entity = c.other_entity and el.other_account = c.other_account
where reason != ''
