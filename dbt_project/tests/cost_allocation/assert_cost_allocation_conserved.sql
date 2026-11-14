-- Cost allocation conserves money (konsol#269, T1). Per run x origin member:
--   1. every line sums to zero (what is sent is received, to the last digit);
--   2. the lines received at members that never send in the run sum to the
--      origin's pool, so nothing is parked at an intermediate sender.
-- Part 1 cannot fire on a build of the shipped macro (both lines of a hop carry
-- the same hop_amount, so each hop sums to zero); it stays as the tripwire for a
-- macro change that rounds or filters one side, and fires on a seeded table.
-- Part 2 can fire on a real build: a coefficient chain that parks money at a
-- sender, or receives at a member that does not close.
-- The pool is read from the origin's own `sent` lines (sender = origin): in
-- Declared Allocation Account mode a pass-through `sent` line sits on the
-- allocation account, and its origin_amount is the same pool again.
-- The pool is read from the `sent` lines, one value per (run, origin, account);
-- origin_amount repeats on every line of that origin, so it is taken once per
-- account and summed across accounts. Exact comparison, no tolerance: the model
-- carries Decimal(38,16) amounts and the hop coefficients are rounded to close.
-- UNION ALL + GROUP BY, not a LEFT JOIN: join_use_nulls=0 would fill a missing
-- side with 0 and hide an origin that has received lines but no pool.
with lines as (
    select * from {{ ref('gold_cost_allocation') }}
),

senders as (
    select distinct run, sender_member from lines where line_type = 'sent'
),

totals as (
    select
        run, origin_member,
        sum(amount) as total,
        sumIf(amount, line_type = 'received'
              and (run, receiver_member) not in (select run, sender_member from senders)
        ) as received_at_receivers
    from lines
    group by run, origin_member
),

pools as (
    select run, origin_member, sum(account_pool) as pool
    from (
        select run, origin_member, main_account, max(origin_amount) as account_pool
        from lines
        where line_type = 'sent' and sender_member = origin_member
        group by run, origin_member, main_account
    )
    group by run, origin_member
),

combined as (
    select run, origin_member, total, received_at_receivers, toDecimal128(0, 4) as pool
    from totals
    union all
    select run, origin_member, toDecimal128(0, 16), toDecimal128(0, 16), pool
    from pools
)

select
    run, origin_member,
    sum(total) as total,
    sum(received_at_receivers) as received_at_receivers,
    sum(pool) as pool
from combined
group by run, origin_member
having total != 0 or received_at_receivers != pool
