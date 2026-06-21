{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, hierarchy_member_code, data_area_id, fiscal_year, fiscal_period, main_account)',
        cluster=cluster_name()
    )
}}

{# Trial balance rolled up to any node in a reporting hierarchy. #}

with tb_long as (
    {{ tb_dimension_long_sql('tb') }}
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
    tb.data_area_id,
    tb.fiscal_year,
    tb.fiscal_period,
    tb.main_account,
    tb.account_name,
    tb.account_type_name,
    tb.is_balance_sheet,
    tb.is_pnl,
    {% for d in var('dimensions') %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', tb.{{ d.name }}) as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %},
    {{ hierarchy_measure_sums('tb.') }}
from tb_long as tb
inner join leaf_closure as lc
    on lc.hierarchy_dimension = tb.hierarchy_dimension
    and lc.descendant_member_code = tb.dimension_member_code
group by
    lc.hierarchy_name,
    lc.hierarchy_dimension,
    lc.hierarchy_member_code,
    lc.hierarchy_member_label,
    lc.hierarchy_level,
    lc.hierarchy_is_group,
    tb.data_area_id,
    tb.fiscal_year,
    tb.fiscal_period,
    tb.main_account,
    tb.account_name,
    tb.account_type_name,
    tb.is_balance_sheet,
    tb.is_pnl,
    {% for d in var('dimensions') %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', tb.{{ d.name }}){{ ',' if not loop.last }}
    {%- endfor %}