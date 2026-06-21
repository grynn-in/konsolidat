{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_dimension, dimension_member_code)',
        cluster=cluster_name()
    )
}}

{# GL dimension values not assigned to any leaf in the default published hierarchy. #}

with tb_long as (
    {{ tb_dimension_long_sql('tb') }}
),

default_hierarchies as (
    select hierarchy_name, dimension
    from {{ ref('gold_reporting_hierarchy') }}
    where is_default = 1
    group by hierarchy_name, dimension
),

hierarchy_leaves as (
    select
        h.hierarchy_name,
        h.dimension,
        h.member_code
    from {{ ref('gold_reporting_hierarchy') }} as h
    inner join default_hierarchies as d
        on d.hierarchy_name = h.hierarchy_name
        and d.dimension = h.dimension
    where h.is_group = 0
)

select distinct
    tb.hierarchy_dimension,
    d.hierarchy_name as default_hierarchy_name,
    tb.dimension_member_code
from tb_long as tb
inner join default_hierarchies as d
    on d.dimension = tb.hierarchy_dimension
left anti join hierarchy_leaves as hl
    on hl.hierarchy_name = d.hierarchy_name
    and hl.dimension = tb.hierarchy_dimension
    and hl.member_code = tb.dimension_member_code