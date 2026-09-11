{#
    PRD-8 / F2: every entity node in the consolidation structure must be
    reachable by the tree walk.

    Was "every entity in the consolidation_groups SEED appears in the
    hierarchy". The seed is gone — it was the same ClickHouse relation konsol
    writes, so the test compared a table with itself whenever a governed build
    had re-seeded it. The structure table is the left side now, and the right
    side is the ancestry closure, which is what consolidation actually
    traverses: an entity missing from it reaches no group at all.
#}

select
    cg.consolidation_group,
    cg.data_area_id
from {{ source('epm_gold', 'consolidation_groups') }} as cg
left join (
    select distinct data_area_id
    from {{ source('epm_staging', 'consolidation_ancestry') }}
) as a
    on cg.data_area_id = a.data_area_id
where cg.data_area_id != ''
  and a.data_area_id is null
