-- Test: Each budget line should spread into exactly 12 periods
select
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    spread_profile_id,
    count(distinct fiscal_period) as period_count
from {{ ref('gold_spread_budget') }}
group by scenario_id, data_area_id, fiscal_year, main_account, spread_profile_id
having count(distinct fiscal_period) != 12
