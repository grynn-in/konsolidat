{#
    konsol#117 (design section 1): the Consolidation Group tree stays the
    reporting structure, the links say what is owned. The one rule tying them
    together: every non-root tree node is reached from its tree parent by at
    least one link path. Paths compose, so this local rule covers every ancestor.

    What "reached" reads as here:
      - an ENTITY node: epm_staging.consolidation_ancestry has a (tree parent
        group, entity) row — konsol's path enumeration writes one per path from
        each group node to each entity it reaches, so no row means no path;
      - a pure GROUP node (no entity): at least one Ownership Period names it as
        the owned node. The closure carries no rows for group nodes (a group is a
        destination, never a contributor), so which owner holds it is not checked
        here; konsol's validate refuses an owner outside the same root.

    A node with no path gives its tree ancestors nothing: its numbers never
    reach the consolidated result, silently. This fails the build naming it.

    Fixtures: assert_tree_node_reached_by_links.sql (pass), .must_flag.sql (flags 2:
    one unreached entity node, one unlinked group node).
#}

with nodes as (
    select
        consolidation_group,
        data_area_id,
        parent_group,
        path
    from {{ source('epm_staging', 'consolidation_hierarchy') }}
    where parent_group != ''
),

reached_entities as (
    select distinct
        consolidation_group as parent_group,
        data_area_id
    from {{ source('epm_staging', 'consolidation_ancestry') }}
    where consolidation_group != '' and data_area_id != ''
),

linked_nodes as (
    select distinct
        consolidation_group,
        data_area_id
    from {{ source('epm_staging', 'ownership_periods') }}
)

select
    n.consolidation_group,
    n.data_area_id,
    n.parent_group,
    n.path,
    concat(
        'Tree node ', n.path, ' is not reached from its parent ', n.parent_group,
        if(n.data_area_id != '',
           ' by any link path (no consolidation_ancestry row for the pair)',
           ' by any link (no Ownership Period names it as the owned node)'),
        ': its numbers never reach the consolidated result (konsol#117).'
    ) as message
from nodes as n
left join reached_entities as r
    on r.parent_group = n.parent_group
    and r.data_area_id = n.data_area_id
left join linked_nodes as l
    on l.consolidation_group = n.consolidation_group
    and l.data_area_id = n.data_area_id
where (n.data_area_id != '' and r.data_area_id = '')
   or (n.data_area_id = '' and l.consolidation_group = '')
