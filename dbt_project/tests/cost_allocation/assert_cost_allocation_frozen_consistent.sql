-- Cost allocation lines agree with their run (konsol#269, W5). Three ways the
-- published lines can disagree with epm_staging.cost_allocation_runs:
--   1. duplicate line: the same hop of the same pool appears twice (a frozen run
--      frozen again). pool_account is in the key: in declared mode the received
--      lines of two pools share the allocation account (review M1). hop_kind is in
--      the key too (konsol#269 RC6): under Reciprocal one sender sends to one
--      receiver at one step twice, once as `own` and once as `pass` (origin IT's
--      own unit and the cost HR returned to IT, both to HR at step 1), and those are
--      two lines, not a duplicate;
--   2. run not in staging: lines of a cancelled run were not removed;
--   3. freeze stamp does not match the policy: a 'Freeze at Approval' run
--      with a NULL frozen_at, or a 'Follow Latest Data' run with one.
-- Inner joins and IN only: join_use_nulls=0 would fill an unmatched side.
{{ config(severity='error') }}
with lines as (
    select * from {{ ref('gold_cost_allocation') }}
),

runs as (
    select name, amounts_after_approval
    from {{ source('epm_staging', 'cost_allocation_runs') }}
)

select run, 'duplicate line' as problem
from lines
group by run, main_account, pool_account, origin_member, step, sender_member, receiver_member, line_type, hop_kind
having count() > 1

union all

select distinct run, 'run not in staging' as problem
from lines
where run not in (select name from runs)

union all

select distinct l.run, 'freeze stamp does not match the run policy' as problem
from lines as l
inner join runs as r on r.name = l.run
where (r.amounts_after_approval = 'Freeze at Approval' and l.frozen_at is null)
   or (r.amounts_after_approval = 'Follow Latest Data' and l.frozen_at is not null)
