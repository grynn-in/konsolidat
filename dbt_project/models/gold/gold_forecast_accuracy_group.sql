{{
    config(
        engine='MergeTree()',
        order_by='(consolidation_group, scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account)'
    )
}}

{# konsol#348 S6 WC3 (FC-4-2): gold_forecast_accuracy in the GROUP's currency, per consolidation group.

   One row per (consolidation group, approved forecast round, closed Regular period after its as-of within
   its horizon, entity the round forecasts in that group, account, budget dimensions, reporting currency):
     forecast_amount     gold_consolidated_budget_tb.group_amount of the round's Cycle, layers summed:
                         translated at the Cycle's Rate Set, at the group's share (proportional) as the
                         budget consolidation computes it;
     actual_amount       gold_consolidated_trial_balance.group_amount, at the actuals' rates and share,
                         summed to the budget dimensions (the actuals carry every dimension);
     forecast_error, forecast_abs_error, forecast_error_pct, lag, as_of_date: as gold_forecast_accuracy.
   The two sides translate at different rates, so for an entity outside the group's currency the error
   holds the FX movement between the forecast's Rate Set and the actuals' rates; that is what this view
   adds to gold_forecast_accuracy (the entity-currency error, with no FX in it).

   Entity rows only, before eliminations: the budget has no partner (konsol#427) and no deal journals
   (konsol#425), and gold_consolidated_trial_balance holds the entities' translated rows (no CTA,
   eliminations or journals), so both sides are compared at the same layer.

   The rules of gold_forecast_accuracy hold here too (every approved round side by side; closed = the
   effective status Closed or Locked, S6-Q8 a; an account with an actual and no forecast is a forecast of 0;
   a round's rows stay in its own fiscal year), with "the entities the round forecasts" taken per group:
   a (group, Cycle, entity) with a gold_consolidated_budget_tb row. The (round, period) pairs come from
   forecast_accuracy_round_periods(), the definition both models share. UNION ALL + GROUP BY, inner
   equality joins only (join_use_nulls=0); fresh names under the sums (CYCLIC_ALIASES); one window.
   A table, rebuilt whole. It reads gold_consolidated_trial_balance and is read by nothing in the close
   (tests/test_budget_outside_close.py). #}

{%- set budget_dims = get_budget_dimensions() %}

with round_periods as {{ forecast_accuracy_round_periods() }},

round_entities as (
    select distinct
        consolidation_group as re_group,
        cycle as re_cycle,
        data_area_id as re_entity
    from {{ ref('gold_consolidated_budget_tb') }}
),

forecast_rows as (
    select
        b.consolidation_group as a_group,
        rp.rp_scenario as a_scenario,
        rp.rp_cycle as a_cycle,
        rp.rp_as_of_date as a_as_of,
        b.data_area_id as a_entity,
        rp.rp_fiscal_year as a_year,
        toUInt8(rp.rp_fiscal_period) as a_period,
        toString(b.main_account) as a_account,
        {% for d in budget_dims %}
        b.{{ d.name }} as a_{{ d.name }},
        {% endfor %}
        b.reporting_currency as a_currency,
        rp.rp_lag as a_lag,
        {{ cast_to_decimal128('sum(b.group_amount)', amount_scale()) }} as a_forecast,
        {{ cast_to_decimal128('0', amount_scale()) }} as a_actual
    from {{ ref('gold_consolidated_budget_tb') }} as b
    inner join round_periods as rp
        on rp.rp_cycle = b.cycle
        and rp.rp_scenario = b.scenario_id
        and rp.rp_fiscal_year = toUInt16(b.fiscal_year)
        and rp.rp_fiscal_period = toUInt16(b.fiscal_period)
    group by
        b.consolidation_group,
        rp.rp_scenario,
        rp.rp_cycle,
        rp.rp_as_of_date,
        b.data_area_id,
        rp.rp_fiscal_year,
        rp.rp_fiscal_period,
        b.main_account,
        {% for d in budget_dims %}
        b.{{ d.name }},
        {% endfor %}
        b.reporting_currency,
        rp.rp_lag
),

actual_rows as (
    select
        t.consolidation_group as a_group,
        rp.rp_scenario as a_scenario,
        rp.rp_cycle as a_cycle,
        rp.rp_as_of_date as a_as_of,
        t.data_area_id as a_entity,
        rp.rp_fiscal_year as a_year,
        toUInt8(rp.rp_fiscal_period) as a_period,
        toString(t.main_account) as a_account,
        {% for d in budget_dims %}
        t.{{ d.name }} as a_{{ d.name }},
        {% endfor %}
        t.reporting_currency as a_currency,
        rp.rp_lag as a_lag,
        {{ cast_to_decimal128('0', amount_scale()) }} as a_forecast,
        {{ cast_to_decimal128('sum(t.group_amount)', amount_scale()) }} as a_actual
    from {{ ref('gold_consolidated_trial_balance') }} as t
    inner join round_periods as rp
        on rp.rp_fiscal_year = toUInt16(t.fiscal_year)
        and rp.rp_fiscal_period = toUInt16(t.fiscal_period)
    inner join round_entities as re
        on re.re_group = t.consolidation_group
        and re.re_cycle = rp.rp_cycle
        and re.re_entity = t.data_area_id
    group by
        t.consolidation_group,
        rp.rp_scenario,
        rp.rp_cycle,
        rp.rp_as_of_date,
        t.data_area_id,
        rp.rp_fiscal_year,
        rp.rp_fiscal_period,
        t.main_account,
        {% for d in budget_dims %}
        t.{{ d.name }},
        {% endfor %}
        t.reporting_currency,
        rp.rp_lag
),

met as (
    select
        a_group,
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
        a_group,
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
    a_group as consolidation_group,
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
    a_currency as reporting_currency,
    toInt32(a_lag) as lag,
    m_forecast as forecast_amount,
    m_actual as actual_amount,
    m_forecast - m_actual as forecast_error,
    abs(m_forecast - m_actual) as forecast_abs_error,
    if(m_actual = 0,
       cast(null, 'Nullable(Float64)'),
       toFloat64(m_forecast - m_actual) / abs(toFloat64(m_actual)) * 100) as forecast_error_pct
from met
