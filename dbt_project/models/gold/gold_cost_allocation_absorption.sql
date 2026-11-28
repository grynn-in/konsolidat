{{
    config(
        engine='MergeTree()',
        order_by='(run, sender_member)'
    )
}}

-- Absorption variance per Declared Rate sender (konsol#269 2b-2 W6; Q5 A, Deepak Pai
-- 27 Nov 2026): one row per run x rate sender with its pool, what it received, what it
-- charged (rate x units) and variance = pool + received - charged (positive =
-- under-absorbed). A rate sender's lines relieve rate x units on the allocation account
-- and leave its pool on its own accounts, so the variance appears in no line: this is
-- where it is reported, and it is never re-spread (Q5 B rejected). Runs that follow the
-- latest data are computed here from gold_cost_allocation; runs frozen at approval come
-- from gold_cost_allocation_absorption_frozen, as gold_cost_allocation does with its
-- frozen twin. A live row has frozen_at NULL. The computation is the
-- cost_allocation_absorption macro, shared with the frozen model.
select * from (
    {{ cost_allocation_absorption(
        runs_predicate="r.amounts_after_approval = 'Follow Latest Data'",
        lines_relation=ref('gold_cost_allocation'),
        frozen_at_expr="cast(null as Nullable(DateTime))"
    ) }}
)

union all

select
    run, rule_set, method, scenario_id, data_area_id, fiscal_year, fiscal_period,
    allocation_dimension, allocation_account, sender_member, step, rate, units,
    pool, received, charged, variance, frozen_at
from {{ ref('gold_cost_allocation_absorption_frozen') }}
