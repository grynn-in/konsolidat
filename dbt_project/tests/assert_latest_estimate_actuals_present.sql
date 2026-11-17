-- konsol#348 S6 WA8 (FC-2-1: a missing actual is reported, never filled): every entity a forecast
-- round forecasts has an actual in each Regular period of the round's year up to and including its
-- as-of period. gold_latest_estimate takes the actual side from the GL rows; where an entity has none
-- for such a period, the estimate simply has no actual there (it never substitutes the forecast or a
-- zero), so the round's year-to-date reads short. This names each (scenario, round, entity, period) with
-- forecast rows in the round and no actual row in the estimate. One row per missing period; WARN: the
-- TB may simply not be uploaded yet, and the estimate is still right for what is there.
-- Periods come from forecast_round_periods() (declared calendar, BUD-10-1). NOT IN, not a LEFT JOIN
-- (join_use_nulls=0). Fixture: assert_latest_estimate_actuals_present.must_flag.sql (ZZE2 has no P2
-- actual: 1).
{{ config(severity='warn') }}

with expected as (
    select
        r.scenario_id as forecast_scenario,
        r.cycle as round_cycle,
        r.as_of_date as round_as_of,
        e.e_entity as entity,
        toUInt16(r.fiscal_year) as missing_year,
        toUInt16(r.fiscal_period) as missing_period
    from {{ forecast_round_periods() }} as r
    inner join (
        select distinct cycle as e_cycle, data_area_id as e_entity
        from {{ ref('gold_spread_budget') }}
    ) as e
        on e.e_cycle = r.cycle
    where r.fiscal_year = r.cycle_fiscal_year
      and r.lag <= 0
)

select
    forecast_scenario,
    round_cycle,
    round_as_of,
    entity,
    missing_year,
    missing_period
from expected
where (round_cycle, entity, missing_year, missing_period) not in (
    select cycle, data_area_id, toUInt16(fiscal_year), toUInt16(fiscal_period)
    from {{ ref('gold_latest_estimate') }}
    where source = 'actual'
)
