{{
    config(
        engine='MergeTree()',
        order_by='(scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account)'
    )
}}

{# konsol#348 S6 WC2 (FC-4-2, Deepak Pai, 13 Nov 2026: "stay in S6"): how far each approved forecast round
   was from what happened, in the entity's currency.

   One row per (approved forecast round, CLOSED Regular period after its as-of period within its horizon,
   entity the round forecasts, account, budget dimensions, currency):
     forecast_amount     the round's gold_spread_budget rows (by `cycle`), layers summed (the actuals have
                         no layer, so the measured forecast is the final one);
     actual_amount       the GL rows of gold_scenario_trial_balance (data_source 'gl'), as
                         gold_latest_estimate reads them;
     forecast_error      forecast_amount - actual_amount, signed debit - credit like both sides;
     forecast_abs_error  |forecast_error|;
     forecast_error_pct  forecast_error / |actual_amount| x 100 (variance_pct's convention: the error's
                         sign, the actual's scale); NULL when the actual is 0, never 0 or an infinity
                         (assert_forecast_accuracy_pct_null_on_zero_actual);
     lag                 Regular periods from the round's as-of period (1 = the period after it), counted
                         on the declared calendar across a year end (forecast_round_periods(), BUD-10-1);
     as_of_date          the round's.

   Declared sub-rules (say so in a reader, never change silently):
   - Every APPROVED round is measured, not only the declared current one: accuracy compares rounds side by
     side (FC-4). A reader that wants the current round joins gold_forecast_current_round itself.
   - Closed (S6-Q8 a, under the standing rule): epm_staging.fiscal_periods.status Closed or Locked. konsol
     publishes the EFFECTIVE status there, the stricter of the Fiscal Year's and the period row's
     (konsol fiscal_calendar.fiscal_period_rows), so a period of a Closed year is never read as Open. A
     period declared on several rows counts as closed only when every row says so. An Open period is not
     measured: its actuals are still moving.
   - Entities: those the round forecasts (a gold_spread_budget row under the Cycle), as gold_latest_estimate.
     An entity with actuals and no forecast row is not in the round.
   - Accounts: within a forecast entity, an account with an actual and no forecast is a forecast of 0, and
     a forecast with no actual is measured against 0 ("Unbudgeted is unfavourable", Deepak Pai, 22 Sep 2026:
     no figure means zero). Both are real misses and stay in the error.
   - A round's rows stay inside its own fiscal year (Q24 a: a horizon crossing the year end is one Cycle per
     year sharing the as-of), and the lag still counts from the shared as-of across the year end.

   Joins are inner and on equalities only (join_use_nulls=0: an unmatched side would read ''/0); the two
   sides meet by UNION ALL + GROUP BY, never an outer join. Round and period columns are renamed (rp_*,
   re_*, a_*) so no alias matches a column another table in the join carries; the sums are taken under
   fresh names and renamed outside them (CYCLIC_ALIASES). One window only (regular_period_ranks()'s
   row_number), as gold_latest_estimate, so an empty warehouse's first build does not stack window steps.
   A table, rebuilt whole; nothing here reads or is read by the close. #}

{%- set budget_dims = get_budget_dimensions() %}

with closed_periods as (
    select
        toUInt16(fiscal_year) as cp_fiscal_year,
        toUInt16(fiscal_period) as cp_fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    group by fiscal_year, fiscal_period
    having countIf(status not in ('Closed', 'Locked')) = 0
),

round_periods as (
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
          select cp_fiscal_year, cp_fiscal_period from closed_periods
      )
),

round_entities as (
    select distinct
        cycle as re_cycle,
        data_area_id as re_entity
    from {{ ref('gold_spread_budget') }}
),

forecast_rows as (
    select
        rp.rp_scenario as a_scenario,
        rp.rp_cycle as a_cycle,
        rp.rp_as_of_date as a_as_of,
        f.data_area_id as a_entity,
        rp.rp_fiscal_year as a_year,
        toUInt8(rp.rp_fiscal_period) as a_period,
        toString(f.main_account) as a_account,
        {% for d in budget_dims %}
        f.{{ d.name }} as a_{{ d.name }},
        {% endfor %}
        f.currency as a_currency,
        rp.rp_lag as a_lag,
        {{ cast_to_decimal128('sum(f.period_amount)', amount_scale()) }} as a_forecast,
        {{ cast_to_decimal128('0', amount_scale()) }} as a_actual
    from {{ ref('gold_spread_budget') }} as f
    inner join round_periods as rp
        on rp.rp_cycle = f.cycle
        and rp.rp_scenario = f.scenario_id
        and rp.rp_fiscal_year = toUInt16(f.fiscal_year)
        and rp.rp_fiscal_period = toUInt16(f.fiscal_period)
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
        f.currency,
        rp.rp_lag
),

actual_rows as (
    select
        rp.rp_scenario as a_scenario,
        rp.rp_cycle as a_cycle,
        rp.rp_as_of_date as a_as_of,
        tb.data_area_id as a_entity,
        rp.rp_fiscal_year as a_year,
        toUInt8(rp.rp_fiscal_period) as a_period,
        toString(tb.main_account) as a_account,
        {% for d in budget_dims %}
        tb.{{ d.name }} as a_{{ d.name }},
        {% endfor %}
        tb.currency as a_currency,
        rp.rp_lag as a_lag,
        {{ cast_to_decimal128('0', amount_scale()) }} as a_forecast,
        {{ cast_to_decimal128('sum(tb.amount)', amount_scale()) }} as a_actual
    from {{ ref('gold_scenario_trial_balance') }} as tb
    inner join round_periods as rp
        on rp.rp_fiscal_year = toUInt16(tb.fiscal_year)
        and rp.rp_fiscal_period = toUInt16(tb.fiscal_period)
    inner join round_entities as re
        on re.re_cycle = rp.rp_cycle
        and re.re_entity = tb.data_area_id
    where tb.data_source = 'gl'
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
        tb.currency,
        rp.rp_lag
),

met as (
    select
        a_scenario,
        a_cycle,
        a_as_of,
        a_entity,
        a_year,
        a_period,
        a_account,
        {% for d in budget_dims %}
        a_{{ d.name }},
        {% endfor %}
        a_currency,
        a_lag,
        sum(a_forecast) as m_forecast,
        sum(a_actual) as m_actual
    from (
        select * from forecast_rows
        union all
        select * from actual_rows
    )
    group by
        a_scenario,
        a_cycle,
        a_as_of,
        a_entity,
        a_year,
        a_period,
        a_account,
        {% for d in budget_dims %}
        a_{{ d.name }},
        {% endfor %}
        a_currency,
        a_lag
)

select
    a_scenario as scenario_id,
    a_cycle as cycle,
    a_as_of as as_of_date,
    a_entity as data_area_id,
    a_year as fiscal_year,
    a_period as fiscal_period,
    a_account as main_account,
    {% for d in budget_dims %}
    a_{{ d.name }} as {{ d.name }},
    {% endfor %}
    a_currency as currency,
    toInt32(a_lag) as lag,
    m_forecast as forecast_amount,
    m_actual as actual_amount,
    m_forecast - m_actual as forecast_error,
    abs(m_forecast - m_actual) as forecast_abs_error,
    if(m_actual = 0,
       cast(null, 'Nullable(Float64)'),
       toFloat64(m_forecast - m_actual) / abs(toFloat64(m_actual)) * 100) as forecast_error_pct
from met
