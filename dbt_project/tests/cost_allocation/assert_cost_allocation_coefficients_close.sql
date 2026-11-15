-- Allocation coefficients close (konsol#269, T5). Per run, origin member, step,
-- sender and hop kind, the receivers' coefficients sum to the hop's pool_coefficient
-- exactly (konsol rounds to 12 places by largest remainder so they do). A hop
-- whose rows disagree about pool_coefficient is flagged too. The origin's own
-- relief is the `own` hops (hop_kind = 'own'): per run and origin their
-- pool_coefficients sum to exactly 1, because the origin sends its whole pool
-- there, and a hop that closes against another pool would still lose or invent
-- money. A `pass` hop may have the origin as its sender (Reciprocal); it is not
-- own relief and its pool_coefficient is not 1.
with hops as (
    select
        run, origin_member, step, sender_member, hop_kind,
        sum(coefficient) as coefficient_sum,
        min(pool_coefficient) as pool_coefficient_min,
        max(pool_coefficient) as pool_coefficient_max
    from {{ source('epm_staging', 'cost_allocation_coefficients') }}
    group by run, origin_member, step, sender_member, hop_kind
)

select run, origin_member, step, sender_member, coefficient_sum, pool_coefficient_min, pool_coefficient_max
from hops
where coefficient_sum != pool_coefficient_max
    or pool_coefficient_min != pool_coefficient_max

union all

select
    run, origin_member, toUInt16(0) as step, '' as sender_member,
    sum(h.pool_coefficient_max) as coefficient_sum,
    min(h.pool_coefficient_min) as pool_coefficient_min,
    max(h.pool_coefficient_max) as pool_coefficient_max
from hops as h
where h.hop_kind = 'own'
group by run, origin_member
having sum(h.pool_coefficient_max) != 1
