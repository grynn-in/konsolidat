-- konsol#348 S2 (R10, Q15-c): the hand-computed movements of test_fixtures/budget_raw_ytd.sql, as
-- literals. assert_budget_ytd_reconciles is built from the macro it checks (movement_spine), so it
-- cannot catch a mistake in that rule; this test does not use it. Cycle ZZ-CY-HAND (ZZ data) is stated
-- YTD per account and layer (the fixture's header holds the table); the manual spread of ZZ_PLAN_2026 /
-- ZZE1 / FY2026 must hold exactly these movements, summed over budget dimensions.
-- It is vacuous where the cycle ZZ-CY-HAND has no lines (every real site): no expected row is built.
-- Flags one row per (layer, account, period) that is missing, unexpected or off by more than 0.01.
{{ config(severity='error') }}

with expected as (
    select * from (
        select 'base' as layer, 'ZZ4000' as main_account, 1 as fiscal_period, toFloat64(-100) as amount
        union all select 'base', 'ZZ4000', 2, -150
        union all select 'base', 'ZZ4000', 3, -200
        union all select 'base', 'ZZ6000', 1, 80
        union all select 'base', 'ZZ6000', 2, 120
        union all select 'base', 'ZZ6000', 3, -200
        union all select 'challenge', 'ZZ4000', 1, 0
        union all select 'challenge', 'ZZ4000', 2, -50
        union all select 'challenge', 'ZZ4000', 3, 0
    )
    where 'ZZ-CY-HAND' in (select cycle from {{ source('budget_raw', 'budget_entries') }})
),

combined as (
    select layer, main_account, toUInt8(fiscal_period) as fiscal_period,
           amount as expected_amount, toFloat64(0) as actual_amount,
           toUInt8(1) as is_expected, toUInt8(0) as is_actual
    from expected

    union all

    select layer, toString(main_account) as main_account, toUInt8(fiscal_period) as fiscal_period,
           toFloat64(0) as expected_amount, toFloat64(period_amount) as actual_amount,
           toUInt8(0) as is_expected, toUInt8(1) as is_actual
    from {{ ref('gold_spread_budget') }}
    where spread_profile_id = 'manual'
      and scenario_id = 'ZZ_PLAN_2026'
      and data_area_id = 'ZZE1'
      and fiscal_year = 2026
      and 'ZZ-CY-HAND' in (select cycle from {{ source('budget_raw', 'budget_entries') }})
),

per_row as (
    select layer, main_account, fiscal_period,
           sum(expected_amount) as expected_amount,
           sum(actual_amount) as actual_amount,
           max(is_expected) as is_expected,
           max(is_actual) as is_actual
    from combined
    group by layer, main_account, fiscal_period
)

select layer, main_account, fiscal_period, expected_amount, actual_amount, is_expected, is_actual
from per_row
where is_expected != is_actual
   or abs(expected_amount - actual_amount) > 0.01
