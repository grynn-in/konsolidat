-- A3 / grynn-in/konsolidat: confine the FRESHLY-WRITTEN slice of a scoped close.
--
-- A1 (#119) asserted that under an orchestrator scope close every row in the WHOLE
-- persisted gold_cash_flow_indirect / gold_ytd_trial_balance table was confined to
-- the scoped entities. A2 (#116) then made both models `incremental` (rewriting
-- only the close slice; since #154 a pre_hook deletes it and the SELECT appends
-- it), so a scoped close rewrites ONLY the in-scope entity's
-- keys and PRESERVES every other entity's prior rows BY DESIGN. The whole-table
-- invariant therefore became false and the A1 test false-failed (122 retained rows).
--
-- REAL invariant checked here: the FRESHLY-WRITTEN slice — the rows the close
-- actually (re)derives and writes — must be confined to the resolved scope.
-- That slice IS each model's SOURCE projection: gold_trial_balance filtered by the
-- SAME period_filter + scope_filter predicates the model applies (cash-flow:
-- single-period; YTD: include_period=false, year-bounded). We check that pre-persist
-- projection (the handoff's "check the SELECT pre-persist" reconciliation), which is
-- robust to A2's incremental preservation of out-of-scope sibling slices and needs
-- NO write-time marker — so the gold contract tables stay byte-for-byte unchanged.
--
-- NON-VACUOUS via an INDEPENDENT oracle. The genuine weakness of the first A3 cut
-- (commit 9ad34db) was NOT the source-projection — it was the oracle: it resolved
-- `scoped_entities` from gold_consolidation_hierarchy with the SAME LIKE/path
-- patterns scope_filter uses, so the projection was a subset of the oracle BY
-- CONSTRUCTION and an offender could never appear (a tautology). Here the oracle is
-- resolved INDEPENDENTLY from the flat consolidation_groups seed with EXACT equality
-- only (no LIKE, no `path`, no hierarchy), so if scope_filter ever OVER-SELECTS
-- (e.g. an unescaped `_`/`%` LIKE metacharacter, a lost slash boundary, a widened
-- predicate) it pulls an entity into the projection that the exact-equality oracle
-- does not contain, and that entity surfaces below as an offender. RED reachable:
-- broadening scope_filter (e.g. adding an extra `or data_area_id = ...`) under a
-- resolvable scope makes the over-selected entity an offender; GREEN once the macro
-- selects exactly the scope.
--
-- The oracle resolves an ENTITY scope (matches itself) or ANY consolidation
-- group, top-level or intermediate, to every entity that rolls into it — the
-- ancestry closure carries one row per (ancestor group, entity), so a sub-group
-- needs no special case. An unresolvable scope yields an empty oracle and the
-- check is suppressed rather than false-failing; a genuinely bogus/zero-entity
-- scope is already guarded by assert_scope_resolves_to_entities.
--
-- F2 removed the previous ASSUMPTION (konsolidat#124) that the flat seed and the
-- hierarchy agree on top-level group membership. They did not — the seed put
-- DEMF and GBMF under GROUP_CORP, the doctype under GROUP_EMEA (#130) — and the
-- seed is gone. Oracle and macro now read the same tree by two different
-- mechanisms: a parent-link closure here, a path-string LIKE there.
--
-- Tradeoff (vs. the rejected write-time marker): this guards against the scope_filter
-- MACRO over-selecting, not against a model dropping the scope_filter call entirely.
-- The latter would need a persisted load marker on the gold tables, which violates
-- the no-var byte-for-byte invariant; all three consolidation models share the same
-- chokepoint filter pattern and that is covered by review.
--
-- (Do NOT call period_filter()/scope_filter() inside a `--` comment: Jinja renders
-- the macro and its multi-line output breaks out of the comment line.)
--
-- OPT-IN: with no entity_scope var this returns no rows (full build byte-for-byte
-- unchanged).
{%- set scope = var('entity_scope', '') -%}
{%- if scope is not none and (scope | string | trim) != '' -%}
{%- set s = (scope | string | trim) | replace("'", "''") %}
with scoped_entities as (
    -- Independent oracle: the ancestry closure, EXACT equality only. A scope
    -- code is either a consolidation group (every entity that rolls into it, at
    -- any depth) or an entity data_area_id (matches itself). Still no LIKE and
    -- no `path` — scope_filter resolves descendants by matching the
    -- materialised path string, this resolves them from a closure konsol builds
    -- by walking parent links — so the projection is not a subset of the oracle
    -- by construction and an over-selecting macro still surfaces below.
    --
    -- F2 replaced the flat consolidation_groups seed here. That seed listed
    -- DEMF and GBMF under GROUP_CORP while the real tree puts them under
    -- GROUP_EMEA, and the header above recorded the resulting assumption ("the
    -- flat seed and gold_consolidation_hierarchy AGREE on TOP-LEVEL group
    -- membership… that divergence is itself the bug tracked in #130"). Reading
    -- the structure table directly made that divergence the normal case: a
    -- GROUP_CORP close would have pulled DEMF and GBMF in through `path` while
    -- the oracle held only USMF and JPMF, and both would have false-failed.
    -- The closure resolves an INTERMEDIATE sub-group too, so the suppression
    -- clause below is now only reached for a scope that resolves to nothing.
    select data_area_id
    from {{ source('epm_staging', 'consolidation_ancestry') }}
    where consolidation_group = '{{ s }}' and data_area_id != ''
    union distinct
    select data_area_id
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = '{{ s }}' and data_area_id != ''
),
-- Source projection fed to gold_cash_flow_indirect (per-period: period_filter
-- applies year AND single period; matches the model's WHERE exactly).
cash_flow_slice as (
    select distinct data_area_id
    from {{ ref('gold_trial_balance') }}
    where fiscal_period > 0
        {{ period_filter() }}
        {{ scope_filter() }}
),
-- Source projection fed to gold_ytd_trial_balance (cumulative: period_filter bounds
-- the year only, suppressing the single-period predicate; matches the model).
ytd_slice as (
    select distinct data_area_id
    from {{ ref('gold_trial_balance') }}
    where 1 = 1
        {{ period_filter(include_period=false) }}
        {{ scope_filter() }}
),
offenders as (
    select 'gold_cash_flow_indirect' as model, data_area_id
    from cash_flow_slice
    where data_area_id not in (select data_area_id from scoped_entities)
    union all
    select 'gold_ytd_trial_balance' as model, data_area_id
    from ytd_slice
    where data_area_id not in (select data_area_id from scoped_entities)
)
select model, data_area_id, count(*) as offending_rows
-- Suppress only when the seed can't independently resolve this scope (intermediate
-- sub-group): no oracle => can't adjudicate => don't false-fail. Resolvable scopes
-- (entity or top-level group) are always checked.
from offenders
where (select count(*) from scoped_entities) > 0
group by model, data_area_id
{%- else -%}
-- No scope var: trivially pass (no rows).
select '' as model, '' as data_area_id, toUInt64(0) as offending_rows
where 1 = 0
{%- endif -%}
