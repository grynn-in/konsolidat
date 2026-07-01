{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, hierarchy_member_code, data_area_id, fiscal_year, fiscal_period, main_account, layer)',
        cluster=cluster_name()
    )
}}

{# Budget amounts rolled up to reporting hierarchy nodes (leaf input, group read). #}

with budget_long as (
    {{ budget_dimension_long_sql('b') }}
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
    b.scenario_id,
    b.data_area_id,
    b.fiscal_year,
    b.fiscal_period,
    b.main_account,
    {# Budget layer preserved through the rollup so hierarchy reads can filter to
       one layer (base/challenge/management/board); omitting the filter sums all
       layers = the final budget, matching the flat path (grynn-in/konsol#63). #}
    b.layer,
    {% for d in get_budget_dimensions() %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', b.{{ d.name }}) as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %},
    sum(b.period_amount) as period_amount,
    sum(b.annual_amount) as annual_amount
from budget_long as b
inner join leaf_closure as lc
    on lc.hierarchy_dimension = b.hierarchy_dimension
    and lc.descendant_member_code = b.dimension_member_code
group by
    lc.hierarchy_name,
    lc.hierarchy_dimension,
    lc.hierarchy_member_code,
    lc.hierarchy_member_label,
    lc.hierarchy_level,
    lc.hierarchy_is_group,
    b.scenario_id,
    b.data_area_id,
    b.fiscal_year,
    b.fiscal_period,
    b.main_account,
    b.layer,
    {% for d in get_budget_dimensions() %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', b.{{ d.name }}){{ ',' if not loop.last }}
    {%- endfor %}