-- PRD-6 Test: Sum of 12 spread period amounts must equal annual_amount
select
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    annual_amount,
    sum(period_amount) as spread_total,
    abs(annual_amount - sum(period_amount)) as spread_gap
from {{ ref('gold_spread_budget') }}
group by scenario_id, data_area_id, fiscal_year, main_account, annual_amount
having abs(annual_amount - sum(period_amount)) > 0.01
