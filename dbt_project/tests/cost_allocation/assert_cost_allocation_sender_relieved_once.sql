-- Sender relieved once (konsol#269, T4). An origin member's pool in an account is
-- relieved by one run only, per scenario, entity, year and period. The relief is
-- the 'sent' line at the origin itself (sender_member = origin_member); later
-- hops pass the amount on and do not relieve the origin again.
select
    scenario_id, data_area_id, fiscal_year, fiscal_period, origin_member, main_account,
    uniqExact(run) as runs, arraySort(groupUniqArray(run)) as run_names
from {{ ref('gold_cost_allocation') }}
where line_type = 'sent' and sender_member = origin_member
group by scenario_id, data_area_id, fiscal_year, fiscal_period, origin_member, main_account
having runs > 1
