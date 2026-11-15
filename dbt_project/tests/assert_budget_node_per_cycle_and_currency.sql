{# konsol#348 S3 B11 (QB2 a, QB3 a; decided 14 Nov 2026 under Deepak Pai's standing rule): the budget rollup
   to a reporting hierarchy node keeps every Budget Cycle and every currency apart.

   gold_spread_budget carries `cycle` (B4) and `currency` (B4, B7): a forecast scenario holds one approved
   Cycle per round, and rounds must never sum; a budget line is in its entity's accounting currency, and
   amounts in two currencies must never sum. gold_budget_at_hierarchy_node therefore carries both and groups
   by both, as gold_tb_at_hierarchy_node carries every column of its row grain (gold_trial_balance has no
   currency; the entity's is one, so grouping by it never splits a row).

   Checked at the leaves. Summed over the leaf rows (hierarchy_is_group = 0) of one hierarchy and dimension,
   the node model's period_amount per (scenario, cycle, currency, entity, year, period, account, layer) must
   equal the fact's over the rows whose dimension value is a leaf of that hierarchy. A node model without
   the cycle (or currency) column is compared on the rest of the key, so each round's fact rows meet the
   node's sum across rounds and the test fails rather than errors: two rounds of -100 and -110 against one
   node row of -210.

   konsolidat#220: a code may be a leaf in several dated tranches. A fact row matches only the leaf tranche
   whose window covers its period's end_date (declared calendar, epm_staging.fiscal_periods; a period the
   calendar does not declare drops out of both sides, QA3 a). Output aliases differ from the joined columns'
   names: ClickHouse strips the qualifier from the left table's columns in a join, so a same-named alias
   would shadow them. One row per mismatched key; error severity.
   Fixtures: dbt_project/test_fixtures/budget_node_two_rounds.sql. #}
{{ config(severity='error') }}

{% set node_cols = [] %}
{% if execute %}
    {% set node_cols = adapter.get_columns_in_relation(ref('gold_budget_at_hierarchy_node')) | map(attribute='name') | list %}
{% endif %}
{% set node_has_cycle = 'cycle' in node_cols %}
{% set node_has_currency = 'currency' in node_cols %}

with leaves as (
    select hierarchy_name, dimension, member_code, member_effective_from, member_effective_to
    from {{ ref('gold_reporting_hierarchy') }}
    where is_group = 0
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
        bd.*,
        p.end_date as period_end_date
    from (
        {{ budget_dimension_long_sql('b') }}
    ) as bd
    inner join periods as p
        on p.fiscal_year = toUInt16(bd.fiscal_year)
        and p.fiscal_period = toUInt16(bd.fiscal_period)
),

expected as (
    select
        l.hierarchy_name as hierarchy_name,
        l.dimension as dimension,
        bl.scenario_id as scenario_id,
        bl.cycle as cycle,
        bl.currency as currency,
        bl.data_area_id as data_area_id,
        bl.fiscal_year as fiscal_year,
        bl.fiscal_period as fiscal_period,
        bl.main_account as main_account,
        bl.layer as layer,
        sum(bl.period_amount) as period_amount
    from budget_dated as bl
    inner join leaves as l
        on l.dimension = bl.hierarchy_dimension
        and l.member_code = bl.dimension_member_code
    where bl.period_end_date >= l.member_effective_from
      and bl.period_end_date <= l.member_effective_to
    group by
        l.hierarchy_name, l.dimension, bl.scenario_id, bl.cycle, bl.currency,
        bl.data_area_id, bl.fiscal_year, bl.fiscal_period, bl.main_account, bl.layer
),

node as (
    select
        nm.hierarchy_name as node_hierarchy,
        nm.hierarchy_dimension as node_dimension,
        nm.scenario_id as node_scenario,
        {% if node_has_cycle %}nm.cycle{% else %}''{% endif %} as node_cycle,
        {% if node_has_currency %}nm.currency{% else %}''{% endif %} as node_currency,
        nm.data_area_id as node_entity,
        nm.fiscal_year as node_year,
        nm.fiscal_period as node_period,
        nm.main_account as node_account,
        nm.layer as node_layer,
        sum(nm.period_amount) as node_amount
    from {{ ref('gold_budget_at_hierarchy_node') }} as nm
    where nm.hierarchy_is_group = 0
    group by
        node_hierarchy, node_dimension, node_scenario, node_cycle, node_currency,
        node_entity, node_year, node_period, node_account, node_layer
)

select
    if(coalesce(e.hierarchy_name, '') != '', e.hierarchy_name, n.node_hierarchy) as hierarchy,
    if(coalesce(e.hierarchy_name, '') != '', e.dimension, n.node_dimension) as dimension_column,
    if(coalesce(e.hierarchy_name, '') != '', e.scenario_id, n.node_scenario) as budget_scenario,
    if(coalesce(e.hierarchy_name, '') != '', e.cycle, n.node_cycle) as budget_cycle,
    if(coalesce(e.hierarchy_name, '') != '', e.currency, n.node_currency) as row_currency,
    if(coalesce(e.hierarchy_name, '') != '', e.data_area_id, n.node_entity) as entity,
    if(coalesce(e.hierarchy_name, '') != '', e.fiscal_year, n.node_year) as key_year,
    if(coalesce(e.hierarchy_name, '') != '', e.fiscal_period, n.node_period) as key_period,
    if(coalesce(e.hierarchy_name, '') != '', e.main_account, n.node_account) as account,
    if(coalesce(e.hierarchy_name, '') != '', e.layer, n.node_layer) as budget_layer,
    e.period_amount as fact_period_amount,
    n.node_amount as node_period_amount
from expected as e
full outer join node as n
    on e.hierarchy_name = n.node_hierarchy
    and e.dimension = n.node_dimension
    and e.scenario_id = n.node_scenario
    and e.data_area_id = n.node_entity
    and e.fiscal_year = n.node_year
    and e.fiscal_period = n.node_period
    and e.main_account = n.node_account
    and e.layer = n.node_layer
    {% if node_has_cycle %}and e.cycle = n.node_cycle{% endif %}
    {% if node_has_currency %}and e.currency = n.node_currency{% endif %}
where coalesce(e.hierarchy_name, '') = ''
   or coalesce(n.node_hierarchy, '') = ''
   or abs(toFloat64(e.period_amount) - toFloat64(n.node_amount)) > {{ materiality_floor() }}
