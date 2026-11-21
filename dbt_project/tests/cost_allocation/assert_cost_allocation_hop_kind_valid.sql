-- hop_kind is `own` or `pass` (konsol#269, RF5, review finding 6). The allocation
-- macro books an `own` hop on the pool account and a `pass` hop on the account the
-- sender received the cost on; any other value, a blank included, is neither, and
-- used to be treated as `pass` without a word. Rows returned are violations: a
-- coefficient row or an allocation line whose hop_kind is not in ('own', 'pass').
select 'coefficient' as source, run, origin_member, sender_member, receiver_member, hop_kind
from {{ source('epm_staging', 'cost_allocation_coefficients') }}
where hop_kind not in ('own', 'pass')

union all

select 'line', run, origin_member, sender_member, receiver_member, hop_kind
from {{ ref('gold_cost_allocation') }}
where hop_kind not in ('own', 'pass')
