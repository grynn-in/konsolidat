{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-8: Multi-level consolidation hierarchy
   Reads from staging table when available, falls back to consolidation_groups seed
   for backward compatibility (flat hierarchy, level=1) #}

with staging_hierarchy as (
    select
        consolidation_group,
        data_area_id,
        parent_group,
        hierarchy_level,
        effective_ownership_pct,
        path
    from {{ source('epm_staging', 'consolidation_hierarchy') }}
),

{# Fallback: derive flat hierarchy from existing seed #}
seed_fallback as (
    select
        consolidation_group,
        data_area_id,
        '' as parent_group,
        toUInt8(1) as hierarchy_level,
        ownership_pct as effective_ownership_pct,
        concat(consolidation_group, '/', data_area_id) as path
    from {{ ref('consolidation_groups') }}
),

{# Use staging if populated, otherwise fall back to seed #}
hierarchy as (
    select * from staging_hierarchy
    where consolidation_group != ''

    union all

    select sf.*
    from seed_fallback as sf
    where not exists (
        select 1 from staging_hierarchy as sh
        where sh.consolidation_group != ''
        limit 1
    )
)

select
    consolidation_group,
    data_area_id,
    parent_group,
    hierarchy_level,
    effective_ownership_pct,
    path
from hierarchy
where data_area_id != ''
