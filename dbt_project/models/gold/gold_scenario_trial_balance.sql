{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

-- The two branches are a POSITIONAL union: a column added to one is added to
-- the other in the same place. Column order: scenario_id, data_area_id,
-- fiscal_year, fiscal_period, main_account, account_name, account_type_name,
-- budget dims, currency, amount, data_source.
--
-- CURRENCY (konsol#348 S3 B6, QB3 a): every row says what currency it is in,
-- so the variance models can carry it on their grain (B8) and never net two
-- currencies. The GL branch takes the entity's accounting currency from
-- silver_entity_currencies (konsol#110, the one answer); the budget branch takes
-- the fact's (gold_spread_budget.currency, B4).
--
-- ACTUAL: from gold_trial_balance (GL-sourced), stamped with the site's declared
-- actual scenario: the single active scenario_definitions row of type 'actual'
-- (PR #211 review 2, konsolidat#206). With none or several declared, the rows
-- keep 'ACTUAL', and assert_scenario_rows_declared names the problem instead of
-- this model failing.
-- LEFT JOIN silver_entity_currencies: an entity with no declared currency keeps
-- its rows, with currency '' (join_use_nulls=0 fills the default). That is not a
-- fallback: assert_scenario_tb_currency_declared (error) names every such row,
-- and assert_every_tb_entity_has_a_currency names the entity. Intake refuses an
-- Entity without a Functional Currency (konsol#328), so live this is a pin.
select
    sd.actual_scenario_id as scenario_id,
    tb.data_area_id as data_area_id,
    tb.fiscal_year as fiscal_year,
    tb.fiscal_period as fiscal_period,
    tb.main_account as main_account,
    tb.account_name as account_name,
    tb.account_type_name as account_type_name,
    {{ dim_select(prefix='tb.', dims=get_budget_dimensions(), trailing=true) }}
    ec.accounting_currency as currency,
    tb.period_net_amount as amount,
    'gl' as data_source
from {{ ref('gold_trial_balance') }} as tb
left join {{ ref('silver_entity_currencies') }} as ec
    on ec.data_area_id = tb.data_area_id
cross join (
    select
        if(uniqExact(scenario_id) = 1, any(scenario_id), 'ACTUAL') as actual_scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'actual'
      and is_active = 1
) as sd

union all

-- BUDGET/FORECAST from the canonical budget fact (annual-spread + manual
-- monthly, grynn-in/konsolidat#94). Replaces the empty epm_staging.budget_input
-- placeholder, which nothing populated — so app-entered budgets never reached
-- this scenario fact. gold_spread_budget scenario_ids (BUDGET_2024/2025,
-- FORECAST_*) are disjoint from the declared actual branch above, so no
-- double-count. The ERP 'BUDGET' branch (silver_budget_entries, data_source
-- 'd365_budget') is gone (konsol#348 S3 B1, QB1 b): the budget enters through
-- konsol's two tables only; tests/test_budget_models_read_no_erp.py pins it.
-- gold_spread_budget now carries one row per layer (base/challenge/management/
-- board); the scenario TB is the FINAL budget, so layers are summed back to one
-- row per (scenario, entity, period, account, dims, currency) here. The fact's
-- currency joins the grain (B6); konsol keeps it one per entity, and
-- assert_budget_currency_is_entity_currency names a line that is not.
-- The fact also carries the Budget Cycle (B4), which this model does NOT carry:
-- the cycles of one scenario-year are summed here, as the layers are. A
-- budget-type scenario has one cycle per year (assert_budget_one_cycle_per_
-- scenario_year); a forecast scenario has one per round, and this model is not
-- the place to read a forecast round (the variance models read budget-type
-- scenarios only; S6's latest-estimate read picks its round on the fact).
-- Until then a forecast holds one approved round (konsol refuses the second Approve;
-- assert_forecast_one_approved_round_until_s6 is the backstop), so this sum is
-- one round, never two.
select
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    '' as account_name,
    '' as account_type_name,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    currency,
    {{ cast_to_decimal128('sum(period_amount)', amount_scale()) }} as amount,
    'budget' as data_source
from {{ ref('gold_spread_budget') }}
group by
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
    currency
