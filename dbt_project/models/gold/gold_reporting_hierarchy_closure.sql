{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, dimension, descendant_member_code, ancestor_member_code)',
        cluster=cluster_name()
    )
}}

{# Ancestor ↔ descendant bridge for every published hierarchy node. #}

with recursive closure as (
    select
        hierarchy_name,
        dimension,
        member_code as descendant_member_code,
        member_code as ancestor_member_code,
        hierarchy_level as ancestor_level,
        is_group as ancestor_is_group,
        member_label as ancestor_label,
        toUInt8(0) as depth
    from {{ ref('gold_reporting_hierarchy') }}

    union all

    select
        c.hierarchy_name,
        c.dimension,
        c.descendant_member_code,
        p.member_code as ancestor_member_code,
        p.hierarchy_level as ancestor_level,
        p.is_group as ancestor_is_group,
        p.member_label as ancestor_label,
        c.depth + 1 as depth
    from closure as c
    inner join {{ ref('gold_reporting_hierarchy') }} as n
        on n.hierarchy_name = c.hierarchy_name
        and n.dimension = c.dimension
        and n.member_code = c.ancestor_member_code
    inner join {{ ref('gold_reporting_hierarchy') }} as p
        on p.hierarchy_name = n.hierarchy_name
        and p.dimension = n.dimension
        and p.member_code = n.parent_member_code
    where n.parent_member_code != ''
      and c.depth < 20
)

select distinct
    hierarchy_name,
    dimension,
    descendant_member_code,
    ancestor_member_code,
    ancestor_level,
    ancestor_is_group,
    ancestor_label
from closure