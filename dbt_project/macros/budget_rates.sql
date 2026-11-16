{#
    konsol#348 S4 (W4, W5): the consolidated budget's inputs and its rate guard.

    A budget translates at the Rate Set its Budget Cycle declares (BUD-3;
    S4-Q1 c, S4-Q2 a), read from epm_staging.budget_cycles, konsol's
    write-through of the APPROVED Cycles. Never at the actuals set, and never
    at 1.0: a budget key whose Cycle's set has no usable rate stops the budget
    build by name (budget_rate_guard, the model's pre_hook), and only the
    budget build. The actuals guard (governed_rate_guard, macros/
    governed_rates.sql) keys on gold_trial_balance and the actuals set, so a
    missing budget rate never stops gold_consolidated_trial_balance, and a
    missing actuals rate never stops the budget.

    One definition, three users: budget_rate_gaps() is read by the guard
    (pre_hook), by assert_budget_translated_currency_has_a_governed_rate (the
    singular test that lists every gap) and, through
    budget_consolidation_inputs(), by the model itself, so the keys the guard
    requires are exactly the keys the model translates.
#}

{#
    The rate rows a budget build reads: every set an approved Cycle declares.
    This is the budget's `rate_set_predicate` for consolidation_core (which
    requires one): it narrows the rate tables to the sets in play, and the
    core's `rate_set_column` then keys each row's rate on its own Cycle's set,
    so two Cycles' sets holding a rate for one (from, to, year, period) are two
    keys, not a duplicate. `column` is the rate_set column as the caller's
    query sees it (`rate_set` bare, `g.rate_set` under an alias).
#}
{% macro budget_rate_set_predicate(column='rate_set') -%}
{{ column }} in (select rate_set from {{ source('epm_staging', 'budget_cycles') }})
{%- endmacro %}

{#
    The budget fact as the consolidation reads it, and its period spine. Emits
    two CTEs, {p}budget_fact and {p}budget_periods; call it after `with`, as
    `with {{ budget_consolidation_inputs() }}, ...`.

    {p}budget_fact   gold_spread_budget joined to the APPROVED Cycles
                     (epm_staging.budget_cycles, on the Cycle's name), carrying
                     the Cycle's rate_set. A fact row whose Cycle is not
                     approved is not consolidated; assert_budget_cycle_is_approved
                     (warn) names it, so nothing leaves silently.
    {p}budget_periods  the distinct (entity, fiscal_year, fiscal_period) the
                     BUDGET has rows in, with the dates konsol's calendar
                     declares for the period (declared_periods()), in the shape
                     ownership_resolution_ctes() takes. This is the spine the
                     budget's ownership is resolved on: gold_entity_ownership's
                     spine is the ACTUALS' periods, so a budget period with no
                     trial balance row (next year's budget, entered before the
                     year starts) has no ownership there and vanished from an
                     ownership join on it. A budget period the calendar does
                     not declare is dropped by the inner join and named by
                     assert_budget_period_declared.
#}
{% macro budget_consolidation_inputs(p='') %}
{{ p }}budget_fact as (
    select
        b.scenario_id as scenario_id,
        b.cycle as cycle,
        b.layer as layer,
        b.data_area_id as data_area_id,
        toUInt16(b.fiscal_year) as fiscal_year,
        toUInt16(b.fiscal_period) as fiscal_period,
        b.main_account as main_account,
        {{ dim_select(dims=get_budget_dimensions(), prefix='b.', trailing=true) }}
        b.currency as currency,
        b.period_amount as period_amount,
        bc.rate_set as rate_set
    from {{ ref('gold_spread_budget') }} as b
    inner join (
        select name, rate_set
        from {{ source('epm_staging', 'budget_cycles') }}
    ) as bc
        on bc.name = b.cycle
),

{{ p }}budget_periods as (
    select distinct
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        dp.window_start_date as period_start_date,
        dp.window_end_date as period_date
    from {{ p }}budget_fact as f
    inner join {{ declared_periods() }} as dp
        on dp.fiscal_year = f.fiscal_year
        and dp.fiscal_period = f.fiscal_period
)
{% endmacro %}
