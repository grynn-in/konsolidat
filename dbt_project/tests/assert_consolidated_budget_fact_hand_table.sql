-- konsol#348 S6 WC1 (S6-Q7 a): gold_consolidated_budget_fact equals a table worked out by hand.
-- The view is gold_fully_consolidated_budget rolled to the group (consolidation_group in the entity slot,
-- data_area_id) per (fiscal_year, fiscal_period, main_account, scenario_id, cycle, layer), every
-- adjustment type summed into consolidated_amount, the shape of gold_consolidated_fact plus the three
-- budget grain columns. A budget-type scenario keeps its Cycle; a forecast-type scenario keeps its
-- DECLARED current round only (gold_forecast_current_round), so a second approved round is never added.
-- The fixture (test_fixtures/assert_consolidated_budget_fact_hand_table.sql) seeds two groups and two
-- layers of budget ZZ_PLAN_CBF and two rounds of forecast ZZ_FC_CBF (R2 declared); the expected rows are
-- below. A multiset diff (UNION ALL + GROUP BY with +1/-1, never count() over EXCEPT, konsolidat#361)
-- names every row that differs: net +1 expected and missing, -1 produced and not expected. Amounts
-- rounded to 4 places.
-- Vacuous where the fixture's scenarios are absent (every real site, and the full CI build): no expected
-- row is built and only ZZ_PLAN_CBF / ZZ_FC_CBF produced rows are read. They are present when a Budget
-- Cycle names one (the build-mode fixture, so a view that drops a whole scenario still fails) or when
-- the view holds one (the test-mode must_flag, which seeds the view's scratch table directly). Not a
-- `fixture_only_tests` test: that var is ON in ci_full_build.py's full builds (see
-- assert_latest_estimate_hand_table).
{{ config(severity='error') }}

with expected as (
    select
        data_area_id as k_group,
        fiscal_year as k_year,
        fiscal_period as k_period,
        main_account as k_account,
        scenario_id as k_scenario,
        cycle as k_cycle,
        layer as k_layer,
        round(amount, 4) as k_amount,
        1 as sign
    from values(
        'data_area_id String, fiscal_year UInt16, fiscal_period UInt8, main_account String, scenario_id String, cycle String, layer String, amount Float64',
        -- ZZG1, budget, base: ZZE1 -100 + ZZE2 -50 on ZZ4000; ZZE1 cta 3 and nci_attribution -1 on CTA;
        -- the unbalanced plug on UNBALANCED
        ('ZZG1', 2026, 1, 'ZZ4000', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', -150),
        ('ZZG1', 2026, 1, 'CTA', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 2),
        ('ZZG1', 2026, 1, 'UNBALANCED', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 150),
        -- ZZG1, budget, challenge: its own layer, never added to base
        ('ZZG1', 2026, 1, 'ZZ4000', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'challenge', -10),
        -- ZZG2 holds ZZE1 proportionally (60%): its own group, never added to ZZG1
        ('ZZG2', 2026, 1, 'ZZ4000', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', -60),
        -- forecast: R2 is declared; R1 (-200) is absent
        ('ZZG1', 2026, 1, 'ZZ4000', 'ZZ_FC_CBF', 'ZZ-CBF-R2', 'base', -220)
    )
    where 'ZZ_PLAN_CBF' in (select scenario_id from {{ source('epm_staging', 'budget_cycles') }})
       or 'ZZ_PLAN_CBF' in (select scenario_id from {{ ref('gold_consolidated_budget_fact') }})
),

produced as (
    select
        data_area_id as k_group,
        toUInt16(fiscal_year) as k_year,
        toUInt8(fiscal_period) as k_period,
        toString(main_account) as k_account,
        scenario_id as k_scenario,
        cycle as k_cycle,
        layer as k_layer,
        round(sum(toFloat64(consolidated_amount)), 4) as k_amount,
        -1 as sign
    from {{ ref('gold_consolidated_budget_fact') }}
    where scenario_id in ('ZZ_PLAN_CBF', 'ZZ_FC_CBF')
    group by data_area_id, fiscal_year, fiscal_period, main_account, scenario_id, cycle, layer
)

select k_group, k_year, k_period, k_account, k_scenario, k_cycle, k_layer, k_amount, sum(sign) as net
from (
    select * from expected
    union all
    select * from produced
)
group by k_group, k_year, k_period, k_account, k_scenario, k_cycle, k_layer, k_amount
having net != 0
