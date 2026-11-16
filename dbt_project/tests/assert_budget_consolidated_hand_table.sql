-- konsol#348 S4 (W4): the hand-computed translated amounts of
-- test_fixtures/assert_budget_consolidated_hand_table.sql, as literals. Two Budget Cycles of one
-- scenario on DIFFERENT Rate Sets (ZZ-CY-HAND-A on ZZB1, ZZ-CY-HAND-B on ZZB2), each with two
-- layers (base, challenge) holding the same local rows: one EUR entity ZZE1 in a USD group ZZG,
-- 100% owned, FY2026 P6 and P7; ZZ1000 cash (balance sheet, closing) and ZZ4000 revenue (P&L,
-- average). The actuals set ZZACT holds a different rate (1.0) for every key.
--
--   set    P6 closing / average   P7 closing / average
--   ZZB1   1.10 / 1.05            1.20 / 1.15
--   ZZB2   2.00 / 1.90            2.20 / 2.10
--   ZZACT  1.00 / 1.00            1.00 / 1.00      (never read for a budget)
--
--   local, every (cycle, layer):  P6 ZZ1000 +100, ZZ4000 -100;  P7 ZZ1000 +50, ZZ4000 -50
--
-- translated = local x rate + retranslation (konsolidat#257: a closing-rate balance sheet key is
-- revalued at each period's closing rate: cum_local(prev) x (C(p) - C(prev))), per (cycle, layer):
--
--   cycle A: P6 ZZ1000 100 x 1.10 = 110;  P6 ZZ4000 -100 x 1.05 = -105
--            P7 ZZ1000 50 x 1.20 + 100 x (1.20 - 1.10) = 70;  P7 ZZ4000 -50 x 1.15 = -57.5
--   cycle B: P6 ZZ1000 100 x 2.00 = 200;  P6 ZZ4000 -100 x 1.90 = -190
--            P7 ZZ1000 50 x 2.20 + 100 x (2.20 - 2.00) = 130;  P7 ZZ4000 -50 x 2.10 = -105
--
-- What each wrong reading would give instead: the actuals set, 100 / -100 / 50 / -50; both sets
-- read without the Cycle's set on the rate key, two Closing rates per key, so NULL and a refused
-- build; the two layers telescoped in the retranslation window (cum_local 200 at P7), 80 and 150
-- for ZZ1000 P7; the two cycles telescoped, a closing-rate lag across sets. The test is vacuous
-- where the Cycle ZZ-CY-HAND-A is not approved (every real site): no expected row is built.
-- Flags one row per (cycle, layer, account, period) that is missing, unexpected or off by more
-- than 0.01.
{{ config(severity='error') }}

with expected as (
    select * from (
        select 'ZZ-CY-HAND-A' as cycle, 'base' as layer, 'ZZ1000' as main_account, 6 as fiscal_period, toFloat64(110) as amount
        union all select 'ZZ-CY-HAND-A', 'base', 'ZZ4000', 6, -105
        union all select 'ZZ-CY-HAND-A', 'base', 'ZZ1000', 7, 70
        union all select 'ZZ-CY-HAND-A', 'base', 'ZZ4000', 7, -57.5
        union all select 'ZZ-CY-HAND-A', 'challenge', 'ZZ1000', 6, 110
        union all select 'ZZ-CY-HAND-A', 'challenge', 'ZZ4000', 6, -105
        union all select 'ZZ-CY-HAND-A', 'challenge', 'ZZ1000', 7, 70
        union all select 'ZZ-CY-HAND-A', 'challenge', 'ZZ4000', 7, -57.5
        union all select 'ZZ-CY-HAND-B', 'base', 'ZZ1000', 6, 200
        union all select 'ZZ-CY-HAND-B', 'base', 'ZZ4000', 6, -190
        union all select 'ZZ-CY-HAND-B', 'base', 'ZZ1000', 7, 130
        union all select 'ZZ-CY-HAND-B', 'base', 'ZZ4000', 7, -105
        union all select 'ZZ-CY-HAND-B', 'challenge', 'ZZ1000', 6, 200
        union all select 'ZZ-CY-HAND-B', 'challenge', 'ZZ4000', 6, -190
        union all select 'ZZ-CY-HAND-B', 'challenge', 'ZZ1000', 7, 130
        union all select 'ZZ-CY-HAND-B', 'challenge', 'ZZ4000', 7, -105
    )
    where 'ZZ-CY-HAND-A' in (select name from {{ source('epm_staging', 'budget_cycles') }})
),

combined as (
    select cycle, layer, main_account, toUInt8(fiscal_period) as fiscal_period,
           amount as expected_amount, toFloat64(0) as actual_amount,
           toUInt8(1) as is_expected, toUInt8(0) as is_actual
    from expected

    union all

    select cycle, layer, toString(main_account) as main_account, toUInt8(fiscal_period) as fiscal_period,
           toFloat64(0) as expected_amount, toFloat64(translated_amount) as actual_amount,
           toUInt8(0) as is_expected, toUInt8(1) as is_actual
    from {{ ref('gold_consolidated_budget_tb') }}
    where cycle in ('ZZ-CY-HAND-A', 'ZZ-CY-HAND-B')
      and scenario_id = 'ZZ_PLAN_2026'
      and consolidation_group = 'ZZG'
      and data_area_id = 'ZZE1'
      and fiscal_year = 2026
      and 'ZZ-CY-HAND-A' in (select name from {{ source('epm_staging', 'budget_cycles') }})
),

per_row as (
    select cycle, layer, main_account, fiscal_period,
           sum(expected_amount) as expected_amount,
           sum(actual_amount) as actual_amount,
           max(is_expected) as is_expected,
           max(is_actual) as is_actual
    from combined
    group by cycle, layer, main_account, fiscal_period
)

select cycle, layer, main_account, fiscal_period, expected_amount, actual_amount, is_expected, is_actual
from per_row
where is_expected != is_actual
   or abs(expected_amount - actual_amount) > 0.01
order by cycle, layer, main_account, fiscal_period
