-- PRD-8 Test: Every entity in consolidation_groups seed must appear in hierarchy
select
    cg.data_area_id
from {{ ref('consolidation_groups') }} as cg
left join {{ ref('gold_consolidation_hierarchy') }} as h
    on cg.consolidation_group = h.consolidation_group
    and cg.data_area_id = h.data_area_id
where h.data_area_id is null
