{{
    config(
        materialized='table',
        query_settings={'query_plan_enable_multithreading_after_window_functions': 0},
        pre_hook=[
            "{{ budget_rate_guard() }}"
        ],
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
     of the APPROVED Cycles (S4-Q2 a), which carries each Cycle's Rate Set. Since S3 the fact's own
     inputs (budget_annual_input, budget_entries) are in ClickHouse only while their Cycle is
     approved, so in a consistent warehouse every fact row finds its Cycle here; a fact row whose
     Cycle has no budget_cycles row is sync drift between the three write-throughs, is not
     consolidated, and assert_budget_cycle_is_approved (warn) names it. The statement flags and names come from the
     chart (silver_main_accounts; S4-Q6 a): the budget fact carries none. period_amount is already
     signed like the actuals (debit - credit, BUD-7) and is ROUNDED to the actuals' Decimal scale
     (cast_to_decimal128, never toDecimal128 of a Float64, konsolidat#191).
     is_year_end_close is 0: a budget posts no close.
   - Rate Set (BUD-3; S4-Q1 c): each row translates at ITS CYCLE's Rate Set, never the actuals set
     and never 1.0. One model holds Cycles on different sets (a budget and a reforecast), so the set
     is on the rate KEY: the core's rate_set_column takes it from the row, groups the governed
     rates per set and keys both rate joins on it; rate_set_predicate narrows the rate tables to
     the Cycles' sets. A key with no usable rate in its Cycle's set stops this build by name
     (budget_rate_guard, the pre_hook; macros/budget_rates.sql), and only this build.
   - Ownership: resolved on the BUDGET's own period spine, distinct (entity, year, period) of the
     fact x the declared calendar, materialised once in gold_budget_entity_ownership
     (konsolidat#369: resolved inline here, the core's four reads of its rated CTE re-planned the
     whole resolution each time, 33 KB of SQL and ~6.6 s per statement on an empty budget;
     the CANNOT_SCHEDULE_TASK that issue opened with was not this but the thread cap, see
     partner_data_area_id below and the core's entity_tb), not read from
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
   - fx_method and rate_set are carried on every row (last, in that order), so a reader can see
     which method and which set translated it without a join. konsol#348 S5 (G1): the Statement
     Drill's "rate used" shows the method the warehouse APPLIED to the row, which is the chart's
     declaration at build time; the chart's method of today may differ, so konsol reads it here.

   Fully-consolidated budget layers (CTA, NCI attribution) are W6's model; nothing here reads or is
   read by the close (gold_fully_consolidated_tb, the close fingerprint). #}

{# konsol#348 S4 (W5): the first and only pre_hook, budget_rate_guard (macros/budget_rates.sql),
   raises BEFORE the table is replaced when a budget key has no usable rate in its Cycle's set,
   naming scenario, Cycle, set, currency pair, rate period and reason. It also reads the currencies'
   reference magnitudes; declared here so dbt knows the dependency at parse time (the body reads the
   calendar and the Cycles itself). #}
-- depends_on: {{ source('epm_gold', 'currencies') }} {{ source('epm_staging', 'fiscal_periods') }} {{ source('epm_staging', 'budget_cycles') }}

with {{ budget_consolidation_inputs(with_periods=false) }},

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
        {# konsol#427: a budget has no partner. materialize, not a bare constant:
           this column sits in every window partition of the core, and ClickHouse
           24.8 loses the sorted-stream property across a constant sort column, so
           with '' the budget sorted and scattered a third time between
           retranslated and close_pnl (500 window transforms against the actuals'
           50 on an empty warehouse) and exhausted the thread pool
           (konsolidat#369; tests/test_consolidation_core_thread_cap.py). #}
        materialize('') as partner_data_area_id,
        {{ dim_select(dims=get_budget_dimensions(), prefix='f.', trailing=true) }}
        f.scenario_id as scenario_id,
        f.cycle as cycle,
        f.layer as layer,
        {# konsolidat#191's class (S4b live test): period_amount is a Float64, and
           toDecimal128(Float64) truncates toward zero (1234567.89 -> 1234567.8899;
           1000.01 / 12 -> 83.3341 for 83.3342). cast_to_decimal128 rounds to the scale
           first; assert_budget_consolidated_local_amount_exact compares exactly. #}
        {{ cast_to_decimal128('f.period_amount', amount_scale()) }} as local_amount,
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
                      ownership_cte=ref('gold_budget_entity_ownership'),
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
   uses_historical_rate, retranslation_amount last), then fx_method and rate_set (S5 G1: the
   actuals' table drops fx_method; the budget keeps it for the drill). A table, so nothing here is
   positional; the order is kept for S5's readers. #}
select * except (partner_data_area_id, uses_historical_rate, translation_adjustment, fx_method,
                 is_retained_earnings, is_year_end_close, is_filler, rate_set),
       partner_data_area_id,
       uses_historical_rate,
       translation_adjustment as retranslation_amount,
       fx_method,
       rate_set
from with_set
