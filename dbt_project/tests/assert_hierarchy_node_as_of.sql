{# konsolidat#220: the trial balance rolls up the tree AS IT WAS in each period, with that period's labels.
   On the fixture hierarchy_dated.sql (hierarchy ZZ_DIV over dim_business_unit, entity ZZE1, cash ZZ1000):
     - FY2018 P6: ZZ_EX rolls to ZZ_E and ZZ_ROOT, not ZZ_B; ZZ_GX rolls to ZZ_G;
     - FY2024 P6: ZZ_AX rolls to ZZ_A labelled "Alpha";
     - FY2025 P6: ZZ_EX rolls to ZZ_B, not ZZ_E; ZZ_AX rolls to ZZ_A labelled "Alpha New"; no row carries
       ZZ_E or ZZ_G (both ended before 2025);
     - every node carries each amount once (a leaf with two tranches is not counted twice).
   Budgets (row H4) the same way, on hierarchy ZZ_DIV_CC over dim_cost_center (a budget has no business unit),
   scenario ZZ_PLAN_H, revenue ZZ4000: FY2018 P6 ZZ_EX rolls to ZZ_E and ZZ_ROOT, not ZZ_B; FY2025 P6 ZZ_EX
   rolls to ZZ_B and ZZ_ROOT, not ZZ_E.
   Variance (row H5) the same way, on the same cost-centre tree (business unit never reaches variance): the
   budget_amount of budget_scenario_id ZZ_PLAN_H on ZZ4000 is -70 at FY2018 P6 on ZZ_EX, ZZ_E and ZZ_ROOT (not
   ZZ_B), and -600 at FY2025 P6 on ZZ_EX, ZZ_B and ZZ_ROOT (not ZZ_E).
   The node rows must be exactly the expected ones: one row per missing or wrong node, one per unexpected node. #}

with actual as (
    select
        hierarchy_member_code as code,
        toInt32(fiscal_year) as fy,
        toInt32(fiscal_period) as fp,
        hierarchy_member_label as label,
        toFloat64(sum(period_net_amount)) as amount,
        toUInt8(1) as hit
    from {{ ref('gold_tb_at_hierarchy_node') }}
    where hierarchy_name = 'ZZ_DIV'
      and hierarchy_dimension = 'dim_business_unit'
      and data_area_id = 'ZZE1'
      and main_account = 'ZZ1000'
    group by code, fy, fp, label
),

expected as (
    select 'ZZ_EX' as code, toInt32(2018) as fy, toInt32(6) as fp, 'ZZ EX' as label, toFloat64(100) as amount, toUInt8(1) as hit
    union all select 'ZZ_E', 2018, 6, 'ZZ E', 100, 1
    union all select 'ZZ_GX', 2018, 6, 'ZZ GX', 20, 1
    union all select 'ZZ_G', 2018, 6, 'ZZ G', 20, 1
    union all select 'ZZ_ROOT', 2018, 6, 'ZZ root', 120, 1
    union all select 'ZZ_AX', 2024, 6, 'ZZ AX', 3, 1
    union all select 'ZZ_A', 2024, 6, 'Alpha', 3, 1
    union all select 'ZZ_ROOT', 2024, 6, 'ZZ root', 3, 1
    union all select 'ZZ_EX', 2025, 6, 'ZZ EX', 500, 1
    union all select 'ZZ_B', 2025, 6, 'ZZ B', 500, 1
    union all select 'ZZ_AX', 2025, 6, 'ZZ AX', 4000, 1
    union all select 'ZZ_A', 2025, 6, 'Alpha New', 4000, 1
    union all select 'ZZ_ROOT', 2025, 6, 'ZZ root', 4500, 1
),

budget_actual as (
    select
        hierarchy_member_code as code,
        toInt32(fiscal_year) as fy,
        toInt32(fiscal_period) as fp,
        hierarchy_member_label as label,
        toFloat64(sum(period_amount)) as amount,
        toUInt8(1) as hit
    from {{ ref('gold_budget_at_hierarchy_node') }}
    where hierarchy_name = 'ZZ_DIV_CC'
      and hierarchy_dimension = 'dim_cost_center'
      and scenario_id = 'ZZ_PLAN_H'
      and data_area_id = 'ZZE1'
      and main_account = 'ZZ4000'
    group by code, fy, fp, label
),

budget_expected as (
    select 'ZZ_EX' as code, toInt32(2018) as fy, toInt32(6) as fp, 'ZZ EX' as label, toFloat64(-70) as amount, toUInt8(1) as hit
    union all select 'ZZ_E', 2018, 6, 'ZZ E', -70, 1
    union all select 'ZZ_ROOT', 2018, 6, 'ZZ root', -70, 1
    union all select 'ZZ_EX', 2025, 6, 'ZZ EX', -600, 1
    union all select 'ZZ_B', 2025, 6, 'ZZ B', -600, 1
    union all select 'ZZ_ROOT', 2025, 6, 'ZZ root', -600, 1
),

variance_actual as (
    select
        hierarchy_member_code as code,
        toInt32(fiscal_year) as fy,
        toInt32(fiscal_period) as fp,
        hierarchy_member_label as label,
        toFloat64(sum(coalesce(budget_amount, 0))) as amount,
        toUInt8(1) as hit
    from {{ ref('gold_variance_at_hierarchy_node') }}
    where hierarchy_name = 'ZZ_DIV_CC'
      and hierarchy_dimension = 'dim_cost_center'
      and budget_scenario_id = 'ZZ_PLAN_H'
      and data_area_id = 'ZZE1'
      and main_account = 'ZZ4000'
    group by code, fy, fp, label
)

-- an expected node that is missing, or carries the wrong amount
select
    concat('FY', toString(e.fy), ' P', toString(e.fp), ' ', e.code, ' "', e.label, '"') as node,
    if(a.hit = 0, 'missing',
       concat('amount ', toString(a.amount), ', expected ', toString(e.amount))) as problem
from expected as e
left join actual as a
    on a.code = e.code
    and a.fy = e.fy
    and a.fp = e.fp
    and a.label = e.label
where a.hit = 0 or abs(a.amount - e.amount) > 0.005

union all

-- a node the tree did not have in that period (or had under another label)
select
    concat('FY', toString(a.fy), ' P', toString(a.fp), ' ', a.code, ' "', a.label, '"') as node,
    concat('unexpected, amount ', toString(a.amount)) as problem
from actual as a
left join expected as e
    on e.code = a.code
    and e.fy = a.fy
    and e.fp = a.fp
    and e.label = a.label
where e.hit = 0

union all

-- budgets (row H4): an expected budget node that is missing, or carries the wrong amount
select
    concat('budget FY', toString(e.fy), ' P', toString(e.fp), ' ', e.code, ' "', e.label, '"') as node,
    if(a.hit = 0, 'missing',
       concat('amount ', toString(a.amount), ', expected ', toString(e.amount))) as problem
from budget_expected as e
left join budget_actual as a
    on a.code = e.code
    and a.fy = e.fy
    and a.fp = e.fp
    and a.label = e.label
where a.hit = 0 or abs(a.amount - e.amount) > 0.005

union all

-- a budget node the tree did not have in that period
select
    concat('budget FY', toString(a.fy), ' P', toString(a.fp), ' ', a.code, ' "', a.label, '"') as node,
    concat('unexpected, amount ', toString(a.amount)) as problem
from budget_actual as a
left join budget_expected as e
    on e.code = a.code
    and e.fy = a.fy
    and e.fp = a.fp
    and e.label = a.label
where e.hit = 0

union all

-- variance (row H5): an expected node missing, or carrying the wrong budget (same nodes as the budget model)
select
    concat('variance FY', toString(e.fy), ' P', toString(e.fp), ' ', e.code, ' "', e.label, '"') as node,
    if(a.hit = 0, 'missing',
       concat('budget_amount ', toString(a.amount), ', expected ', toString(e.amount))) as problem
from budget_expected as e
left join variance_actual as a
    on a.code = e.code
    and a.fy = e.fy
    and a.fp = e.fp
    and a.label = e.label
where a.hit = 0 or abs(a.amount - e.amount) > 0.005

union all

-- a variance node the tree did not have in that period
select
    concat('variance FY', toString(a.fy), ' P', toString(a.fp), ' ', a.code, ' "', a.label, '"') as node,
    concat('unexpected, budget_amount ', toString(a.amount)) as problem
from variance_actual as a
left join budget_expected as e
    on e.code = a.code
    and e.fy = a.fy
    and e.fp = a.fp
    and e.label = a.label
where e.hit = 0
