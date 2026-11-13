{{
    config(
        engine='MergeTree()',
        order_by='(run, origin_member, step, sender_member, receiver_member, line_type)'
    )
}}

-- Cost allocation lines (konsol#269): the runs that follow the latest data,
-- computed here (W3), union the runs frozen at approval, read from
-- gold_cost_allocation_frozen (W5). The computation is the cost_allocation_lines
-- macro, shared with that model. A live line has frozen_at NULL.
select * from (
    {{ cost_allocation_lines(
        runs_predicate="r.amounts_after_approval = 'Follow Latest Data'",
        frozen_at_expr="cast(null as Nullable(DateTime))"
    ) }}
)

union all

select
    run, rule_set, method, scenario_id, data_area_id, main_account, allocation_dimension,
    member, line_type, origin_member, sender_member, receiver_member, driver,
    fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at
from {{ ref('gold_cost_allocation_frozen') }}
