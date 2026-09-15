{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, hierarchy_member_code, data_area_id, fiscal_year, fiscal_period, main_account, layer)',
        cluster=cluster_name()
    )
}}

{# Budget amounts rolled up to reporting hierarchy nodes (leaf input, group read).

   konsolidat#220: the tree is resolved per period, as in gold_tb_at_hierarchy_node. A budget row joins only the
   leaf tranche and the closure rows whose windows cover its period's end_date (declared calendar,
   epm_staging.fiscal_periods; a period the calendar does not list is judged at the last day of its month). #}

with budget_long as (
    {{ budget_dimension_long_sql('b') }}
),

periods as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        max(end_date) as end_date
    from {{ source('epm_staging', 'fiscal_periods') }}
    group by fiscal_year, fiscal_period
),

budget_dated as (
    select
        b.*,
        {# an unmatched LEFT JOIN row carries Date's default (1970-01-01), not NULL #}
        if(
            p.end_date = toDate(0),
            toLastDayOfMonth({{ build_date_from_year_period('b.fiscal_year', 'b.fiscal_period') }}),
            p.end_date
        ) as period_end_date
    from budget_long as b
    left join periods as p
        on p.fiscal_year = toUInt16(b.fiscal_year)
        and p.fiscal_period = toUInt16(b.fiscal_period)
),

leaf_closure as (
    select
        c.hierarchy_name,
        c.dimension as hierarchy_dimension,
        c.ancestor_member_code as hierarchy_member_code,
        c.ancestor_level as hierarchy_level,
        c.ancestor_is_group as hierarchy_is_group,
        c.ancestor_label as hierarchy_member_label,
        c.descendant_member_code,
        c.valid_from,
        c.valid_to,
        leaf.member_effective_from as leaf_effective_from,
        leaf.member_effective_to as leaf_effective_to
    from {{ ref('gold_reporting_hierarchy_closure') }} as c
    inner join {{ ref('gold_reporting_hierarchy') }} as leaf
        on leaf.hierarchy_name = c.hierarchy_name
        and leaf.dimension = c.dimension
        and leaf.member_code = c.descendant_member_code
        and leaf.is_group = 0
)

select
    lc.hierarchy_name,
    lc.hierarchy_dimension as hierarchy_dimension,
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
from budget_dated as b
inner join leaf_closure as lc
    on lc.hierarchy_dimension = b.hierarchy_dimension
    and lc.descendant_member_code = b.dimension_member_code
{# the leaf tranche and the closure link that hold on the period's end_date #}
where b.period_end_date >= lc.leaf_effective_from
  and b.period_end_date <= lc.leaf_effective_to
  and b.period_end_date >= lc.valid_from
  and b.period_end_date <= lc.valid_to
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