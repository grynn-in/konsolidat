-- konsol#348 S4 (S4b live test, must fix): every local_amount of gold_consolidated_budget_tb equals
-- its budget fact row's period_amount ROUNDED to the actuals' Decimal scale (amount_scale(), 4),
-- never truncated. period_amount is a Float64 (gold_spread_budget: annual_amount x period_weight,
-- or a manual line's net), and toDecimal128(Float64, 4) truncates the binary double toward zero
-- (konsolidat#191): 1234567.89 becomes 1234567.8899, and an annual 1000.01 spread evenly,
-- 83.33416666..., becomes 83.3341 where rounding gives 83.3342. 14 of 16 live ZZ budget rows were
-- off by 0.0001 on the first live build. cast_to_decimal128() (macros/db_adapter.sql) rounds to
-- the scale, goes through the shortest exact text and parses that; the model must use it, and
-- this test recomputes the expected value with the same macro from the fact, so the two can only
-- agree when the model rounds. Exact Decimal comparison, no tolerance.
--
-- Join: the fact's grain (scenario, cycle, layer, entity, year, period, account, budget dims) to
-- the consolidated rows, which fan out once per ancestor group; every fan-out row is compared.
-- Filler rows the core adds for a retranslation (is_filler, local_amount 0) have no fact row and
-- are not judged; a fact row whose Cycle is not approved has no consolidated row and is not judged
-- (assert_budget_cycle_is_approved names it).
-- Fixture: test_fixtures/assert_budget_consolidated_local_amount_exact.sql (1234567.89 and the
-- 1000.01 / 12 spread; red on toDecimal128(Float64), green on cast_to_decimal128).
{{ config(severity='error') }}

select
    b.consolidation_group as consolidation_group,
    b.scenario_id as scenario_id,
    b.cycle as cycle,
    b.layer as layer,
    b.data_area_id as data_area_id,
    b.fiscal_year as fiscal_year,
    b.fiscal_period as fiscal_period,
    b.main_account as main_account,
    b.local_amount as local_amount,
    f.period_amount as period_amount,
    {{ cast_to_decimal128('f.period_amount', amount_scale()) }} as expected_local_amount
from {{ ref('gold_consolidated_budget_tb') }} as b
inner join {{ ref('gold_spread_budget') }} as f
    on f.scenario_id = b.scenario_id
    and f.cycle = b.cycle
    and f.layer = b.layer
    and f.data_area_id = b.data_area_id
    and toUInt16(f.fiscal_year) = toUInt16(b.fiscal_year)
    and toUInt16(f.fiscal_period) = toUInt16(b.fiscal_period)
    and f.main_account = b.main_account
    {{ dim_join_on('f', 'b', dims=get_budget_dimensions()) }}
where b.local_amount != {{ cast_to_decimal128('f.period_amount', amount_scale()) }}
order by consolidation_group, scenario_id, cycle, layer, data_area_id, fiscal_year, fiscal_period, main_account
