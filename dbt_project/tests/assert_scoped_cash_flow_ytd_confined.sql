-- A3 / grynn-in/konsolidat: confine the FRESHLY-WRITTEN slice of a scoped close.
--
-- A1 (#119) asserted that under an orchestrator scope close every row in the WHOLE
-- persisted gold_cash_flow_indirect / gold_ytd_trial_balance table was confined to
-- the scoped entities. A2 (#116) then made both models `incremental` (delete+insert
-- keyed on the close slice), so a scoped close rewrites ONLY the in-scope entity's
-- keys and PRESERVES every other entity's prior rows BY DESIGN. The whole-table
-- invariant therefore became false and the A1 test false-failed.
--
-- The review-1 fix replaced a re-derived-from-source check (which was a logical
-- tautology — it re-ran the SAME scope_filter resolution on both sides, never read
-- the actual models, and so could NEVER surface an offender) with a check on the
-- ACTUAL model output. Two structural facts make this possible and non-vacuous:
--
--   1. We read the real models (ref(gold_cash_flow_indirect)/ref(gold_ytd_trial_balance)),
--      so a model that DROPS scope_filter and writes out-of-scope entities into the
--      close is now observable here (the old test re-projected a clean slice from
--      gold_trial_balance and was decoupled from the models entirely).
--
--   2. delete+insert is deterministic, so a preserved sibling and a freshly-leaked
--      sibling are byte-identical on persisted state — they cannot be told apart by
--      reading the table. We therefore isolate THIS run's freshly-written rows with
--      the `_close_scope` load marker the models stamp at write time
--      (close_scope_marker() = the run's entity_scope; '' on a full build). Only
--      rows this scoped close actually wrote carry the marker; A2-preserved siblings
--      carry '' (or a prior scope) and are correctly ignored.
--
-- The scope oracle is resolved INDEPENDENTLY from the consolidation_groups seed
-- (the flat parent->entity source of truth), NOT from gold_consolidation_hierarchy
-- or the scope_filter macro, and uses EXACT equality (no LIKE patterns). So it is
-- not a superset-by-construction of the macro's selection: if the macro ever
-- over-selected (e.g. an unescaped `_` LIKE wildcard) the extra entity would be
-- stamped into the close yet absent from the oracle, and surface as an offender.
--
-- REACHABLE RED (verified): strip scope_filter from either model and run a scoped
-- DEMF/2024 close — the model stamps `_close_scope='DEMF'` onto every 2024 entity,
-- the seed oracle resolves to {DEMF}, and the out-of-scope siblings surface here.
-- GREEN once the model confines its write to the scope. OPT-IN: with no entity_scope
-- var the marker is '' on both sides and this returns no rows (full build unchanged).
{%- set scope = (var('entity_scope', '') | string | trim) -%}
{%- if scope != '' %}
{%- set s = scope | replace("'", "''") %}
with scoped_entities as (
    -- Independent oracle: flat consolidation_groups seed. A scope code is either a
    -- consolidation group (expand to its member entities) or an entity (itself).
    -- Exact equality only — no hierarchy path / LIKE resolution shared with the macro.
    select data_area_id
    from {{ ref('consolidation_groups') }}
    where consolidation_group = '{{ s }}'
       or data_area_id = '{{ s }}'
),
offenders as (
    -- Rows THIS scoped close freshly wrote (marker = the run's scope) that fall
    -- outside the independently-resolved scope.
    select 'gold_cash_flow_indirect' as model, data_area_id
    from {{ ref('gold_cash_flow_indirect') }}
    where _close_scope = {{ close_scope_marker() }}
      and data_area_id not in (select data_area_id from scoped_entities)
    union all
    select 'gold_ytd_trial_balance' as model, data_area_id
    from {{ ref('gold_ytd_trial_balance') }}
    where _close_scope = {{ close_scope_marker() }}
      and data_area_id not in (select data_area_id from scoped_entities)
)
select model, data_area_id, count(*) as offending_rows
from offenders
group by model, data_area_id
{%- else -%}
-- No scope var: trivially pass (no rows).
select '' as model, '' as data_area_id, toUInt64(0) as offending_rows
where 1 = 0
{%- endif -%}
