{#
    konsol#117 (design section 3): a path from a group to an entity never visits
    a node twice. konsol refuses a cycle at Ownership Period validate and
    build_rows raises on one; this is the warehouse backstop for a closure row
    that slipped past both (a patch, a hand-written row). One result per cyclic
    path, naming it. `path` (the tree path, kept for readers) is checked too, so a
    volume whose closure predates path_id is covered.

    Fixture: assert_ownership_paths_acyclic.must_flag.sql seeds ZZA/ZZB/ZZA (flags 1).
#}

select
    consolidation_group,
    data_area_id,
    path_id,
    path,
    concat(
        'Path ', if(path_id != '', path_id, path), ' from ', consolidation_group, ' to ', data_area_id,
        ' visits a node twice. Cross-holdings are refused until a treasury-share rule is decided (konsol#117).'
    ) as message
from {{ source('epm_staging', 'consolidation_ancestry') }}
where length(splitByChar('/', path_id)) != length(arrayDistinct(splitByChar('/', path_id)))
   or length(splitByChar('/', path)) != length(arrayDistinct(splitByChar('/', path)))
group by consolidation_group, data_area_id, path_id, path
