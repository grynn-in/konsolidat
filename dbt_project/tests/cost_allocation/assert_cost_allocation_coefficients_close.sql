-- Allocation coefficients close (konsol#269, T5; generalised for declared rates,
-- 2b-2 W4b). Per run, origin member, step, sender and hop kind, the receivers'
-- coefficients sum to the hop's pool_coefficient exactly (konsol rounds to 12
-- places by largest remainder so they do). A hop whose rows disagree about
-- pool_coefficient is flagged too. The origin's own relief is the `own` hops
-- (hop_kind = 'own'): per run and origin their pool_coefficients sum to exactly
--   - 1 for a Share of Pool origin, because it sends its whole pool there;
--   - the step's total driver units for a Declared Rate origin (the sum of
--     driver_value over its weight rows with basis = 'Declared Rate'), because its
--     coefficients are in units and each receiver's is its own units.
-- A hop that closes against another total would still lose or invent money. A
-- `pass` hop may have the origin as its sender (Reciprocal); it is not own relief
-- and its pool_coefficient is not 1. The rate origins and their units come from
-- cost_allocation_rate_origins (macros/cost_allocation.sql), the rule the lines use.
-- The own-sum rows carry the origin's own total in coefficient_sum and the expected
-- total in pool_coefficient_min / _max, with step 0 and a blank sender.
-- UNION ALL + GROUP BY, not a join: join_use_nulls=0 would fill a missing side with 0.
with hops as (
    select
        run, origin_member, step, sender_member, hop_kind,
        sum(coefficient) as coefficient_sum,
        min(pool_coefficient) as pool_coefficient_min,
        max(pool_coefficient) as pool_coefficient_max
    from {{ source('epm_staging', 'cost_allocation_coefficients') }}
    group by run, origin_member, step, sender_member, hop_kind
),

own as (
    select run, origin_member, sum(pool_coefficient_max) as own_total
    from hops
    where hop_kind = 'own'
    group by run, origin_member
),

rate_origins as (
    {{ cost_allocation_rate_origins() }}
),

expected as (
    select run, origin_member, toDecimal128(1, 12) as expected_total
    from own
    where (run, origin_member) not in (select run, origin_member from rate_origins)

    union all

    select run, origin_member, units as expected_total
    from rate_origins
    where (run, origin_member) in (select run, origin_member from own)
)

select run, origin_member, step, sender_member, coefficient_sum, pool_coefficient_min, pool_coefficient_max
from hops
where coefficient_sum != pool_coefficient_max
    or pool_coefficient_min != pool_coefficient_max

union all

select
    run, origin_member, toUInt16(0) as step, '' as sender_member,
    sum(own_total) as coefficient_sum,
    sum(expected_total) as pool_coefficient_min,
    sum(expected_total) as pool_coefficient_max
from (
    select run, origin_member, own_total, toDecimal128(0, 12) as expected_total from own
    union all
    select run, origin_member, toDecimal128(0, 12), expected_total from expected
)
group by run, origin_member
having coefficient_sum != pool_coefficient_max
