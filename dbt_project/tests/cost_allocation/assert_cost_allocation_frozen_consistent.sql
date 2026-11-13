{{ config(severity='error') }}
-- Cost allocation lines agree with their run (konsol#269, W5). Three ways the
-- published lines can disagree with epm_staging.cost_allocation_runs:
--   1. duplicate line: the same hop appears twice (a frozen run frozen again);
--   2. run not in staging: lines of a cancelled run were not removed;
--   3. freeze stamp does not match the policy: a 'Freeze at Approval' run
--      with a NULL frozen_at, or a 'Follow Latest Data' run with one.
-- Inner joins and IN only: join_use_nulls=0 would fill an unmatched side.
with lines as (
    select * from {{ ref('gold_cost_allocation') }}
),

runs as (
    select name, amounts_after_approval
    from {{ source('epm_staging', 'cost_allocation_runs') }}
)

select run, 'duplicate line' as problem
from lines
group by run, main_account, origin_member, step, sender_member, receiver_member, line_type
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
