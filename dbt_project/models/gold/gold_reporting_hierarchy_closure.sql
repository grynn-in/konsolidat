{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, dimension, descendant_member_code, ancestor_member_code)',
        cluster=cluster_name()
    )
}}

{# Ancestor ↔ descendant bridge for every published hierarchy node.

   konsolidat#220: members are dated. A member row is one tranche of a code (member_effective_from ..
   member_effective_to); a renamed, moved or ended node is a second tranche of the same code. Each closure row
   holds only within a window (valid_from .. valid_to): the base row's window is the member tranche's own, and
   each step up joins the tranche(s) of the parent code whose window OVERLAPS the current one, narrowing the
   window to the intersection. The ancestor's level, group flag and label come from that parent tranche, so a
   rename gives one row per label, each with its own window. A reader picks the row whose window covers the
   date it asks about. #}

with recursive closure as (
    select
        hierarchy_name,
        dimension,
        member_code as descendant_member_code,
        member_code as ancestor_member_code,
        hierarchy_level as ancestor_level,
        is_group as ancestor_is_group,
        member_label as ancestor_label,
        parent_member_code as ancestor_parent_code,
        member_effective_from as valid_from,
        member_effective_to as valid_to,
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
        p.parent_member_code as ancestor_parent_code,
        greatest(c.valid_from, p.member_effective_from) as valid_from,
        least(c.valid_to, p.member_effective_to) as valid_to,
        c.depth + 1 as depth
    from closure as c
    inner join {{ ref('gold_reporting_hierarchy') }} as p
        on p.hierarchy_name = c.hierarchy_name
        and p.dimension = c.dimension
        and p.member_code = c.ancestor_parent_code
    where c.ancestor_parent_code != ''
      and p.member_effective_from <= c.valid_to
      and p.member_effective_to >= c.valid_from
      and c.depth < 20
)

select distinct
    hierarchy_name,
    dimension,
    descendant_member_code,
    ancestor_member_code,
    ancestor_level,
    ancestor_is_group,
    ancestor_label,
    valid_from,
    valid_to
from closure
