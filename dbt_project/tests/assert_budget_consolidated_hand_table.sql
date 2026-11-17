-- konsol#348 S4 (W4): the hand-computed translated amounts of the consolidated budget fixture
-- test_fixtures/assert_budget_consolidated_hand_table.sql, as literals. Two Budget Cycles of one
-- scenario declare DIFFERENT Rate Sets, each has two layers, and every (cycle, layer) holds the
-- same local rows (one EUR entity in a USD group, 100% owned, FY2026 P6 and P7: a closing-rate
-- cash account and an average-rate revenue account); the actuals set holds a different rate for
-- every key. The fixture's header shows the rates and the arithmetic. Each (cycle, layer) must
-- come out as that Cycle's set translates it alone, including the closing-rate retranslation of
-- the cash balance at P7 (konsolidat#257). A model that read the actuals set, read every set
-- without the Cycle's set on the rate key, or lost the layer or the cycle in a window partition
-- (so one layer's balance was retranslated against another's) gives a different number here,
-- and this test does not use the macros it checks. It is vacuous where the Cycle ZZ-CY-HAND-A
-- is not approved (every real site): no expected row is built. Flags one row per (cycle, layer,
-- account, period) that is missing, unexpected or off by more than 0.01.
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
