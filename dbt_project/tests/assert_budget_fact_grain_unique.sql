-- grynn-in/konsolidat#94: the canonical budget fact must hold exactly one row
-- per (scenario, entity, year, period, account, budget dims). The two entry
-- methods (annual×profile spread and manual monthly identity-spread) are
-- UNIONed, with manual overriding annual-spread on the same grain — this asserts
-- the precedence actually dedups and nothing double-counts.

select
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_group_by(dims=get_budget_dimensions()) }},
    count(*) as n_rows
from {{ ref('gold_spread_budget') }}
group by
    scenario_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_group_by(dims=get_budget_dimensions()) }}
having count(*) > 1
