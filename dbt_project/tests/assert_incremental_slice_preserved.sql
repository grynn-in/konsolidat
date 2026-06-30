-- A2 / grynn-in/konsolidat#116 Test: incremental-by-period materialization.
--
-- A scoped orchestrator close (entity_scope / fiscal_year / fiscal_period vars)
-- must update ONLY its own slice and leave every OTHER slice intact. Before A2
-- the four consolidation models were `table`-materialized, so a scoped run
-- OVERWROTE the whole table — zeroing every entity/year outside the close. A2
-- makes them `incremental` with `delete+insert` keyed on the close slice, so a
-- scoped run deletes+reinserts only the in-scope keys and preserves the rest.
-- This guard makes the old data-loss fail loudly.
--
-- OPT-IN via a DEDICATED var `assert_preserved_entity` — deliberately distinct
-- from the orchestrator's `entity_scope` so this guard never collides with the
-- A1 confinement guard (assert_scoped_cash_flow_ytd_confined). With no var it
-- returns no rows, so a normal full build always passes (byte-for-byte opt-in).
--
-- Usage (after a full build, then a scoped close on a DIFFERENT entity):
--   dbt run  --select <4 incremental models> --vars '{entity_scope: DEMF, fiscal_year: 2024}'
--   dbt test --select assert_incremental_slice_preserved --vars '{assert_preserved_entity: USMF}'
-- RED  (table mat — the scoped run wiped the table): USMF gone -> rows -> FAIL.
-- GREEN (incremental — USMF slice preserved):        USMF kept -> 0 rows -> PASS.
--
-- NOTE: gold_fully_consolidated_tb carries the kept entity in its UNSCOPED
-- acquisition/equity/topside layers too, so its entity-balance layer is isolated
-- with `adjustment_type = 'entity'` (the layer fed by the scoped chokepoint).
{%- set keep = var('assert_preserved_entity', '') -%}
{%- if keep is not none and (keep | string | trim) != '' -%}
{%- set e = (keep | string | trim) | replace("'", "''") %}
with preserved as (
    select 'gold_consolidated_trial_balance' as model, count(*) as kept_rows
    from {{ ref('gold_consolidated_trial_balance') }}
    where data_area_id = '{{ e }}'
    union all
    select 'gold_fully_consolidated_tb' as model, count(*) as kept_rows
    from {{ ref('gold_fully_consolidated_tb') }}
    where data_area_id = '{{ e }}' and adjustment_type = 'entity'
    union all
    select 'gold_cash_flow_indirect' as model, count(*) as kept_rows
    from {{ ref('gold_cash_flow_indirect') }}
    where data_area_id = '{{ e }}'
    union all
    select 'gold_ytd_trial_balance' as model, count(*) as kept_rows
    from {{ ref('gold_ytd_trial_balance') }}
    where data_area_id = '{{ e }}'
)
-- An out-of-scope entity that vanished from any incremental model is a row here.
select model, kept_rows
from preserved
where kept_rows = 0
{%- else -%}
-- No var: trivially pass (no rows).
select '' as model, toUInt64(0) as kept_rows
where 1 = 0
{%- endif -%}
