-- A3 / grynn-in/konsolidat: reconcile A1 confinement with A2 incremental semantics.
--
-- A1 (#119) asserted that under an orchestrator scope close every row in the WHOLE
-- persisted gold_cash_flow_indirect / gold_ytd_trial_balance table was confined to
-- the scoped entities. That whole-table invariant became FALSE once A2 (#116) made
-- both models `incremental` (delete+insert keyed on the close slice): a scoped
-- close now rewrites ONLY the in-scope entity's keys and PRESERVES every other
-- entity's slice BY DESIGN. So after e.g. a DEMF/2024 close, sibling entities
-- (USMF, GLMF, ...) legitimately remain in the table — and even within fiscal_year
-- 2024 (30 siblings share that year) — so the old whole-table scan false-fails
-- (122 offending groups). Period-bounding the persisted-table scan does NOT fix
-- it: the preserved siblings live in the same period. Entity presence in the
-- persisted table simply cannot tell a freshly-closed row from a preserved one.
--
-- REAL invariant: the FRESHLY-WRITTEN slice — the rows the close actually
-- (re)derives and delete+inserts — must be confined to the resolved scope. That
-- slice is the model's SOURCE projection: gold_trial_balance filtered by the SAME
-- period_filter + scope_filter predicates the model applies. We check that
-- pre-persist projection here (per the handoff's "check the SELECT pre-persist"
-- reconciliation), which is robust to incremental preservation of sibling slices.
-- If scope_filter ever over-selected an out-of-scope entity, that entity would be
-- written into the close slice and would surface as an offender below.
--
-- The two CTEs mirror each model's WHERE clause exactly (do NOT call the macros in
-- a SQL comment — Jinja still renders them and their multi-line output breaks out
-- of the `--` line):
--   gold_cash_flow_indirect: where fiscal_period > 0  + period_filter() + scope_filter()
--   gold_ytd_trial_balance:  where 1 = 1  + period_filter(include_period=false) + scope_filter()
-- (YTD uses include_period=false: the running sum needs every prior period of the
-- closed year, so only the year is bounded — matching the model.)
--
-- OPT-IN: with no entity_scope var this returns no rows (a normal full build always
-- passes, byte-for-byte). With entity_scope set it returns every entity a model's
-- scoped source projection selects that falls OUTSIDE the independently-resolved
-- scope (RED before A1's filters narrowed the models; GREEN once the freshly-closed
-- slice is confined to scope).
{%- set scope = var('entity_scope', '') -%}
{%- if scope is not none and (scope | string | trim) != '' -%}
{%- set s = (scope | string | trim) | replace("'", "''") %}
with scoped_entities as (
    select data_area_id
    from {{ ref('gold_consolidation_hierarchy') }}
    where data_area_id = '{{ s }}'
       or consolidation_group = '{{ s }}'
       or path = '{{ s }}'
       or path like '{{ s }}/%'
       or path like '%/{{ s }}/%'
       or path like '%/{{ s }}'
),
-- Freshly-written slice fed to gold_cash_flow_indirect (per-period: period_filter
-- applies year AND single period).
cash_flow_slice as (
    select distinct data_area_id
    from {{ ref('gold_trial_balance') }}
    where fiscal_period > 0
        {{ period_filter() }}
        {{ scope_filter() }}
),
-- Freshly-written slice fed to gold_ytd_trial_balance (cumulative: period_filter
-- bounds the year only, suppressing the single-period predicate).
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
from offenders
group by model, data_area_id
{%- else -%}
-- No scope var: trivially pass (no rows).
select '' as model, '' as data_area_id, toUInt64(0) as offending_rows
where 1 = 0
{%- endif -%}
