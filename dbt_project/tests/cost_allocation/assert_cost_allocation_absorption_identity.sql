-- The absorption variance is an identity, not an estimate (konsol#269 2b-2 W6).
-- Q5 A (Deepak Pai, 27 Nov 2026): gold_cost_allocation_absorption reports, per run x
-- Declared Rate sender, pool + received - charged. This test pins three things, exactly,
-- in Decimal(38,16), with the frozen rows included on both sides:
--   1. `variance`: every row's variance = pool + received - charged;
--   2. `charged`: every row's charged = rate x units;
--   3. `run_balance`: per run with a rate sender, the money balances across the two
--      tables:  sum(received lines at the FINAL receivers) + sum(variance)
--             = sum(share senders' pools) + sum(rate senders' pools).
-- Why 3 holds, given the lines' semantics. Every hop is a sent and a received line of
-- the same amount, so a run's lines sum to zero. Group the members: a share sender's
-- net is -pool (its own relief, and it passes on everything it receives: that is what
-- assert_cost_allocation_conserved pins); a rate sender's net is received - charged
-- (its relief is rate x units, it passes nothing on, and under Reciprocal it is an exit
-- of the solve, so cost that reaches it stops there, its own returning units included);
-- a final receiver's net is what it received. Zero total gives
--   final received + sum(received - charged) = sum(share pools), and with
--   variance = pool + received - charged that is the balance above.
-- The share pools are read from the lines (max origin_amount per own sent line, per
-- account), the rate pools from the absorption rows, so a frozen run balances against
-- its own frozen numbers and a trial balance that moved since does not fire this test
-- (that is assert_cost_allocation_absorption_frozen_drift's job). 1 and 2 cannot fire
-- on a build of the shipped macro; they are the tripwire for a macro change and fire on
-- a seeded table. 3 fires on a real build when the rows disagree with the lines: a rate
-- sender the model dropped or counted twice, a charge that is not what its lines relieve
-- (a coefficient set whose units differ from the weights'), received cost not read.
-- Worked examples (plan section 3): ZZER 1,350 + 50 = 1,400; ZZEQ (Reciprocal) 1,445 +
-- 255 = 1,700. Rows returned are violations, with the rule, what was got and what the
-- identity wants. UNION ALL + GROUP BY, no join: join_use_nulls=0 would fill a side with 0.
{{ config(severity='error') }}
with absorption as (
    select * from {{ ref('gold_cost_allocation_absorption') }}
),

lines as (
    select * from {{ ref('gold_cost_allocation') }}
),

senders as (
    select distinct run, sender_member from lines where line_type = 'sent'
),

rate_runs as (
    select distinct run from lines where basis = 'Declared Rate'
    union distinct
    select distinct run from absorption
),

row_checks as (
    select run, sender_member, 'variance' as rule,
           variance as got,
           toDecimal128(toDecimal128(pool, 16) + received - charged, 16) as want
    from absorption
    where variance != toDecimal128(pool, 16) + received - charged

    union all

    select run, sender_member, 'charged' as rule,
           charged as got,
           toDecimal128(rate * units, 16) as want
    from absorption
    where charged != rate * units
),

parts as (
    select run,
           toDecimal128(sum(amount), 16) as final_received,
           toDecimal128(0, 16) as variance_total,
           toDecimal128(0, 16) as pools
    from lines
    where line_type = 'received'
      and (run, receiver_member) not in (select run, sender_member from senders)
    group by run

    union all

    select run, toDecimal128(0, 16), toDecimal128(sum(variance), 16), toDecimal128(sum(toDecimal128(pool, 16)), 16)
    from absorption
    group by run

    union all

    select run, toDecimal128(0, 16), toDecimal128(0, 16), toDecimal128(sum(account_pool), 16)
    from (
        select run, origin_member, main_account, max(origin_amount) as account_pool
        from lines
        where line_type = 'sent' and hop_kind = 'own' and basis = 'Share of Pool'
        group by run, origin_member, main_account
    )
    group by run
),

run_checks as (
    select run, '' as sender_member, 'run_balance' as rule,
           toDecimal128(sum(final_received) + sum(variance_total), 16) as got,
           toDecimal128(sum(pools), 16) as want
    from parts
    where run in (select run from rate_runs)
    group by run
    having got != want
)

select run, sender_member, rule, got, want from row_checks
union all
select run, sender_member, rule, got, want from run_checks
