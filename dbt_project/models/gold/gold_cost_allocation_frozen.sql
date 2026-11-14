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
-- before the INSERT. A run cancelled and re-submitted under the same name is
-- frozen afresh only if a build ran between the cancel and the re-submit; if
-- not, its old rows are still here under that name and are kept. An amend gets a
-- new name, so it is frozen afresh whatever the build order.
--
-- full_refresh=false: `dbt build --full-refresh` skips the rebuild of this table
-- (dbt treats the model as a normal incremental run), so it cannot re-freeze
-- approved runs at current data (W5b; fixture
-- assert_cost_allocation_frozen_drift.full_refresh.must_flag). A deliberate
-- re-freeze of one run means cancelling and re-approving it: the cancel removes its
-- rows (pre_hook above), the new approval is frozen afresh. A column change needs a
-- manual DROP of this table, which discards every frozen amount.
-- It must not ref gold_cost_allocation (which unions this table): that is a cycle.
{{ cost_allocation_lines(
    runs_predicate="r.amounts_after_approval = 'Freeze at Approval'"
        ~ ((" and r.name not in (select run from " ~ this ~ ")") if is_incremental() else ""),
    frozen_at_expr="cast(now() as Nullable(DateTime))"
) }}
