-- PRD-8 Test: No circular references — parent_group must not equal own consolidation_group
-- when parent_group is populated and data_area_id is empty (group node)
select
    consolidation_group,
    parent_group,
    path
from {{ ref('gold_consolidation_hierarchy') }}
where parent_group != ''
  and parent_group = consolidation_group
  and data_area_id = ''
