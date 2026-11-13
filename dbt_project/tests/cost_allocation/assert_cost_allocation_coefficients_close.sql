-- Allocation coefficients close (konsol#269, T5). Per run, origin member, step
-- and sender, the receivers' coefficients sum to the hop's pool_coefficient
-- exactly (konsol rounds to 12 places by largest remainder so they do). A hop
-- whose rows disagree about pool_coefficient is flagged too.
select
    run, origin_member, step, sender_member,
    sum(coefficient) as coefficient_sum,
    min(pool_coefficient) as pool_coefficient_min,
    max(pool_coefficient) as pool_coefficient_max
from {{ source('epm_staging', 'cost_allocation_coefficients') }}
group by run, origin_member, step, sender_member
having coefficient_sum != pool_coefficient_max
    or pool_coefficient_min != pool_coefficient_max
