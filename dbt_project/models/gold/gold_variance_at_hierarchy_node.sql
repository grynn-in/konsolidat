{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, hierarchy_member_code, data_area_id, fiscal_year, fiscal_period, main_account)',
        cluster=cluster_name()
    )
}}

with variance_long as (
    {{ variance_dimension_long_sql('v') }}
),

leaf_closure as (
    select
        c.hierarchy_name,
        c.dimension as hierarchy_dimension,
        c.ancestor_member_code as hierarchy_member_code,
        c.ancestor_level as hierarchy_level,
        c.ancestor_is_group as hierarchy_is_group,
        c.ancestor_label as hierarchy_member_label,
        c.descendant_member_code
    from {{ ref('gold_reporting_hierarchy_closure') }} as c
    inner join {{ ref('gold_reporting_hierarchy') }} as leaf
        on leaf.hierarchy_name = c.hierarchy_name
        and leaf.dimension = c.dimension
        and leaf.member_code = c.descendant_member_code
        and leaf.is_group = 0
)

select
    lc.hierarchy_name,
    lc.hierarchy_dimension,
    lc.hierarchy_member_code,
    lc.hierarchy_member_label,
    lc.hierarchy_level,
    lc.hierarchy_is_group,
    v.data_area_id,
    v.fiscal_year,
    v.fiscal_period,
    v.main_account,
    {% for d in get_budget_dimensions() %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', v.{{ d.name }}) as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %},
    {{ variance_measure_sums('v.') }}
from variance_long as v
inner join leaf_closure as lc
    on lc.hierarchy_dimension = v.hierarchy_dimension
    and lc.descendant_member_code = v.dimension_member_code
group by
    lc.hierarchy_name,
    lc.hierarchy_dimension,
    lc.hierarchy_member_code,
    lc.hierarchy_member_label,
    lc.hierarchy_level,
    lc.hierarchy_is_group,
    v.data_area_id,
    v.fiscal_year,
    v.fiscal_period,
    v.main_account,
    {% for d in get_budget_dimensions() %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', v.{{ d.name }}){{ ',' if not loop.last }}
    {%- endfor %}