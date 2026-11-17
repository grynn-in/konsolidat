{# konsol#348 S6 WA3 (BUD-10-1: horizons and lags are counted in DECLARED periods, never calendar months).

   A forecast round is an approved Budget Cycle of a forecast scenario, keyed by its as-of date (Q23 a);
   its horizon is `horizon_periods` Regular periods AFTER the as-of period. Three subquery macros put every
   round on the declared calendar (declared_periods(), the one source of period dates), so the readers that
   split "actual up to the as-of" from "forecast after it" (gold_latest_estimate, WA7), count the lag of a
   forecast period from its as-of (gold_forecast_accuracy, pair C) or the horizon's coverage (konsol's
   horizon_coverage_model, the same rule in Python) all count the same way.

   Every APPROVED round is here, not only the declared current one (S6-Q1 b): the latest estimate and the
   accuracy model keep rounds side by side (FC-4). A reader that wants the current round joins
   ref('gold_forecast_current_round') on (scenario_id, fiscal_year, cycle) itself.

     forecast_rounds()          one row per approved forecast round, from epm_staging.budget_cycles:
                                cycle, scenario_id, cycle_fiscal_year, as_of_date, horizon_periods.
                                Forecast scenarios by the declared type (IN, join_use_nulls=0); a Cycle
                                with no round (as_of_date at the 1900-01-01 default) is not one.
     regular_period_ranks()     every declared Regular period with period_rank, its 1-based position in
                                (fiscal_year, fiscal_period) order across years, so "N periods after" is
                                a rank difference even across a year end (Q24 a).
     forecast_round_as_of()     forecast_rounds() plus the as-of PERIOD: the lowest Regular period whose
                                declared span holds as_of_date (start_date <= as_of <= end_date, the
                                deal_period_holds rule; an Opening or Closing period never holds a date),
                                as as_of_fiscal_year, as_of_fiscal_period, as_of_rank. A round whose as-of
                                is in no Regular period has NO row: assert_forecast_as_of_in_declared_period
                                (error) names it, so nothing downstream drops it silently.
     forecast_round_periods()   forecast_round_as_of() x regular_period_ranks(): every round against every
                                declared Regular period with `lag` = period_rank - as_of_rank (0 the as-of
                                period, 1.. after it, negative before). A reader keeps lag <= 0 for the
                                actual side and 1 <= lag <= horizon_periods for the forecast side.

   Why cross join + where, not an inequality JOIN ON: the stack's ClickHouse (24.8) takes range conditions
   in ON only behind an experimental setting; the budget tables are small (declared_periods' deal rule does
   the same). Column names on the round side are prefixed (cycle_fiscal_year, as_of_*) so a join with the
   calendar never has two columns named fiscal_year: ClickHouse strips the left table's qualifier in a
   join, and a same-named alias would shadow it. Aggregates never alias to a column they read
   (CYCLIC_ALIASES / ILLEGAL_AGGREGATION; the declared_periods() note). #}

{% macro forecast_rounds() %}
    (
        select
            bc.name as cycle,
            bc.scenario_id as scenario_id,
            toUInt16(bc.fiscal_year) as cycle_fiscal_year,
            bc.as_of_date as as_of_date,
            toUInt16(bc.horizon_periods) as horizon_periods
        from {{ source('epm_staging', 'budget_cycles') }} as bc
        where bc.scenario_id in (
            select scenario_id
            from {{ source('epm_gold', 'scenario_definitions') }}
            where scenario_type = 'forecast'
        )
          and bc.as_of_date != toDate32('1900-01-01')
    )
{% endmacro %}


{% macro regular_period_ranks() %}
    (
        select
            fiscal_year,
            fiscal_period,
            start_date,
            end_date,
            row_number() over (order by fiscal_year, fiscal_period) as period_rank
        from {{ declared_periods() }}
        where period_type = 'Regular'
    )
{% endmacro %}


{% macro forecast_round_as_of() %}
    (
        select
            cycle,
            scenario_id,
            cycle_fiscal_year,
            as_of_date,
            horizon_periods,
            min(hold_rank) as as_of_rank,
            argMin(hold_fiscal_year, hold_rank) as as_of_fiscal_year,
            argMin(hold_fiscal_period, hold_rank) as as_of_fiscal_period
        from (
            select
                r.cycle as cycle,
                r.scenario_id as scenario_id,
                r.cycle_fiscal_year as cycle_fiscal_year,
                r.as_of_date as as_of_date,
                r.horizon_periods as horizon_periods,
                rp.period_rank as hold_rank,
                rp.fiscal_year as hold_fiscal_year,
                rp.fiscal_period as hold_fiscal_period
            from {{ forecast_rounds() }} as r
            cross join {{ regular_period_ranks() }} as rp
            where rp.start_date <= r.as_of_date
              and r.as_of_date <= rp.end_date
        )
        group by cycle, scenario_id, cycle_fiscal_year, as_of_date, horizon_periods
    )
{% endmacro %}


{% macro forecast_round_periods() %}
    (
        select
            a.cycle as cycle,
            a.scenario_id as scenario_id,
            a.cycle_fiscal_year as cycle_fiscal_year,
            a.as_of_date as as_of_date,
            a.horizon_periods as horizon_periods,
            a.as_of_fiscal_year as as_of_fiscal_year,
            a.as_of_fiscal_period as as_of_fiscal_period,
            rp.fiscal_year as fiscal_year,
            rp.fiscal_period as fiscal_period,
            rp.start_date as start_date,
            rp.end_date as end_date,
            toInt32(rp.period_rank) - toInt32(a.as_of_rank) as lag
        from {{ forecast_round_as_of() }} as a
        cross join {{ regular_period_ranks() }} as rp
    )
{% endmacro %}


{# konsol#348 S6 WC2/WC3 (FC-4-2, S6-Q8 a): the (round, period) pairs forecast accuracy measures, one
   definition for gold_forecast_accuracy (entity currency) and gold_forecast_accuracy_group (group
   currency). From forecast_round_periods(): the round's own fiscal year (Q24 a), 1 <= lag <= horizon,
   and only CLOSED periods: epm_staging.fiscal_periods.status Closed or Locked, which konsol publishes as
   the EFFECTIVE status (the stricter of the Fiscal Year's and the row's; fiscal_calendar.fiscal_period_rows),
   on every row that declares the period. Columns are prefixed rp_ so a reader's join never meets a
   same-named column (fiscal_year, cycle). #}
{% macro forecast_accuracy_round_periods() %}
    (
        select
            cycle as rp_cycle,
            scenario_id as rp_scenario,
            as_of_date as rp_as_of_date,
            toUInt16(fiscal_year) as rp_fiscal_year,
            toUInt16(fiscal_period) as rp_fiscal_period,
            lag as rp_lag
        from {{ forecast_round_periods() }}
        where fiscal_year = cycle_fiscal_year
          and lag >= 1
          and lag <= horizon_periods
          and (toUInt16(fiscal_year), toUInt16(fiscal_period)) in (
              select toUInt16(fiscal_year), toUInt16(fiscal_period)
              from {{ source('epm_staging', 'fiscal_periods') }}
              group by fiscal_year, fiscal_period
              having countIf(status not in ('Closed', 'Locked')) = 0
          )
    )
{% endmacro %}
