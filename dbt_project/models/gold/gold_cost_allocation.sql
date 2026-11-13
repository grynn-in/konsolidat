{{
    config(
        engine='MergeTree()',
        order_by='(run, origin_member, step, sender_member, receiver_member, line_type)'
    )
}}

-- Cost allocation lines for runs that follow the latest data (konsol#269, W3).
-- Runs frozen at approval come from gold_cost_allocation_frozen (W5). The
-- computation is the cost_allocation_lines macro, shared with that model.
-- frozen_at is NULL: a live line has no freeze time.
{{ cost_allocation_lines(
    runs_predicate="r.amounts_after_approval = 'Follow Latest Data'",
    frozen_at_expr="cast(null as Nullable(DateTime))"
) }}
