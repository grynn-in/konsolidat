{{
    config(
        materialized='table',
        query_settings={'query_plan_enable_multithreading_after_window_functions': 0},
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsol#348 S4 (W4; S4-Q3 a, S4-Q4 a): the translated and consolidated BUDGET, in the shape of
   gold_consolidated_trial_balance plus three grain columns (scenario_id, cycle, layer), so S5's
   readers read the same columns for a budget as for the actuals. One row per (group, scenario,
   cycle, layer, entity, period, account, budget dimensions): local_amount in the entity's currency,
   translated_amount / group_amount / nci_amount in the group's, the rates used, the ownership.
   Before eliminations (konsol#427): a budget has no partner, so partner_data_area_id is '' on
   every row and no intercompany elimination runs on it. The FCTB-shaped model (W6) adds the CTA
   and NCI attribution layers.

   The core (entity_tb .. consolidated) is macros/consolidation_core.sql, the same macro
   gold_consolidated_trial_balance calls; every translation rule (konsolidat#93 governed rates,
   #257 balance sheet retranslation, #259 year-end close, #204 full and proportional) is applied
   once, there. What is this model's own:

   - Source: gold_spread_budget (the canonical monthly budget fact, annual spreads and manual
     lines, every layer, every Cycle) joined to epm_staging.budget_cycles, konsol's write-through
     of the APPROVED Cycles (S4-Q2 a): an unapproved Cycle's rows are not consolidated, and
     assert_budget_cycle_is_approved (warn) names them. The statement flags and names come from the
     chart (silver_main_accounts; S4-Q6 a): the budget fact carries none. period_amount is already
     signed like the actuals (debit - credit, BUD-7) and is cast to the actuals' Decimal scale.
     is_year_end_close is 0: a budget posts no close.
   - Rate Set (BUD-3; S4-Q1 c): each row translates at ITS CYCLE's Rate Set, never the actuals set
     and never 1.0. One model holds Cycles on different sets (a budget and a reforecast), so the set
     is on the rate KEY: the core's rate_set_column takes it from the row, groups the governed
     rates per set and keys both rate joins on it; rate_set_predicate narrows the rate tables to
     the Cycles' sets. A key with no usable rate in its Cycle's set stops this build by name
     (budget_rate_guard, the pre_hook; macros/budget_rates.sql), and only this build.
   - Ownership: resolved on the BUDGET's own period spine, distinct (entity, year, period) of the
     fact x the declared calendar, through ownership_resolution_ctes(), not read from
     gold_entity_ownership, whose spine is the periods the ACTUALS have rows in: a budget is entered
     before its year starts, so most of its periods have no trial balance row and vanished from an
     ownership join with nothing failing. assert_budget_consolidated_periods_complete pins it.
   - Grain: the budget dimensions (get_budget_dimensions(), the chart's in_budget subset, BUD-8-2)
     plus grain_extra scenario_id, cycle, layer: each is a consolidation of its own, threaded by the
     core through every window partition (a layer's balance is never retranslated against another's,
     a Cycle's never against another's); assert_budget_consolidated_hand_table pins it, and
     assert_consolidation_core_grain_extra_is_a_partition proves the threading in general.
   - Scope: none (scoped=false, no period_filter): the budget is small and this is a table, rebuilt
     whole (S4-Q4 a). A refused build leaves the previous table as it was.
   - rate_set is carried on every row (last), so a reader can see which set translated it
     without a join.

   Fully-consolidated budget layers (CTA, NCI attribution) are W6's model; nothing here reads or is
   read by the close (gold_fully_consolidated_tb, the close fingerprint). #}

with {{ budget_consolidation_inputs() }},

{{ ownership_resolution_ctes('budget_periods', 'own_') }},

{# The core's source contract (macros/consolidation_core.sql header), filled from the budget fact and
   the chart. LEFT on the chart: an undeclared account stays in the consolidation at the closing rate
   with '' names and 0 flags, as it does for the actuals (join_use_nulls=0). #}
budget_source as (
    select
        f.data_area_id as data_area_id,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        f.main_account as main_account,
        ma.account_name as account_name,
        ma.account_type_name as account_type_name,
        ma.is_balance_sheet as is_balance_sheet,
        ma.is_pnl as is_pnl,
        {# konsol#427: a budget has no partner #}
        '' as partner_data_area_id,
        {{ dim_select(dims=get_budget_dimensions(), prefix='f.', trailing=true) }}
        f.scenario_id as scenario_id,
        f.cycle as cycle,
        f.layer as layer,
        toDecimal128(f.period_amount, {{ amount_scale() }}) as local_amount,
        toUInt8(0) as is_year_end_close,
        f.rate_set as rate_set
    from budget_fact as f
    left join (
        select main_account_id, account_name, account_type_name, is_balance_sheet, is_pnl
        from {{ ref('silver_main_accounts') }}
    ) as ma
        on ma.main_account_id = f.main_account
),

{{ consolidation_core(source_cte='budget_source',
                      dims=get_budget_dimensions(),
                      rate_set_predicate=budget_rate_set_predicate(),
                      ownership_cte='own_resolution',
                      grain_extra=['scenario_id', 'cycle', 'layer'],
                      scoped=false,
                      rate_set_column='rate_set') }},

with_set as (
    select c.*, bc.rate_set as rate_set
    from consolidated as c
    inner join (
        select name, rate_set
        from {{ source('epm_staging', 'budget_cycles') }}
    ) as bc
        on bc.name = c.cycle
)

{# gold_consolidated_trial_balance's final shape, in its order (partner_data_area_id,
   uses_historical_rate, retranslation_amount last), then rate_set. A table, so nothing here is
   positional; the order is kept for S5's readers. #}
select * except (partner_data_area_id, uses_historical_rate, translation_adjustment, fx_method,
                 is_retained_earnings, is_year_end_close, is_filler, rate_set),
       partner_data_area_id,
       uses_historical_rate,
       translation_adjustment as retranslation_amount,
       rate_set
from with_set
