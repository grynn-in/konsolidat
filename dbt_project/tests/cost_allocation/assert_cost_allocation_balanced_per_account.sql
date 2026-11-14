-- Cost allocation balances per account (konsol#269, WF1). T1 sums an origin's
-- lines across accounts, so a line booked on the wrong account passes it. Per run
-- this test checks each account and member (worked example: the header of
-- macros/cost_allocation.sql). Rows returned are violations:
--   1. origin relief: per account, the lines at the origin member itself sum to
--      minus its pool on that account. An overflowed hop amount fails here. So
--      does a line at the origin on an account that holds no pool of it.
--   2. pass-through: a member that sends on an origin's cost it received nets to
--      zero for that origin on every account.
--   3. declared placement: in 'Declared Allocation Account' mode every line that
--      is not at the origin itself is on the run's allocation account.
--   4. account balance: per run x account, the net is minus the pools held on the
--      account plus the pools it receives. The receiving account is the pool's
--      own account in "Sender's Own Accounts" mode (so each account nets to zero)
--      and the allocation account in declared mode. So the pool account is
--      relieved by exactly the origin pools, and the allocation account carries
--      all of them.
-- A pool is read from the origin's own sent lines (sender = origin), which sit on
-- the pool account: one value per run x origin x account.
-- UNION ALL + GROUP BY and inner joins only: join_use_nulls=0 would fill a
-- missing side with 0.
with runs as (
    select name, receiver_account_mode, allocation_account
    from {{ source('epm_staging', 'cost_allocation_runs') }}
),

lines as (
    select
        l.run as run, l.main_account as main_account, l.member as member,
        l.line_type as line_type, l.origin_member as origin_member,
        l.sender_member as sender_member, l.origin_amount as origin_amount,
        l.amount as amount,
        r.receiver_account_mode = 'Declared Allocation Account' as declared,
        r.allocation_account as allocation_account
    from {{ ref('gold_cost_allocation') }} as l
    inner join runs as r on r.name = l.run
),

pools as (
    select
        run, origin_member, main_account,
        toDecimal128(max(origin_amount), 16) as pool,
        any(declared) as declared, any(allocation_account) as allocation_account
    from lines
    where line_type = 'sent' and sender_member = origin_member
    group by run, origin_member, main_account
),

passers as (
    select distinct run, origin_member, sender_member
    from lines
    where line_type = 'sent' and sender_member != origin_member
),

relief as (
    select run, main_account, origin_member, sum(net) as net, sum(pool) as pool
    from (
        select run, main_account, origin_member, sum(amount) as net, toDecimal128(0, 16) as pool
        from lines
        where member = origin_member
        group by run, main_account, origin_member
        union all
        select run, main_account, origin_member, toDecimal128(0, 16), pool
        from pools
    )
    group by run, main_account, origin_member
),

pass_through as (
    select run, main_account, member, origin_member, sum(amount) as net
    from lines
    where (run, origin_member, member) in (select run, origin_member, sender_member from passers)
    group by run, main_account, member, origin_member
),

misplaced as (
    select run, main_account, member, origin_member, sum(amount) as net
    from lines
    where declared and member != origin_member and main_account != allocation_account
    group by run, main_account, member, origin_member
),

account_balance as (
    select run, main_account, sum(amount) as net
    from (
        select run, main_account, amount from lines
        union all
        select run, main_account, pool from pools
        union all
        select run, if(declared, allocation_account, main_account), -pool from pools
    )
    group by run, main_account
)

select run, main_account, origin_member as member, origin_member,
       'origin not relieved by exactly its pool on this account' as problem, net, -pool as expected
from relief
where net != -pool

union all

select run, main_account, member, origin_member,
       'pass-through does not net to zero on this account', net, toDecimal128(0, 16)
from pass_through
where net != 0

union all

select run, main_account, member, origin_member,
       'line not on the declared allocation account', net, toDecimal128(0, 16)
from misplaced

union all

select run, main_account, '', '',
       'account does not balance: pools held and received', net, toDecimal128(0, 16)
from account_balance
where net != 0
