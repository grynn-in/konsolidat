{#
    F2: an entity must be a node of the consolidation tree exactly once.

    Consolidation Group's autoname is CG-{consolidation_group}-{data_area_id},
    so CG-GROUP_CORP-DEMF and CG-GROUP_EMEA-DEMF could coexist — and the live
    stack had exactly that shape after a stray `dbt seed`. Before F2 each node
    simply fed its own group. Now the ancestry closure emits a full chain per
    (ancestor, entity) pair for BOTH nodes, so any shared ancestor consolidates
    the entity twice, and gold_entity_ownership — which groups on (group,
    entity, period) — merges the two chains' links into a single meaningless
    product.

    konsol refuses this at save time
    (ConsolidationGroup._validate_entity_in_one_node); this catches data that
    predates the guard or arrived another way.
#}

select
    data_area_id,
    count() as nodes,
    groupArray(consolidation_group) as groups
from {{ source('epm_gold', 'consolidation_groups') }}
where data_area_id != ''
group by data_area_id
having count() > 1
