-- PRD-8 Test: Hierarchy effective_ownership_pct must be between 0 and 100
select
    consolidation_group,
    data_area_id,
    effective_ownership_pct
from {{ ref('gold_consolidation_hierarchy') }}
where effective_ownership_pct < 0
   or effective_ownership_pct > 100
