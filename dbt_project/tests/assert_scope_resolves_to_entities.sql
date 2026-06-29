-- A1 / grynn-in/konsolidat#119 guard: an orchestrator scope close must resolve
-- to at least one entity. A misconfigured/unknown entity_scope code would match
-- nothing in gold_consolidation_hierarchy, so scope_filter would silently narrow
-- every consolidation model to ZERO rows and the close would "succeed" empty.
-- This guard makes that fail the (test-gated) governed build loudly instead.
--
-- OPT-IN: no entity_scope var => no rows (full build passes). With entity_scope
-- set it returns one row (=> failure) only when the code resolves to 0 entities.
{%- set scope = var('entity_scope', '') -%}
{%- if scope is not none and (scope | string | trim) != '' -%}
{%- set s = (scope | string | trim) | replace("'", "''") %}
select
    '{{ s }}' as unresolved_entity_scope,
    count(*) as resolved_entities
from {{ ref('gold_consolidation_hierarchy') }}
where data_area_id = '{{ s }}'
   or consolidation_group = '{{ s }}'
   or path = '{{ s }}'
   or path like '{{ s }}/%'
   or path like '%/{{ s }}/%'
   or path like '%/{{ s }}'
having count(*) = 0
{%- else -%}
-- No scope var: trivially pass (no rows).
select '' as unresolved_entity_scope, toUInt64(0) as resolved_entities
where 1 = 0
{%- endif -%}
