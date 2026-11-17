-- konsol#348 S4 (S4-Q8 b; W6): the two plug layers of gold_fully_consolidated_budget, as hand
-- literals, over two fixtures. For each (group, scenario, cycle, layer, entity, period), with
-- L = sum of the local amounts, G = sum of group_amount and C = the period's Closing rate in the
-- Cycle's Rate Set (entity currency -> group currency):
--     unbalanced = -L x C          the budget's own local imbalance, translated at closing;
--     cta        = -(G - L x C)    the translation difference only.
-- Before S4-Q8 cta was the whole residual -G, which for a budget that is not double-entry (a P&L-only
-- budget: every Budget Annual Input is one-sided) carried the budget's own gap as if it were a
-- currency effect. Both rows are emitted for every consolidation, 0 when there is nothing to plug.
--
-- Fixture 1, test_fixtures/assert_budget_consolidated_balances.sql (Cycle ZZ-CY-BAL, EUR entity in
-- a USD group, 80% owned, double-entry rows, L = 0): unbalanced 0 everywhere, and cta exactly what
-- the whole residual gave before: base P6 -5, base P7 -12.5 (the P7 cash retranslation is in G),
-- challenge P6 -2.
-- Fixture 2, test_fixtures/assert_budget_consolidated_balances.pnl_only.sql (Cycle ZZ-CY-PNL, the
-- same entity 100% owned, a P&L-ONLY budget: revenue and an expense, nothing on the balance sheet):
--   P6: revenue -100, expense +60, L = -40; average 1.05, closing 1.10.
--       G = -40 x 1.05 = -42; L x C = -44; unbalanced = +44; cta = -(-42 + 44) = -2
--       (the hand translation difference: -40 x (1.05 - 1.10) = +2, plugged by -2).
--   P7: revenue -50, expense +30, L = -20; average 1.15, closing 1.20.
--       G = -23; L x C = -24; unbalanced = +24; cta = -1.
-- Red before S4-Q8: no 'unbalanced' row exists, and the P&L-only cta is the whole residual (+42,
-- +23 instead of -2, -1).
-- Each fixture's block is vacuous where its Cycle is not approved (every real site). Flags one
-- row per (cycle, layer, period, adjustment_type) missing, unexpected or off by more than 0.01.
{{ config(severity='error') }}

with expected as (
    select * from (
        select 'ZZ-CY-BAL' as cycle, 'base' as layer, 6 as fiscal_period, 'unbalanced' as adjustment_type, toFloat64(0) as amount
        union all select 'ZZ-CY-BAL', 'base', 6, 'cta', -5
        union all select 'ZZ-CY-BAL', 'base', 7, 'unbalanced', 0
        union all select 'ZZ-CY-BAL', 'base', 7, 'cta', -12.5
        union all select 'ZZ-CY-BAL', 'challenge', 6, 'unbalanced', 0
        union all select 'ZZ-CY-BAL', 'challenge', 6, 'cta', -2
    )
    where 'ZZ-CY-BAL' in (select name from {{ source('epm_staging', 'budget_cycles') }})

    union all

    select * from (
        select 'ZZ-CY-PNL' as cycle, 'base' as layer, 6 as fiscal_period, 'unbalanced' as adjustment_type, toFloat64(44) as amount
        union all select 'ZZ-CY-PNL', 'base', 6, 'cta', -2
        union all select 'ZZ-CY-PNL', 'base', 7, 'unbalanced', 24
        union all select 'ZZ-CY-PNL', 'base', 7, 'cta', -1
    )
    where 'ZZ-CY-PNL' in (select name from {{ source('epm_staging', 'budget_cycles') }})
),

combined as (
    select cycle, layer, toUInt8(fiscal_period) as fiscal_period, adjustment_type,
           amount as expected_amount, toFloat64(0) as actual_amount,
           toUInt8(1) as is_expected, toUInt8(0) as is_actual
    from expected

    union all

    select cycle, layer, toUInt8(fiscal_period) as fiscal_period, toString(adjustment_type) as adjustment_type,
           toFloat64(0) as expected_amount, toFloat64(amount) as actual_amount,
           toUInt8(0) as is_expected, toUInt8(1) as is_actual
    from {{ ref('gold_fully_consolidated_budget') }}
    where cycle in ('ZZ-CY-BAL', 'ZZ-CY-PNL')
      and cycle in (select name from {{ source('epm_staging', 'budget_cycles') }})
      and scenario_id = 'ZZ_PLAN_2026'
      and consolidation_group = 'ZZG'
      and data_area_id = 'ZZE1'
      and fiscal_year = 2026
      and adjustment_type in ('cta', 'unbalanced')
),

per_row as (
    select cycle, layer, fiscal_period, adjustment_type,
           sum(expected_amount) as expected_amount,
           sum(actual_amount) as actual_amount,
           max(is_expected) as is_expected,
           max(is_actual) as is_actual
    from combined
    group by cycle, layer, fiscal_period, adjustment_type
)

select cycle, layer, fiscal_period, adjustment_type, expected_amount, actual_amount, is_expected, is_actual
from per_row
where is_expected != is_actual
   or abs(expected_amount - actual_amount) > 0.01
order by cycle, layer, fiscal_period, adjustment_type
