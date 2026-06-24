-- Test: each ANNUAL-spread budget line spreads into exactly 12 periods.
-- Excludes manual (identity-spread) budgets (#94): a manually-entered budget can
-- legitimately be partial-year, so it carries no structural 12-period guarantee.
select
    scenario_id,
    data_area_id,
    fiscal_year,
    main_account,
    spread_profile_id,
    count(distinct fiscal_period) as period_count
from {{ ref('gold_spread_budget') }}
where spread_profile_id != 'manual'
group by scenario_id, data_area_id, fiscal_year, main_account, spread_profile_id
having count(distinct fiscal_period) != 12
