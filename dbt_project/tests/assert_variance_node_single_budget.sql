{# konsolidat#206: gold_variance_at_hierarchy_node keeps each budget scenario
   apart. gold_variance_analysis has one set of rows per active budget-type
   scenario (budget_scenario_id), the actuals repeated against each. Summed
   over the leaf rows (hierarchy_is_group = 0) of one hierarchy and dimension,
   the node model's actual_amount for a (budget_scenario_id, entity, year,
   period, account) must equal gold_variance_analysis' actual_amount over the
   rows whose dimension value is a leaf of that hierarchy.

   A node model that does not carry budget_scenario_id is compared on the rest
   of the key, so each budget scenario's actuals meet the node's sum across
   scenarios: with two budget scenarios the actuals are counted twice and the
   test fails rather than erroring. One row per mismatched key.

   Output aliases differ from the joined columns' names: ClickHouse strips the
   qualifier from the left table's columns in a join, so a same-named alias
   would shadow them. #}

{% set node_cols = [] %}
{% if execute %}
    {% set node_cols = adapter.get_columns_in_relation(ref('gold_variance_at_hierarchy_node')) | map(attribute='name') | list %}
{% endif %}
{% set node_has_scenario = 'budget_scenario_id' in node_cols %}
{# the node model selects lc.hierarchy_dimension from a join whose other side
   has hierarchy_dimension too, so ClickHouse names the column
   `lc.hierarchy_dimension`: read whichever name the relation has #}
{% set node_dim_col = 'hierarchy_dimension' if 'hierarchy_dimension' in node_cols else '`lc.hierarchy_dimension`' %}

with leaves as (
    select hierarchy_name, dimension, member_code
    from {{ ref('gold_reporting_hierarchy') }}
    where is_group = 0
),

expected as (
    select
        l.hierarchy_name as hierarchy_name,
        l.dimension as dimension,
        vl.budget_scenario_id as budget_scenario_id,
        vl.data_area_id as data_area_id,
        vl.fiscal_year as fiscal_year,
        vl.fiscal_period as fiscal_period,
        vl.main_account as main_account,
        sum(vl.actual_amount) as actual_amount
    from (
        {{ variance_dimension_long_sql('v') }}
    ) as vl
    inner join leaves as l
        on l.dimension = vl.hierarchy_dimension
        and l.member_code = vl.dimension_member_code
    group by
        l.hierarchy_name, l.dimension, vl.budget_scenario_id,
        vl.data_area_id, vl.fiscal_year, vl.fiscal_period, vl.main_account
),

node as (
    select
        nm.hierarchy_name as node_hierarchy,
        nm.{{ node_dim_col }} as node_dimension,
        {% if node_has_scenario %}nm.budget_scenario_id as node_scenario,{% endif %}
        nm.data_area_id as node_entity,
        nm.fiscal_year as node_year,
        nm.fiscal_period as node_period,
        nm.main_account as node_account,
        sum(nm.actual_amount) as node_actual
    from {{ ref('gold_variance_at_hierarchy_node') }} as nm
    where nm.hierarchy_is_group = 0
    group by
        node_hierarchy, node_dimension, {% if node_has_scenario %}node_scenario,{% endif %}
        node_entity, node_year, node_period, node_account
)

select
    if(coalesce(e.hierarchy_name, '') != '', e.hierarchy_name, n.node_hierarchy) as hierarchy,
    if(coalesce(e.hierarchy_name, '') != '', e.dimension, n.node_dimension) as dimension_column,
    if(coalesce(e.hierarchy_name, '') != '', e.budget_scenario_id, {% if node_has_scenario %}n.node_scenario{% else %}''{% endif %}) as scenario_id,
    if(coalesce(e.hierarchy_name, '') != '', e.data_area_id, n.node_entity) as entity,
    if(coalesce(e.hierarchy_name, '') != '', e.fiscal_year, n.node_year) as key_year,
    if(coalesce(e.hierarchy_name, '') != '', e.fiscal_period, n.node_period) as key_period,
    if(coalesce(e.hierarchy_name, '') != '', e.main_account, n.node_account) as account,
    e.actual_amount as analysis_actual_amount,
    n.node_actual as node_actual_amount
from expected as e
full outer join node as n
    on e.hierarchy_name = n.node_hierarchy
    and e.dimension = n.node_dimension
    and e.data_area_id = n.node_entity
    and e.fiscal_year = n.node_year
    and e.fiscal_period = n.node_period
    and e.main_account = n.node_account
    {% if node_has_scenario %}and e.budget_scenario_id = n.node_scenario{% endif %}
where coalesce(e.hierarchy_name, '') = ''
   or coalesce(n.node_hierarchy, '') = ''
   or abs(toFloat64(e.actual_amount) - toFloat64(n.node_actual)) > {{ materiality_floor() }}
