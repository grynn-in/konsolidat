{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        full_refresh=false,
        pre_hook=[
            "{% if is_incremental() %}DELETE FROM {{ this }} WHERE run NOT IN (SELECT name FROM {{ source('epm_staging', 'cost_allocation_runs') }}){% endif %}"
        ],
        engine='MergeTree()',
        order_by='(run, sender_member)'
    )
}}

-- Absorption variance of runs frozen at approval (konsol#269 2b-2 W7): the twin of
-- gold_cost_allocation_absorption for runs with amounts_after_approval = 'Freeze at
-- Approval', built the way gold_cost_allocation_frozen is. A Freeze run is computed
-- ONCE, the first build after it appears in staging, stamped frozen_at = now(), and
-- never recomputed, so the pool is the sender's trial balance AT APPROVAL and a later
-- change to the trial balance does not move the variance
-- (assert_cost_allocation_absorption_frozen_drift reports the difference). Its received
-- lines are read from gold_cost_allocation_frozen, which the same build appended, so
-- the row and its lines agree; the two frozen_at stamps are seconds apart.
--
-- Incremental strategy: `append` plus a pre_hook DELETE of the rows whose run left
-- epm_staging.cost_allocation_runs (cancelled), and a SELECT restricted to Freeze runs
-- with no row here yet, so an existing frozen run is left untouched (the reasoning is
-- in gold_cost_allocation_frozen.sql). full_refresh=false: `dbt build --full-refresh`
-- cannot re-freeze approved runs at current data; a re-freeze of one run is a cancel
-- and a re-approval. on_schema_change='fail': a column change needs a manual DROP,
-- which discards every frozen variance. This table is new with 2b-2, so it has no
-- upgrade pre_hooks: no row of it predates its shape.
-- It must not ref gold_cost_allocation_absorption (which unions this table): a cycle.
{{ cost_allocation_absorption(
    runs_predicate="r.amounts_after_approval = 'Freeze at Approval'"
        ~ ((" and r.name not in (select run from " ~ this ~ ")") if is_incremental() else ""),
    lines_relation=ref('gold_cost_allocation_frozen'),
    frozen_at_expr="cast(now() as Nullable(DateTime))"
) }}
