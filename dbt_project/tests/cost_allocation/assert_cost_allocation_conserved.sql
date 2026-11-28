-- Cost allocation conserves money (konsol#269, T1; generalised for declared rates,
-- 2b-2 W4a). Per run x origin member:
--   1. every line sums to zero (what is sent is received, to the last digit);
--   2. the lines received at the SINKS sum to what the origin sends out: its pool
--      for a Share of Pool origin, rate x its own units for a Declared Rate origin.
--      So nothing is parked at an intermediate sender. A sink is a member that
--      never sends in the run, or a Declared Rate sender: a rate sender's outflow
--      is fixed by its rate, so cost that reaches it stops there, whoever's it is,
--      its own returning units included (Reciprocal; plan section 3). A share
--      sender is never a sink, not even for its own cost: under Reciprocal what
--      comes back to it is passed on again.
-- What the origin sends out is read from its own `sent` lines (hop_kind = 'own'):
--   - Share of Pool: origin_amount is the pool, one value per (run, origin,
--     account), taken once per account and summed across accounts. In Declared
--     Allocation Account mode a pass-through `sent` line sits on the allocation
--     account with the same origin_amount again, which is why only own lines count.
--   - Declared Rate: origin_amount is the RATE, so it is no pool; the charge is
--     rate x the own hop's coefficients (its driver units). That those units are
--     the step's units is assert_cost_allocation_coefficients_close's job.
-- Part 1 cannot fire on a build of the shipped macro (both lines of a hop carry
-- the same hop_amount, so each hop sums to zero); it stays as the tripwire for a
-- macro change that rounds or filters one side, and fires on a seeded table.
-- Part 2 can fire on a real build: a coefficient chain that parks money at a
-- share sender, or receives at a member that does not close.
-- The rate senders of a run are read from the lines themselves (an origin with
-- basis = 'Declared Rate'), so the test reads one table. Exact comparison, no
-- tolerance: the model carries Decimal(38,16) amounts.
-- UNION ALL + GROUP BY, not a LEFT JOIN: join_use_nulls=0 would fill a missing
-- side with 0 and hide an origin that has received lines but no own lines.
with lines as (
    select * from {{ ref('gold_cost_allocation') }}
),

senders as (
    select distinct run, sender_member from lines where line_type = 'sent'
),

rate_senders as (
    select distinct run, origin_member as member from lines where basis = 'Declared Rate'
),

totals as (
    select
        run, origin_member,
        sum(amount) as total,
        sumIf(amount, line_type = 'received'
              and ((run, receiver_member) not in (select run, sender_member from senders)
                   or (run, receiver_member) in (select run, member from rate_senders))
        ) as received_at_sinks
    from lines
    group by run, origin_member
),

sent_out as (
    select run, origin_member, toDecimal128(sum(account_pool), 16) as sent_out
    from (
        select run, origin_member, main_account, max(origin_amount) as account_pool
        from lines
        where line_type = 'sent' and hop_kind = 'own' and basis != 'Declared Rate'
        group by run, origin_member, main_account
    )
    group by run, origin_member

    union all

    select run, origin_member,
           max(origin_amount) * sumIf(coefficient, line_type = 'sent' and hop_kind = 'own') as sent_out
    from lines
    where basis = 'Declared Rate'
    group by run, origin_member
),

combined as (
    select run, origin_member, total, received_at_sinks, toDecimal128(0, 16) as sent_out
    from totals
    union all
    select run, origin_member, toDecimal128(0, 16), toDecimal128(0, 16), sent_out
    from sent_out
)

select
    run, origin_member,
    sum(total) as total,
    sum(received_at_sinks) as received_at_sinks,
    sum(sent_out) as sent_out
from combined
group by run, origin_member
having total != 0 or received_at_sinks != sent_out
