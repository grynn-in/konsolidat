-- konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459): a forecast
-- scenario's rows in gold_scenario_trial_balance are the DECLARED current round's and no other's.
--
-- Rounds never sum. The scenario TB's budget branch groups without `cycle`, so before S6 WA4 it added
-- every approved round of a forecast (scenario, year) together (R1 100 + R2 110 = 210, and konsol
-- refused the second Approve to keep that from happening). Now the branch keeps, for a forecast-type
-- scenario, only the rows of gold_forecast_current_round's cycle; a pair with no declaration has no
-- rows at all. This ties the two: per (scenario, entity, year, period, account, currency) of every
-- forecast scenario, the TB's amount must equal the fact's period_amount summed over layers (and budget
-- dimensions) for the declared cycle; a key on one side only, or an amount off by more than the
-- materiality floor, is one row here. A key present in the TB with no declared round is therefore
-- named (the TB holds rows the declaration does not back), and so is a declared round whose rows the TB
-- dropped. Budget-type scenarios pass through the branch unchanged and are not read here. Error
-- severity: every reader of the scenario TB (the variance models, the cost-allocation pool) would
-- report a doubled or an empty forecast.
--
-- join_use_nulls=0: an unmatched FULL OUTER JOIN side reads '' (never NULL), so the "missing" test is
-- coalesce(..., '') = '' on the key's scenario_id, as assert_budget_node_per_cycle_and_currency does;
-- output aliases differ from the joined columns' names so no alias shadows a stripped qualifier.
-- Fixtures: assert_scenario_tb_forecast_is_current_round.sql (R1 100, R2 110, R2 declared: the TB
-- shows 110, pass), assert_scenario_tb_forecast_is_current_round.must_flag.sql (the TB seeded with
-- the summed 210 against the same declaration: 1 result, the shape of the pre-WA4 model).
{{ config(severity='error') }}

with forecast_scenarios as (
    select scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'forecast'
),

expected as (
    select
        f.scenario_id as scenario_id,
        f.data_area_id as data_area_id,
        toUInt16(f.fiscal_year) as fiscal_year,
        toUInt8(f.fiscal_period) as fiscal_period,
        toString(f.main_account) as main_account,
        f.currency as currency,
        sum(toFloat64(f.period_amount)) as period_amount
    from {{ ref('gold_spread_budget') }} as f
    where f.scenario_id in (select scenario_id from forecast_scenarios)
      and (f.scenario_id, toUInt16(f.fiscal_year), f.cycle) in (
        select scenario_id, toUInt16(fiscal_year), cycle
        from {{ ref('gold_forecast_current_round') }}
      )
    group by f.scenario_id, f.data_area_id, f.fiscal_year, f.fiscal_period, f.main_account, f.currency
),

tb as (
    select
        t.scenario_id as tb_scenario,
        t.data_area_id as tb_entity,
        toUInt16(t.fiscal_year) as tb_year,
        toUInt8(t.fiscal_period) as tb_period,
        toString(t.main_account) as tb_account,
        t.currency as tb_currency,
        sum(toFloat64(t.amount)) as tb_amount
    from {{ ref('gold_scenario_trial_balance') }} as t
    where t.data_source = 'budget'
      and t.scenario_id in (select scenario_id from forecast_scenarios)
    group by t.scenario_id, t.data_area_id, t.fiscal_year, t.fiscal_period, t.main_account, t.currency
)

select
    if(coalesce(e.scenario_id, '') != '', e.scenario_id, b.tb_scenario) as forecast_scenario,
    if(coalesce(e.scenario_id, '') != '', e.data_area_id, b.tb_entity) as entity,
    if(coalesce(e.scenario_id, '') != '', e.fiscal_year, b.tb_year) as key_year,
    if(coalesce(e.scenario_id, '') != '', e.fiscal_period, b.tb_period) as key_period,
    if(coalesce(e.scenario_id, '') != '', e.main_account, b.tb_account) as account,
    if(coalesce(e.scenario_id, '') != '', e.currency, b.tb_currency) as row_currency,
    e.period_amount as declared_round_amount,
    b.tb_amount as scenario_tb_amount
from expected as e
full outer join tb as b
    on b.tb_scenario = e.scenario_id
    and b.tb_entity = e.data_area_id
    and b.tb_year = e.fiscal_year
    and b.tb_period = e.fiscal_period
    and b.tb_account = e.main_account
    and b.tb_currency = e.currency
where coalesce(e.scenario_id, '') = ''
   or coalesce(b.tb_scenario, '') = ''
   or abs(e.period_amount - b.tb_amount) > {{ materiality_floor() }}
