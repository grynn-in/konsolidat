{{
    config(
        engine='MergeTree()',
        order_by='(scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account)'
    )
}}

{# konsol#348 S6 WA7 (FC-2-1, S6-Q2 a): the latest estimate of every approved forecast round.

   A round's latest estimate is its year's actuals up to the as-of period and its forecast after it:
     source = 'actual'    the GL rows of gold_scenario_trial_balance (data_source 'gl') in the round's
                          fiscal year, in Regular periods AT OR BEFORE the round's as-of period (lag <= 0),
                          for the entities the round forecasts (an entity with a gold_spread_budget row
                          under the Cycle). An entity with actuals and no forecast row is not in the round.
     source = 'forecast'  the round's own gold_spread_budget rows (by `cycle`) in Regular periods AFTER the
                          as-of period and within the horizon (1 <= lag <= horizon_periods), in the round's
                          fiscal year, layers summed (the actuals have no layer, so the estimate is the final
                          forecast). A forecast row at or before the as-of period is NOT in the estimate:
                          the actual replaces it.
   Periods are counted on the declared calendar (forecast_round_periods(), BUD-10-1); a round whose as-of
   is in no declared Regular period has no row (assert_forecast_as_of_in_declared_period, error, names it).
   A horizon that crosses the year end is one Cycle per fiscal year sharing the as-of (Q24 a), so each
   Cycle's estimate stays inside its own year.

   EVERY approved round is here, keyed by `cycle` and `as_of_date`, not only the declared current one:
   rounds sit side by side (FC-4, S6-Q2 a). gold_latest_estimate_current narrows to the declared round
   (S6-Q1 b) for the Excel read. Rows are summed to one per (scenario_id, cycle, data_area_id,
   fiscal_year, fiscal_period, main_account, budget dimensions, currency): assert_latest_estimate_grain_unique.
   An actual that is missing for a forecast entity at or before the as-of is reported, never filled
   (FC-2-1): assert_latest_estimate_actuals_present (WARN).

   Joins are inner and on equalities only (join_use_nulls=0: an unmatched side would read ''); the lag
   and horizon conditions are a WHERE. Round and period columns are renamed (rp_*, re_*) so no alias
   matches a column another table in the join carries; the sums are taken in a subquery under a fresh
   name and renamed outside it (CYCLIC_ALIASES). #}

{%- set budget_dims = get_budget_dimensions() %}

with round_periods as (
    select
        cycle as rp_cycle,
        scenario_id as rp_scenario,
        as_of_date as rp_as_of_date,
        horizon_periods as rp_horizon,
        fiscal_year as rp_fiscal_year,
        fiscal_period as rp_fiscal_period,
        lag as rp_lag
    from {{ forecast_round_periods() }}
    where fiscal_year = cycle_fiscal_year
      and lag <= horizon_periods
),

round_entities as (
    select distinct
        cycle as re_cycle,
        data_area_id as re_entity
    from {{ ref('gold_spread_budget') }}
),

actual_rows as (
    select
        rp.rp_scenario as e_scenario,
        rp.rp_cycle as e_cycle,
        rp.rp_as_of_date as e_as_of,
        tb.data_area_id as e_entity,
        toUInt16(rp.rp_fiscal_year) as e_year,
        toUInt8(rp.rp_fiscal_period) as e_period,
        toString(tb.main_account) as e_account,
        {% for d in budget_dims %}
        tb.{{ d.name }} as e_{{ d.name }},
        {% endfor %}
        tb.currency as e_currency,
        {{ cast_to_decimal128('sum(tb.amount)', amount_scale()) }} as e_amount,
        'actual' as e_source
    from {{ ref('gold_scenario_trial_balance') }} as tb
    inner join round_periods as rp
        on rp.rp_fiscal_year = toUInt16(tb.fiscal_year)
        and rp.rp_fiscal_period = toUInt16(tb.fiscal_period)
    inner join round_entities as re
        on re.re_cycle = rp.rp_cycle
        and re.re_entity = tb.data_area_id
    where tb.data_source = 'gl'
      and rp.rp_lag <= 0
    group by
        rp.rp_scenario,
        rp.rp_cycle,
        rp.rp_as_of_date,
        tb.data_area_id,
        rp.rp_fiscal_year,
        rp.rp_fiscal_period,
        tb.main_account,
        {% for d in budget_dims %}
        tb.{{ d.name }},
        {% endfor %}
        tb.currency
),

forecast_rows as (
    select
        rp.rp_scenario as e_scenario,
        rp.rp_cycle as e_cycle,
        rp.rp_as_of_date as e_as_of,
        f.data_area_id as e_entity,
        toUInt16(rp.rp_fiscal_year) as e_year,
        toUInt8(rp.rp_fiscal_period) as e_period,
        toString(f.main_account) as e_account,
        {% for d in budget_dims %}
        f.{{ d.name }} as e_{{ d.name }},
        {% endfor %}
        f.currency as e_currency,
        {{ cast_to_decimal128('sum(f.period_amount)', amount_scale()) }} as e_amount,
        'forecast' as e_source
    from {{ ref('gold_spread_budget') }} as f
    inner join round_periods as rp
        on rp.rp_cycle = f.cycle
        and rp.rp_scenario = f.scenario_id
        and rp.rp_fiscal_year = toUInt16(f.fiscal_year)
        and rp.rp_fiscal_period = toUInt16(f.fiscal_period)
    where rp.rp_lag >= 1
    group by
        rp.rp_scenario,
        rp.rp_cycle,
        rp.rp_as_of_date,
        f.data_area_id,
        rp.rp_fiscal_year,
        rp.rp_fiscal_period,
        f.main_account,
        {% for d in budget_dims %}
        f.{{ d.name }},
        {% endfor %}
        f.currency
)

select
    e_scenario as scenario_id,
    e_cycle as cycle,
    e_as_of as as_of_date,
    e_entity as data_area_id,
    e_year as fiscal_year,
    e_period as fiscal_period,
    e_account as main_account,
    {% for d in budget_dims %}
    e_{{ d.name }} as {{ d.name }},
    {% endfor %}
    e_currency as currency,
    e_amount as period_amount,
    e_source as source
from (
    select * from actual_rows
    union all
    select * from forecast_rows
)
