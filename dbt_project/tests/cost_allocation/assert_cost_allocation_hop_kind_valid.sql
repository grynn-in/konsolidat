-- hop_kind is `own` or `pass`, and a Declared Rate sender never passes (konsol#269,
-- RF5, review finding 6; 2b-2 W4e). The allocation macro books an `own` hop on the
-- pool account and a `pass` hop on the account the sender received the cost on; any
-- other value, a blank included, is neither, and used to be treated as `pass`
-- without a word. A rate sender's outflow is fixed by its rate (plan section 3): it
-- has its own hop and is a SINK for every origin, so a `pass` row whose sender is a
-- rate sender invents an outflow its rate does not charge. Rows returned are
-- violations: a coefficient row or an allocation line whose hop_kind is not in
-- ('own', 'pass'), or a `pass` row sent by a rate sender. The rate senders are the
-- run's weight rows with basis = 'Declared Rate' (cost_allocation_rate_origins) for
-- the coefficients, and the lines' own basis for the lines.
with rate_origins as (
    {{ cost_allocation_rate_origins() }}
),

rate_line_origins as (
    select distinct run, origin_member
    from {{ ref('gold_cost_allocation') }}
    where basis = 'Declared Rate'
)

select 'coefficient' as source, run, origin_member, sender_member, receiver_member, hop_kind,
       'hop_kind is not own or pass' as problem
from {{ source('epm_staging', 'cost_allocation_coefficients') }}
where hop_kind not in ('own', 'pass')

union all

select 'line', run, origin_member, sender_member, receiver_member, hop_kind,
       'hop_kind is not own or pass'
from {{ ref('gold_cost_allocation') }}
where hop_kind not in ('own', 'pass')

union all

select 'coefficient', run, origin_member, sender_member, receiver_member, hop_kind,
       'a Declared Rate sender passes cost on'
from {{ source('epm_staging', 'cost_allocation_coefficients') }}
where hop_kind = 'pass'
    and (run, sender_member) in (select run, origin_member from rate_origins)

union all

select 'line', run, origin_member, sender_member, receiver_member, hop_kind,
       'a Declared Rate sender passes cost on'
from {{ ref('gold_cost_allocation') }}
where hop_kind = 'pass'
    and (run, sender_member) in (select run, origin_member from rate_line_origins)
