-- PRD-ALLOCATED-LAYER PR1: gold deprecation views must match ACTUAL alloc rows
select
    'row_count_mismatch' as error
from (
    select count(*) as alloc_count
    from {{ ref('alloc_results') }}
    where scenario_id = 'ACTUAL'
) as a
cross join (
    select count(*) as gold_count
    from {{ ref('gold_allocation_results') }}
) as g
where a.alloc_count != g.gold_count