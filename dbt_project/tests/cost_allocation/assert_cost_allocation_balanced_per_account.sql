-- Cost allocation balances per account (konsol#269, WF1; generalised for declared
-- rates, 2b-2 W4c). T1 sums an origin's lines across accounts, so a line booked on
-- the wrong account passes it. Per run this test checks each account and member
-- (worked examples: the header of macros/cost_allocation.sql). Rows returned are
-- violations:
--   1. origin relief: per account, the lines at the origin member itself sum to
--      minus what it must be relieved by on that account: its pool for a Share of
--      Pool origin; rate x the step's driver units (from the run's weight rows) for
--      a Declared Rate origin, whose relief sits on the allocation account. An
--      overflowed hop amount fails here. So does a line at the origin on an
--      account that holds no pool of it. Inflows to a rate origin (its received
--      lines: it is a sink, Reciprocal sends its own units back) are allowed and
--      left out of its net; a share origin's inflows net against its pass lines.
--   2. pass-through: a member that sends on an origin's cost it received nets to
--      zero for that origin on every account.
--   3. declared placement: in 'Declared Allocation Account' mode every line except
--      a share origin's own relief (a sent line of an `own` hop) is on the run's
--      allocation account; a rate origin's own relief is on it too.
--   4. account balance: per run x account, the net is minus the amounts relieved on
--      the account plus the amounts it receives. The receiving account is the pool's
--      own account in "Sender's Own Accounts" mode (so each account nets to zero)
--      and the allocation account in declared mode. So the pool account is
--      relieved by exactly the origin pools, the allocation account carries all of
--      them, and a rate charge cancels on the allocation account it both leaves and
--      lands on.
--   5. rate mode: a Declared Rate origin in a Sender's Own Accounts run (konsol
--      refuses it, Q6 A; here its charge has no allocation account to land on).
-- A pool is read from the origin's own sent lines (hop_kind = 'own'), which sit on
-- the pool account: one value per run x origin x account; a rate from the same
-- lines on the allocation account, its units from cost_allocation_rate_origins.
-- UNION ALL + GROUP BY and inner joins only: join_use_nulls=0 would fill a
-- missing side with 0.
with runs as (
    select name, receiver_account_mode, allocation_account
    from {{ source('epm_staging', 'cost_allocation_runs') }}
),

rate_origins as (
    {{ cost_allocation_rate_origins() }}
),

lines as (
    select
        l.run as run, l.main_account as main_account, l.member as member,
        l.line_type as line_type, l.hop_kind as hop_kind, l.basis as basis,
        l.origin_member as origin_member,
        l.sender_member as sender_member, l.origin_amount as origin_amount,
        l.amount as amount,
        r.receiver_account_mode = 'Declared Allocation Account' as declared,
        r.allocation_account as allocation_account
    from {{ ref('gold_cost_allocation') }} as l
    inner join runs as r on r.name = l.run
),

own_sent as (
    select
        run, origin_member, main_account, basis,
        max(origin_amount) as origin_amount,
        any(declared) as declared, any(allocation_account) as allocation_account
    from lines
    where line_type = 'sent' and hop_kind = 'own'
    group by run, origin_member, main_account, basis
),

-- what relieves the origin on that account: the pool, or rate x units
pools as (
    select run, origin_member, main_account, declared, allocation_account, toDecimal128(origin_amount, 16) as pool
    from own_sent
    where basis != 'Declared Rate'

    union all

    select o.run, o.origin_member, o.main_account, o.declared, o.allocation_account,
           o.origin_amount * ro.units as pool
    from own_sent as o
    inner join rate_origins as ro on ro.run = o.run and ro.origin_member = o.origin_member
    where o.basis = 'Declared Rate'
),

passers as (
    select distinct run, origin_member, sender_member
    from lines
    where line_type = 'sent' and hop_kind != 'own' and sender_member != origin_member
),

relief as (
    select run, main_account, origin_member, sum(net) as net, sum(pool) as pool
    from (
        select run, main_account, origin_member, sum(amount) as net, toDecimal128(0, 16) as pool
        from lines
        where member = origin_member and not (basis = 'Declared Rate' and line_type = 'received')
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
    where declared
        and (not (line_type = 'sent' and hop_kind = 'own') or basis = 'Declared Rate')
        and main_account != allocation_account
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
),

rate_in_own_accounts as (
    select distinct run, origin_member
    from lines
    where basis = 'Declared Rate' and not declared
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

union all

select run, '', origin_member, origin_member,
       'declared rate in Sender''s Own Accounts mode: the charge needs the allocation account',
       toDecimal128(0, 16), toDecimal128(0, 16)
from rate_in_own_accounts
