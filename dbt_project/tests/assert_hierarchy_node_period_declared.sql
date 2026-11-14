{# konsolidat#189 PR3 (konsol#348, decision QA3 a): every period a hierarchy-node model carries is a period
   konsol's fiscal calendar declares (epm_staging.fiscal_periods).

   The node models date a period by its declared calendar, and they used to fall back, for a period the
   calendar does not list, to the last day of the calendar month the period number names. That date is
   invented: an April-March year's P5 is August, not May, and a period with no declaration has no true
   date. Each node model now inner-joins the declared periods, so an undeclared period drops out; this test
   is what turns that drop into a failed build, the way assert_trial_balance_period_declared does for
   gold_trial_balance.

   One row per (model, fiscal_year, fiscal_period) that a node model carries and the calendar does not
   declare. Models: gold_tb_at_hierarchy_node, gold_unassigned_hierarchy_members,
   gold_budget_at_hierarchy_node, gold_variance_at_hierarchy_node.
   Fixture: dbt_project/test_fixtures/assert_hierarchy_node_period_declared.sql. #}
select
    n.model as model,
    n.fiscal_year as fiscal_year,
    n.fiscal_period as fiscal_period,
    count() as n_rows,
    'period not declared in epm_staging.fiscal_periods' as fault
from (
    select 'gold_tb_at_hierarchy_node' as model, toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period
    from {{ ref('gold_tb_at_hierarchy_node') }}
    union all
    select 'gold_unassigned_hierarchy_members' as model, toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period
    from {{ ref('gold_unassigned_hierarchy_members') }}
    union all
    select 'gold_budget_at_hierarchy_node' as model, toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period
    from {{ ref('gold_budget_at_hierarchy_node') }}
    union all
    select 'gold_variance_at_hierarchy_node' as model, toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period
    from {{ ref('gold_variance_at_hierarchy_node') }}
) as n
where (n.fiscal_year, n.fiscal_period) not in (
    select dp.fiscal_year, dp.fiscal_period
    from {{ declared_periods() }} as dp
)
group by n.model, n.fiscal_year, n.fiscal_period
