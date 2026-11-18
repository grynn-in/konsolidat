{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsol#348 S4 / konsolidat#369: the BUDGET's ownership, resolved once on the budget's own
   period spine and materialised, in gold_entity_ownership's shape (ownership_resolution_ctes()'s
   output: one row per (ancestor group, entity, fiscal_year, fiscal_period) with owner_group,
   has_complete_chain, effective_ownership_pct, consolidation_method, ...).

   Why a model of its own. gold_entity_ownership's spine is the periods the ACTUALS have rows in
   (gold_trial_balance x the declared calendar); a budget is entered before its year starts, so
   most of its periods have no ownership row there and vanished from an ownership join
   (assert_budget_consolidated_periods_complete). W4 therefore resolved the graph inline, as the
   core's ownership_cte, from the budget's own spine: distinct (entity, year, period) of the
   approved Cycles' fact rows x the declared calendar (budget_consolidation_inputs(),
   macros/budget_rates.sql). But ClickHouse inlines every CTE reference: the core reads its
   `rated` CTE four times, each copy re-planning the whole resolution (a ~300-line chain with 13
   internal references of its own), and budget_rate_guard's gap query planned it a fifth time.
   The compiled SELECT was 33 KB against the CTB's 18 KB, the live CREATE and INSERT took ~6.6 s
   EACH on an empty budget (analysis, not data), and CI's smaller ClickHouse ran out of threads
   (CANNOT_SCHEDULE_TASK, code 439). Resolved here once, the readers join a table:
   gold_consolidated_budget_tb (ownership_cte=ref(this)), budget_rate_gaps() (the pre_hook guard
   and assert_budget_translated_currency_has_a_governed_rate) and
   assert_budget_declared_historical_has_a_rate. tests/test_budget_ownership_materialised.py
   pins that none of them resolves the graph again.

   Spine: a budget period the calendar does not declare is dropped by the inner join in
   budget_consolidation_inputs and named by assert_budget_period_declared. An unapproved Cycle's
   rows are not in the spine (they are not consolidated either). A table, rebuilt whole with the
   budget models; no orchestrator scope. Nothing here reads or is read by the close. #}

with {{ budget_consolidation_inputs() }},

{{ ownership_resolution_ctes('budget_periods', 'own_') }}

select * from own_resolution
