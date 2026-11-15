-- grynn-in/konsolidat#94: the canonical budget fact must hold exactly one row
-- per (scenario, cycle, entity, year, period, account, budget dims, layer). The two entry
-- methods (annual×profile spread and manual monthly identity-spread) are
-- UNIONed with no precedence rule: konsol keeps them on disjoint grains (Q16-c,
-- backstopped by assert_budget_one_writer_per_grain), so nothing double-counts
-- and this asserts it. `layer` is part of the
-- grain: gold_spread_budget emits one row per layer (konsolidat#300). So is `cycle`
-- (konsol#348 S3 B4, QB2 a): a forecast round is its own approved Cycle, and two rounds on
-- one grain are two legitimate rows, never one.

select
    scenario_id,
    cycle,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    layer,
    {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
    count(*) as n_rows
from {{ ref('gold_spread_budget') }}
group by
    scenario_id,
    cycle,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    layer
    {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
having count(*) > 1
