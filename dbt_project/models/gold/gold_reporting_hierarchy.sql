{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, dimension, member_code)',
        cluster=cluster_name()
    )
}}

select
    hierarchy_name,
    dimension,
    member_code,
    member_label,
    parent_member_code,
    toUInt8(is_group) as is_group,
    toUInt8(hierarchy_level) as hierarchy_level,
    path,
    effective_from,
    effective_to,
    toUInt8(is_default) as is_default
from {{ ref('reporting_hierarchies') }}
where status = 'Published'