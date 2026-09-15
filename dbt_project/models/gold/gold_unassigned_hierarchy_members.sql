{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='(hierarchy_dimension, dimension_member_code)',
        cluster=cluster_name()
    )
}}

{# GL dimension values not assigned to any leaf in the default published hierarchy, per period.

   konsolidat#220: members are dated tranches (member_effective_from .. member_effective_to), so a value is
   unassigned in a period only when no leaf tranche of the default hierarchy covers that period's end_date.
   A value that becomes a leaf in 2025 is unassigned in 2024 and assigned from 2025. The period's end_date
   comes from the declared calendar (epm_staging.fiscal_periods); a period the calendar does not list is
   judged at the last day of its month. #}

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

tb_periods as (
    {# aliased: periods has fiscal_year / fiscal_period too, and ClickHouse would name
       the duplicated columns `tb.fiscal_year` / `tb.fiscal_period` #}
    select distinct
        tb.hierarchy_dimension as hierarchy_dimension,
        tb.dimension_member_code as dimension_member_code,
        tb.fiscal_year as fiscal_year,
        tb.fiscal_period as fiscal_period,
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
        h.member_code,
        h.member_effective_from,
        h.member_effective_to
    from {{ ref('gold_reporting_hierarchy') }} as h
    inner join default_hierarchies as d
        on d.hierarchy_name = h.hierarchy_name
        and d.dimension = h.dimension
    where h.is_group = 0
),

{# (value, period) pairs a leaf tranche of the default hierarchy covers #}
covered as (
    select distinct
        hl.hierarchy_name as hierarchy_name,
        tp.hierarchy_dimension as hierarchy_dimension,
        tp.dimension_member_code as dimension_member_code,
        tp.fiscal_year as fiscal_year,
        tp.fiscal_period as fiscal_period
    from tb_periods as tp
    inner join hierarchy_leaves as hl
        on hl.dimension = tp.hierarchy_dimension
        and hl.member_code = tp.dimension_member_code
    where tp.period_end_date >= hl.member_effective_from
      and tp.period_end_date <= hl.member_effective_to
)

select distinct
    tp.hierarchy_dimension as hierarchy_dimension,
    d.hierarchy_name as default_hierarchy_name,
    tp.dimension_member_code as dimension_member_code,
    tp.fiscal_year as fiscal_year,
    tp.fiscal_period as fiscal_period
from tb_periods as tp
inner join default_hierarchies as d
    on d.dimension = tp.hierarchy_dimension
left anti join covered as c
    on c.hierarchy_name = d.hierarchy_name
    and c.hierarchy_dimension = tp.hierarchy_dimension
    and c.dimension_member_code = tp.dimension_member_code
    and c.fiscal_year = tp.fiscal_year
    and c.fiscal_period = tp.fiscal_period
