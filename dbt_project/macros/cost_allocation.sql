{# Cost allocation lines (konsol#269). One computation, shared by the live model
   (gold_cost_allocation, W3) and the frozen model (W5): the caller says which
   runs to compute (`runs_predicate`, a SQL condition on the alias `r`, a row of
   epm_staging.cost_allocation_runs) and what to stamp in frozen_at.

   Pool: the run's accounts in gold_scenario_trial_balance, per origin member and
   account (`pool_account`). The member is read from the run's allocation_dimension
   by a multiIf generated over the budget dimensions, so no dimension name is
   written here; an allocation_dimension that is not a budget dimension reads as ''
   and matches no coefficient (T3, W4, flags it).

   Per coefficient row (a hop) two lines carry the same x = origin_amount *
   coefficient: `sent` (-x at the sender) and `received` (+x at the receiver), so
   they cancel exactly. x is Decimal(38,4) * Decimal(38,12) = Decimal(38,16), exact
   (casting both operands to scale 16 first leaves 6 integer digits: 10,000,000 x
   0.5 overflowed silently, review H1).
   Accounts:
     - received: the pool account in "Sender's Own Accounts" mode, the run's
       allocation_account in 'Declared Allocation Account' mode;
     - sent at the origin itself (sender = origin): the pool account, always; this
       is the relief of the origin's pool;
     - sent by a pass-through sender (sender != origin): the account the sender
       received the cost on, so its received and sent lines net to zero there
       (review H2: booking it on the pool account over-relieved the pool account).
   pool_account is on every line, so the lines of two pools that share an account
   (every received line in declared mode) stay apart (review M1).

   Worked example. IT pool 1000 and HR pool 400 on 6000; allocation account 6999.
   Coefficients: IT -> HR .2, P1 .5, P2 .3 (step 1); HR passes on its .2 of IT as
   P1 .125, P2 .075, and its own pool as P1 .625, P2 .375 (step 2).
     Own accounts, all on 6000:
       IT  -200 -500 -300                      = -1000  (relieved by its pool)
       HR  +200 (from IT) -125 -75 (passed on)  =     0 for IT; -250 -150 = -400 own
       P1  +500 +125 +250 = +875; P2 +300 +75 +150 = +525. 6000 nets 0.
     Declared, allocation account 6999:
       6000: IT -1000, HR -400                       = -1400, exactly the pools;
       6999: HR +200 -125 -75 = 0, P1 +875, P2 +525  = +1400, all received cost.
   assert_cost_allocation_balanced_per_account checks this per account and member.
   Inner joins only: join_use_nulls=0 would fill an unmatched side with defaults. #}
{% macro cost_allocation_member_expr(alias='tb') %}
    {%- set dims = get_budget_dimensions() -%}
    {%- if dims | length == 0 -%}
    ''
    {%- else -%}
    multiIf(
    {%- for d in dims %}
        r.allocation_dimension = '{{ d.name }}', {{ alias }}.{{ d.name }},
    {%- endfor %}
        '')
    {%- endif -%}
{% endmacro %}

{# The pool per (run, origin member, account): the run's accounts in
   gold_scenario_trial_balance. `runs_cte` names a CTE of cost_allocation_runs
   rows (alias r inside). Shared by the lines and by the drift test (T6). #}
{% macro cost_allocation_pools(runs_cte) %}
    select
        r.name as run,
        {{ cost_allocation_member_expr('tb') }} as origin_member,
        tb.main_account as main_account,
        {{ cast_to_decimal128('sum(tb.amount)', amount_scale()) }} as origin_amount
    from {{ runs_cte }} as r
    inner join {{ source('epm_staging', 'cost_allocation_run_accounts') }} as a
        on a.parent = r.name
    inner join {{ ref('gold_scenario_trial_balance') }} as tb
        on tb.scenario_id = r.scenario_id
        and tb.data_area_id = r.data_area_id
        and tb.fiscal_year = r.fiscal_year
        and tb.fiscal_period = r.fiscal_period
        and tb.main_account = a.main_account
    group by r.name, origin_member, tb.main_account
{% endmacro %}

{% macro cost_allocation_lines(runs_predicate, frozen_at_expr) %}
with runs as (
    select *
    from {{ source('epm_staging', 'cost_allocation_runs') }} as r
    where {{ runs_predicate }}
),

pools as (
    {{ cost_allocation_pools('runs') }}
),

hops as (
    select
        r.name as run,
        r.rule_set as rule_set,
        r.method as method,
        r.scenario_id as scenario_id,
        r.data_area_id as data_area_id,
        r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period,
        r.allocation_dimension as allocation_dimension,
        r.receiver_account_mode as receiver_account_mode,
        r.allocation_account as allocation_account,
        p.main_account as pool_account,
        p.origin_amount as origin_amount,
        c.origin_member as origin_member,
        c.step as step,
        c.sender_member as sender_member,
        c.receiver_member as receiver_member,
        c.driver as driver,
        c.coefficient as coefficient,
        p.origin_amount * c.coefficient as hop_amount
    from runs as r
    inner join pools as p
        on p.run = r.name
    inner join {{ source('epm_staging', 'cost_allocation_coefficients') }} as c
        on c.run = r.name
        and c.origin_member = p.origin_member
),

lines as (
    select
        run, rule_set, method, scenario_id, data_area_id, fiscal_year, fiscal_period,
        if(sender_member != origin_member and receiver_account_mode = 'Declared Allocation Account',
           allocation_account, pool_account) as main_account,
        pool_account,
        allocation_dimension,
        sender_member as member,
        'sent' as line_type,
        origin_member, sender_member, receiver_member, driver, step, coefficient, origin_amount,
        -hop_amount as amount
    from hops

    union all

    select
        run, rule_set, method, scenario_id, data_area_id, fiscal_year, fiscal_period,
        if(receiver_account_mode = 'Declared Allocation Account', allocation_account, pool_account) as main_account,
        pool_account,
        allocation_dimension,
        receiver_member as member,
        'received' as line_type,
        origin_member, sender_member, receiver_member, driver, step, coefficient, origin_amount,
        hop_amount as amount
    from hops
)

select
    run, rule_set, method, scenario_id, data_area_id, main_account, pool_account,
    allocation_dimension, member, line_type, origin_member, sender_member, receiver_member,
    driver, fiscal_year, fiscal_period, step, coefficient, origin_amount,
    toDecimal128(amount, 16) as amount,
    {{ frozen_at_expr }} as frozen_at
from lines
{% endmacro %}
