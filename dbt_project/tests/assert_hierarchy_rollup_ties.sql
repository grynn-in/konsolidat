{# A group node's amount must equal the sum of its descendant leaves for the same slice: hierarchy, node, entity,
   period, account and every other dimension. Compared per account, not per node total: a voucher that balances
   inside one dimension value nets a node's total to 0, and a totals-only check would pass on a wrong rollup.

   konsolidat#220: the tree is resolved per period. A leaf row of gold_tb_at_hierarchy_node counts towards a group
   only through the closure link whose window (valid_from .. valid_to) covers the period's end_date (declared
   calendar, epm_staging.fiscal_periods; a period the calendar does not list is judged at the last day of its
   month). So a moved leaf is counted once, under the parent it had then, and an ended group gets nothing later.

   Both sides are stacked and summed per key, so a group row with no leaves and leaves with no group row both
   show as a difference. Output aliases differ from the joined columns' names: ClickHouse strips the qualifier
   from the left table's columns in a join, so a same-named alias would shadow them. #}

{% set slice_cols = ['data_area_id', 'fiscal_year', 'fiscal_period', 'main_account'] %}
{% for d in var('dimensions') %}{% do slice_cols.append(d.name) %}{% endfor %}

with rolled as (
    select
        hierarchy_name,
        hierarchy_dimension,
        hierarchy_member_code,
        hierarchy_is_group,
        {% for col in slice_cols %}
        {{ col }},
        {%- endfor %}
        toFloat64(period_net_amount) as amount
    from {{ ref('gold_tb_at_hierarchy_node') }}
),

periods as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        max(end_date) as end_date
    from {{ source('epm_staging', 'fiscal_periods') }}
    group by fiscal_year, fiscal_period
),

leaf_rows as (
    select
        r.*,
        {# an unmatched LEFT JOIN row carries Date's default (1970-01-01), not NULL #}
        if(
            p.end_date = toDate(0),
            toLastDayOfMonth({{ build_date_from_year_period('r.fiscal_year', 'r.fiscal_period') }}),
            p.end_date
        ) as period_end_date
    from rolled as r
    left join periods as p
        on p.fiscal_year = toUInt16(r.fiscal_year)
        and p.fiscal_period = toUInt16(r.fiscal_period)
    where r.hierarchy_is_group = 0
),

{# each leaf row, once per group that was its ancestor on the period's end_date #}
leaves_at_groups as (
    select
        l.hierarchy_name as k_hierarchy,
        c.ancestor_member_code as k_node,
        {% for col in slice_cols %}
        l.{{ col }} as k_{{ col }},
        {%- endfor %}
        l.amount as leaf_amount
    from leaf_rows as l
    inner join {{ ref('gold_reporting_hierarchy_closure') }} as c
        on c.hierarchy_name = l.hierarchy_name
        and c.dimension = l.hierarchy_dimension
        and c.descendant_member_code = l.hierarchy_member_code
    where c.ancestor_is_group = 1
      and l.period_end_date >= c.valid_from
      and l.period_end_date <= c.valid_to
),

stacked as (
    select
        hierarchy_name as k_hierarchy,
        hierarchy_member_code as k_node,
        {% for col in slice_cols %}
        {{ col }} as k_{{ col }},
        {%- endfor %}
        amount as group_amount,
        toFloat64(0) as leaf_amount
    from rolled
    where hierarchy_is_group = 1

    union all

    select
        k_hierarchy,
        k_node,
        {% for col in slice_cols %}
        k_{{ col }},
        {%- endfor %}
        toFloat64(0) as group_amount,
        leaf_amount
    from leaves_at_groups
)

select
    k_hierarchy as hierarchy,
    k_node as node,
    {% for col in slice_cols %}
    k_{{ col }} as slice_{{ col }},
    {%- endfor %}
    sum(group_amount) as group_total,
    sum(leaf_amount) as leaf_total
from stacked
group by
    k_hierarchy,
    k_node,
    {% for col in slice_cols %}
    k_{{ col }}{{ ',' if not loop.last }}
    {%- endfor %}
having abs(sum(group_amount) - sum(leaf_amount)) > 0.01
