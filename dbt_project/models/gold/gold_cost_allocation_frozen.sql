{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        pre_hook=[
            "{% if is_incremental() %}DELETE FROM {{ this }} WHERE run NOT IN (SELECT name FROM {{ source('epm_staging', 'cost_allocation_runs') }}){% endif %}"
        ],
        engine='MergeTree()',
        order_by='(run, origin_member, step, sender_member, receiver_member, line_type)'
    )
}}

-- Cost allocation lines of runs frozen at approval (konsol#269, W5): a run with
-- amounts_after_approval = 'Freeze at Approval' is computed ONCE, the first
-- build after it appears in staging, stamped frozen_at = now(), and never
-- recomputed, so a later change to the trial balance does not move it
-- (assert_cost_allocation_frozen_drift, W6, reports the difference).
--
-- Incremental strategy: `append` plus a pre_hook DELETE, not `delete+insert`.
-- delete+insert deletes only the keys of the rows it is about to insert, so it
-- could never remove a cancelled run (it has no new rows), and it would replace
-- a frozen run whenever one reappeared in the SELECT. Here the pre_hook removes
-- the rows of runs no longer in epm_staging.cost_allocation_runs (cancelled),
-- and the SELECT is restricted to Freeze runs with no row in this table yet, so
-- an existing frozen run is left untouched. Within one build the DELETE runs
-- before the INSERT, so a run cancelled and re-submitted under the same name is
-- frozen afresh.
--
-- A --full-refresh rebuilds the table, so it freezes every run again at the
-- current data. Do not full-refresh this model on a site with approved runs.
-- It must not ref gold_cost_allocation (which unions this table): that is a cycle.
{{ cost_allocation_lines(
    runs_predicate="r.amounts_after_approval = 'Freeze at Approval'"
        ~ ((" and r.name not in (select run from " ~ this ~ ")") if is_incremental() else ""),
    frozen_at_expr="cast(now() as Nullable(DateTime))"
) }}
