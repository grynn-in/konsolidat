{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, hierarchy_member_code, data_area_id, fiscal_year, fiscal_period, main_account)',
        cluster=cluster_name()
    )
}}

{# konsolidat#206: gold_variance_analysis carries one set of rows per active
   budget-type scenario (budget_scenario_id), the actuals repeated against
   each. Grouping without it counted the actuals once per budget scenario and
   added the budgets together, so every node row is per budget scenario.

   konsolidat#220: the tree is resolved per period, as in gold_tb_at_hierarchy_node. A variance row joins only
   the leaf tranche and the closure rows whose windows cover its period's end_date (declared calendar,
   epm_staging.fiscal_periods; a period the calendar does not list is judged at the last day of its month). #}

with variance_long as (
    {{ variance_dimension_long_sql('v') }}
),

periods as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        max(end_date) as end_date
    from {{ source('epm_staging', 'fiscal_periods') }}
    group by fiscal_year, fiscal_period
),

variance_dated as (
    select
        v.*,
        {# an unmatched LEFT JOIN row carries Date's default (1970-01-01), not NULL #}
        if(
            p.end_date = toDate(0),
            toLastDayOfMonth({{ build_date_from_year_period('v.fiscal_year', 'v.fiscal_period') }}),
            p.end_date
        ) as period_end_date
    from variance_long as v
    left join periods as p
        on p.fiscal_year = toUInt16(v.fiscal_year)
        and p.fiscal_period = toUInt16(v.fiscal_period)
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
    {# aliased: variance_long has hierarchy_dimension too, and ClickHouse would
       name the duplicated column `lc.hierarchy_dimension` #}
    lc.hierarchy_dimension as hierarchy_dimension,
    lc.hierarchy_member_code,
    lc.hierarchy_member_label,
    lc.hierarchy_level,
    lc.hierarchy_is_group,
    v.data_area_id,
    v.fiscal_year,
    v.fiscal_period,
    v.main_account,
    v.budget_scenario_id,
    {% for d in get_budget_dimensions() %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', v.{{ d.name }}) as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %}{{ ',' if get_budget_dimensions() | length > 0 }}
    {{ variance_measure_sums('v.') }}
from variance_dated as v
inner join leaf_closure as lc
    on lc.hierarchy_dimension = v.hierarchy_dimension
    and lc.descendant_member_code = v.dimension_member_code
{# the leaf tranche and the closure link that hold on the period's end_date #}
where v.period_end_date >= lc.leaf_effective_from
  and v.period_end_date <= lc.leaf_effective_to
  and v.period_end_date >= lc.valid_from
  and v.period_end_date <= lc.valid_to
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
    v.budget_scenario_id
    {{- ',' if get_budget_dimensions() | length > 0 }}
    {% for d in get_budget_dimensions() %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', v.{{ d.name }}){{ ',' if not loop.last }}
    {%- endfor %}