-- A line's basis is the one its origin's weight rows declare (konsol#269 2b-2 W5).
-- The macro writes basis 'Declared Rate' on every line of an origin whose weight
-- rows in cost_allocation_run_weights carry basis = 'Declared Rate', with the
-- step's rate as origin_amount, and 'Share of Pool' on every other line; the
-- frozen table's column default gives rows frozen before 2b-2 'Share of Pool'. A
-- weight row's basis is 'Share of Pool', 'Declared Rate' or '' (a run synced
-- before 2b-2, read as Share of Pool). Rows returned are violations, one per
-- (run, member, basis, problem):
--   weight: a basis that is none of the three;
--   weight: a Declared Rate step whose rows disagree on the rate, or whose rate is
--           not positive (konsol writes one rate on every row of the step; the
--           lines macro takes max(), so this is where the disagreement is named);
--   line:   a basis that is not 'Share of Pool' or 'Declared Rate';
--   line:   a basis that disagrees with the origin's weight rows (a rate line of a
--           share origin, or a share line of a rate origin);
--   line:   a Declared Rate line whose origin_amount is not a rate the step
--           declares (a pool that leaked into a rate origin's lines).
-- IN / NOT IN, not joins: join_use_nulls=0 would fill a missing side with ''.
with weights as (
    select parent as run, step, sender_member, basis, rate
    from {{ source('epm_staging', 'cost_allocation_run_weights') }}
),

rate_senders as (
    select distinct run, sender_member from weights where basis = 'Declared Rate'
),

lines as (
    select run, origin_member, basis, origin_amount
    from {{ ref('gold_cost_allocation') }}
)

select 'weight' as source, run, sender_member as member, basis,
       'weight basis is not Share of Pool, Declared Rate or blank' as problem
from weights
where basis not in ('Share of Pool', 'Declared Rate', '')
group by run, sender_member, basis

union all

select 'weight', run, sender_member, 'Declared Rate',
       'a Declared Rate step needs one positive rate on every row'
from weights
where basis = 'Declared Rate'
group by run, step, sender_member
having min(rate) != max(rate) or min(rate) <= 0

union all

select 'line', run, origin_member, basis, 'line basis is not Share of Pool or Declared Rate'
from lines
where basis not in ('Share of Pool', 'Declared Rate')
group by run, origin_member, basis

union all

select 'line', run, origin_member, basis, 'line basis disagrees with the origin''s weight rows'
from lines
where (basis = 'Declared Rate') != ((run, origin_member) in (select run, sender_member from rate_senders))
group by run, origin_member, basis

union all

select 'line', run, origin_member, basis,
       concat('origin_amount ', toString(origin_amount), ' is not a rate the step declares')
from lines
where basis = 'Declared Rate'
    and (run, origin_member, origin_amount) not in (
        select run, sender_member, rate from weights where basis = 'Declared Rate')
group by run, origin_member, basis, origin_amount
