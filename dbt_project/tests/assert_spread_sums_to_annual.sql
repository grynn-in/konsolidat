-- PRD-6 Test: per grain (scenario, entity, year, account, layer, budget dims) the spread period amounts
-- must sum to annual_amount. gold_spread_budget gives each layer its own annual_amount, and carries each
-- annual input's own amount on its rows, so the reference is the largest annual_amount of the grain: a
-- grain fed by two inputs (equal or unequal) is spread twice and its total exceeds that reference.
select
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    layer,
    {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
    max(annual_amount) as grain_annual_amount,
    sum(period_amount) as spread_total,
    abs(max(annual_amount) - sum(period_amount)) as spread_gap
from {{ ref('gold_spread_budget') }}
group by
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    layer
    {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
having abs(max(annual_amount) - sum(period_amount)) > 0.01
