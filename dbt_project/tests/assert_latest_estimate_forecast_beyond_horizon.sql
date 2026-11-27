-- konsol#348 S6 pair A review M1 (FC-2-1): a round's forecast after its horizon is reported, never
-- dropped silently. gold_latest_estimate keeps a round's own gold_spread_budget rows in the Regular
-- periods after its as-of period up to the ROUND's horizon (1 <= lag <= round_horizon_periods, the
-- longest horizon_periods among the Cycles sharing the as-of, forecast_rounds(); konsolidat#376: a
-- Cycle's own shorter horizon is not the cut, so its rows inside the round's are not named); a row at or
-- before the as-of is replaced by the actual (the declared rule, not reported here). A row AFTER the
-- horizon has nowhere to go: the estimate leaves it out and the year reads short of what was entered.
-- This names each (scenario, round, entity, account, year, period) of an approved round's fact rows
-- whose period is beyond the horizon, with the amount left out. A key summing to exactly zero drops
-- nothing and is not named. WARN: the horizon may simply be declared shorter than the sheet entered, and the
-- estimate is right for the horizon declared; extend the horizon or remove the rows.
-- Periods come from forecast_round_periods() (declared calendar, BUD-10-1), the round's own fiscal year
-- (a horizon crossing the year end is one Cycle per year, Q24 a). The round columns are renamed (b_*)
-- so no alias matches a column the joined fact carries. Fixtures:
-- assert_latest_estimate_forecast_beyond_horizon.must_flag.sql (the hand table's R1 P7 -41: 1),
-- assert_latest_estimate_forecast_beyond_horizon.round_horizon.must_flag.sql (two Cycles, horizons 12
-- and 3, in one round: only the other round's P3: 1) and
-- assert_latest_estimate_forecast_beyond_horizon.sql (nothing beyond, a zero row: pass).
{{ config(severity='warn') }}

with beyond as (
    select
        cycle as b_cycle,
        scenario_id as b_scenario,
        as_of_date as b_as_of,
        round_horizon_periods as b_horizon,
        fiscal_year as b_year,
        fiscal_period as b_period
    from {{ forecast_round_periods() }}
    where fiscal_year = cycle_fiscal_year
      and lag > round_horizon_periods
)

select
    f.scenario_id as forecast_scenario,
    f.cycle as round_cycle,
    b.b_as_of as round_as_of,
    b.b_horizon as round_horizon,
    f.data_area_id as entity,
    toString(f.main_account) as account,
    toUInt16(f.fiscal_year) as dropped_year,
    toUInt16(f.fiscal_period) as dropped_period,
    sum(f.period_amount) as dropped_amount
from {{ ref('gold_spread_budget') }} as f
inner join beyond as b
    on b.b_cycle = f.cycle
    and b.b_scenario = f.scenario_id
    and b.b_year = toUInt16(f.fiscal_year)
    and b.b_period = toUInt16(f.fiscal_period)
group by
    f.scenario_id,
    f.cycle,
    b.b_as_of,
    b.b_horizon,
    f.data_area_id,
    f.main_account,
    f.fiscal_year,
    f.fiscal_period
having dropped_amount != 0
