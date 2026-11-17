-- konsol#348 S6 WA3 (BUD-10-1: horizons and lags are counted in DECLARED periods). A forecast round's as-of
-- date must fall inside a declared Regular period of the fiscal calendar (epm_staging.fiscal_periods,
-- through declared_periods()): that period is where "actual up to the as-of" ends and the horizon starts
-- (forecast_round_as_of(), macros/forecast_rounds.sql). A round whose as-of date is in no Regular period
-- (a year not yet declared, a gap between periods, a date on an Opening/Closing day with no Regular period
-- around it) cannot be counted: the latest estimate and the accuracy model have no row for it, silently,
-- and this names it instead. Every approved round of a forecast scenario is checked, not only the
-- declared current one: the accuracy model (pair C) reads every round. Error severity: a reader that
-- drops a round is wrong, and the fix is to declare the period in EPM Fiscal Year.
-- NOT IN, not a LEFT JOIN null test (join_use_nulls=0).
-- Fixtures: assert_forecast_as_of_in_declared_period.must_flag.sql (as-of in an undeclared year: 1 result),
-- assert_forecast_as_of_in_declared_period.sql (as-of inside a declared period: pass).
{{ config(severity='error') }}

select
    r.cycle as cycle,
    r.scenario_id as scenario_id,
    r.cycle_fiscal_year as fiscal_year,
    r.as_of_date as as_of_date,
    r.horizon_periods as horizon_periods
from {{ forecast_rounds() }} as r
where r.cycle not in (select cycle from {{ forecast_round_as_of() }})
order by r.scenario_id, r.cycle_fiscal_year, r.as_of_date
