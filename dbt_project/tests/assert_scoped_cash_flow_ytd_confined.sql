-- A1 / grynn-in/konsolidat#119 Test: under an orchestrator scope close, the
-- downstream cash-flow and YTD models must be confined to the scoped entities.
--
-- gold_cash_flow_indirect and gold_ytd_trial_balance ref('gold_trial_balance')
-- directly (they bypass the gold_consolidated_trial_balance chokepoint), so
-- before A1 a scoped close narrowed the consolidated TB but left these two full
-- of every entity. This test makes that drift fail loudly.
--
-- OPT-IN: with no entity_scope var this returns no rows (a normal full build
-- always passes). With entity_scope set it returns every row whose data_area_id
-- falls OUTSIDE the resolved scope (RED before the filters are applied, GREEN
-- after a scoped rebuild narrows both models).
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
offenders as (
    select 'gold_cash_flow_indirect' as model, data_area_id
    from {{ ref('gold_cash_flow_indirect') }}
    where data_area_id not in (select data_area_id from scoped_entities)
    union all
    select 'gold_ytd_trial_balance' as model, data_area_id
    from {{ ref('gold_ytd_trial_balance') }}
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
