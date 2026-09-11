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

{# NOT a `left join ... where a.data_area_id is null`: with join_use_nulls=0 —
   which this project relies on throughout — an unmatched LEFT JOIN fills a
   non-nullable String with '', never NULL, so that form can return no rows at
   all and the test passes while entities are genuinely missing. #}
select
    consolidation_group,
    data_area_id
from {{ source('epm_gold', 'consolidation_groups') }}
where data_area_id != ''
  and data_area_id not in (
      select distinct data_area_id
      from {{ source('epm_staging', 'consolidation_ancestry') }}
  )
