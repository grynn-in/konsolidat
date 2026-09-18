{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_name, hierarchy_member_code, data_area_id, fiscal_year, fiscal_period, main_account)',
        cluster=cluster_name()
    )
}}

{# Trial balance rolled up to any node in a reporting hierarchy.

   konsolidat#220: the tree is resolved per period. Members are dated tranches (member_effective_from ..
   member_effective_to) and each closure link holds only within its window (valid_from .. valid_to), so a
   trial-balance row joins only the leaf tranche and the closure rows whose windows cover its period's end_date:
   a moved leaf rolls to the parent it had then, an ended node carries no later period, and a renamed node
   carries the label of that period. The period's end_date comes from the declared calendar
   (epm_staging.fiscal_periods); a period the calendar does not list is judged at the last day of its month. #}

with tb_long as (
    {{ tb_dimension_long_sql('tb') }}
),

periods as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        max(end_date) as end_date
    from {{ source('epm_staging', 'fiscal_periods') }}
    group by fiscal_year, fiscal_period
),

tb_dated as (
    select
        tb.*,
        {# an unmatched LEFT JOIN row carries Date's default (1970-01-01), not NULL #}
        if(
            p.end_date = toDate(0),
            toLastDayOfMonth({{ build_date_from_year_period('tb.fiscal_year', 'tb.fiscal_period') }}),
            p.end_date
        ) as period_end_date
    from tb_long as tb
    left join periods as p
        on p.fiscal_year = toUInt16(tb.fiscal_year)
        and p.fiscal_period = toUInt16(tb.fiscal_period)
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
    {# aliased: tb_long has hierarchy_dimension too, and ClickHouse would name
       the duplicated column `lc.hierarchy_dimension` #}
    lc.hierarchy_dimension as hierarchy_dimension,
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
    {%- endfor %}{{ ',' if var('dimensions') | length > 0 }}
    {{ hierarchy_measure_sums('tb.') }}
from tb_dated as tb
inner join leaf_closure as lc
    on lc.hierarchy_dimension = tb.hierarchy_dimension
    and lc.descendant_member_code = tb.dimension_member_code
{# the leaf tranche and the closure link that hold on the period's end_date #}
where tb.period_end_date >= lc.leaf_effective_from
  and tb.period_end_date <= lc.leaf_effective_to
  and tb.period_end_date >= lc.valid_from
  and tb.period_end_date <= lc.valid_to
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
    tb.is_pnl
    {{- ',' if var('dimensions') | length > 0 }}
    {% for d in var('dimensions') %}
    if(lc.hierarchy_dimension = '{{ d.name }}', '', tb.{{ d.name }}){{ ',' if not loop.last }}
    {%- endfor %}
