{# Group node amount must equal sum of descendant leaf amounts for the same slice. #}

with rolled as (
    select
        hierarchy_name,
        hierarchy_member_code,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        dim_cost_center,
        dim_department,
        period_net_amount
    from {{ ref('gold_tb_at_hierarchy_node') }}
),

groups as (
    select * from rolled
    where hierarchy_member_code in (
        select member_code
        from {{ ref('gold_reporting_hierarchy') }}
        where is_group = 1
    )
),

leaves as (
    select
        c.hierarchy_name as hierarchy_name,
        c.ancestor_member_code as hierarchy_member_code,
        r.data_area_id as data_area_id,
        r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period,
        r.main_account as main_account,
        r.dim_cost_center as dim_cost_center,
        r.dim_department as dim_department,
        sum(r.period_net_amount) as leaf_sum
    from rolled as r
    inner join {{ ref('gold_reporting_hierarchy_closure') }} as c
        on c.hierarchy_name = r.hierarchy_name
        and c.descendant_member_code = r.hierarchy_member_code
    inner join {{ ref('gold_reporting_hierarchy') }} as leaf
        on leaf.hierarchy_name = r.hierarchy_name
        and leaf.member_code = r.hierarchy_member_code
        and leaf.is_group = 0
    group by
        hierarchy_name,
        hierarchy_member_code,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        dim_cost_center,
        dim_department
)

select
    g.hierarchy_name,
    g.hierarchy_member_code,
    g.data_area_id,
    g.fiscal_year,
    g.fiscal_period,
    g.main_account,
    g.period_net_amount as group_amount,
    l.leaf_sum
from groups as g
inner join leaves as l using (
    hierarchy_name,
    hierarchy_member_code,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    dim_cost_center,
    dim_department
)
where abs(g.period_net_amount - l.leaf_sum) > 0.01