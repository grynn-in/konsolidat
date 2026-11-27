{# Cost allocation lines (konsol#269). One computation, shared by the live model
   (gold_cost_allocation, W3) and the frozen model (W5): the caller says which
   runs to compute (`runs_predicate`, a SQL condition on the alias `r`, a row of
   epm_staging.cost_allocation_runs) and what to stamp in frozen_at.

   Origins. Every sender in a run is an origin whose own cost the lines distribute.
   Its basis (2b-2, konsol#269 Q5 5B; plan section 3) is what its weight rows in
   cost_allocation_run_weights declare:
     - 'Share of Pool' (every origin before 2b-2): origin_amount is the origin's
       POOL, the run's accounts in gold_scenario_trial_balance per origin member and
       account (`pool_account`), one set of lines per account. The coefficients are
       shares of 1.
     - 'Declared Rate': origin_amount is the RATE the run snapshotted (one per rate
       step, 4 places), and the coefficients are in DRIVER UNITS (the own hop's
       pool_coefficient is the step's total units, each receiver's coefficient its
       units), so x = rate x units exactly. The origin's pool stays on its own
       accounts, untouched: it is a sink for cost that reaches it (no pass rows), and
       pool + received - charged is its absorption variance, reported by its own
       model (Q5 A). Its lines sit on the run's ALLOCATION ACCOUNT, pool_account
       included (Q6 A: a rate rule needs Declared Allocation Account mode; a rate
       origin in a Sender's Own Accounts run gets allocation_account '' here and
       assert_cost_allocation_balanced_per_account names it).
   The member is read from the run's allocation_dimension by a multiIf generated
   over the budget dimensions, so no dimension name is written here; an
   allocation_dimension that is not a budget dimension reads as '' and matches no
   coefficient (T3, W4, flags it).

   Per coefficient row (a hop) two lines carry the same x = origin_amount *
   coefficient: `sent` (-x at the sender) and `received` (+x at the receiver), so
   they cancel exactly. x is Decimal(38,4) * Decimal(38,12) = Decimal(38,16), exact
   (casting both operands to scale 16 first leaves 6 integer digits: 10,000,000 x
   0.5 overflowed silently, review H1).
   Accounts:
     - received: the pool account in "Sender's Own Accounts" mode, the run's
       allocation_account in 'Declared Allocation Account' mode;
     - sent on an `own` hop (hop_kind = 'own', the origin's relief of its pool): the
       pool account, always (for a rate origin that IS the allocation account);
     - sent on a `pass` hop (hop_kind = 'pass'; the sender may be the origin itself in
       a Reciprocal solve): the account the sender
       received the cost on, so its received and sent lines net to zero there
       (review H2: booking it on the pool account over-relieved the pool account).
     - any other hop_kind goes to NEITHER account: the line is booked on the marker
       account `?hop_kind`, so balanced_per_account fails loudly, and
       assert_cost_allocation_hop_kind_valid names the row (RF5, review finding 6).
   pool_account is on every line, so the lines of two pools that share an account
   (every received line in declared mode) stay apart (review M1). `basis` is on
   every line too, so a test can tell a rate (origin_amount) from a pool.

   Worked example, share of pool. IT pool 1000 and HR pool 400 on 6000; allocation
   account 6999. Coefficients: IT -> HR .2, P1 .5, P2 .3 (step 1); HR passes on its
   .2 of IT as P1 .125, P2 .075, and its own pool as P1 .625, P2 .375 (step 2).
     Own accounts, all on 6000:
       IT  -200 -500 -300                      = -1000  (relieved by its pool)
       HR  +200 (from IT) -125 -75 (passed on)  =     0 for IT; -250 -150 = -400 own
       P1  +500 +125 +250 = +875; P2 +300 +75 +150 = +525. 6000 nets 0.
     Declared, allocation account 6999:
       6000: IT -1000, HR -400                       = -1400, exactly the pools;
       6999: HR +200 -125 -75 = 0, P1 +875, P2 +525  = +1400, all received cost.
   Worked example, declared rate (plan section 3). IT charges 50 per ticket, tickets
   HR 5, Sales 8, Ops 6 (pool 1000 on 6000); HR (share, pool 400) splits 5/8 : 3/8.
   IT's coefficients: own pool 19, HR 5, Sales 8, Ops 6; HR passes IT's 5 units on
   as Sales 3.125, Ops 1.875. origin_amount for IT is 50:
       6999: IT -250 -400 -300 = -950 (relief on the allocation account);
             HR +250 -156.25 -93.75 = 0; Sales +400 +156.25 +250 = 806.25;
             Ops +300 +93.75 +150 = 543.75.    6000: HR -400; IT untouched (1000).
       IT's absorption variance: 1000 + 0 - 950 = 50 (under-absorbed).
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
   rows (alias r inside). Shared by the lines and by the drift test (T6). Rate
   origins are INCLUDED (their pool is real, it feeds the absorption variance);
   the lines macro and the tests leave them out with cost_allocation_rate_origins. #}
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

{# The Declared Rate origins per run (2b-2): one row per (run, sender) whose weight
   rows carry basis = 'Declared Rate', with the step's rate (Decimal(38,4), as konsol
   snapshotted it) and `units`, the sum of the step's driver units (Decimal(38,12),
   the coefficients' scale, so rate x units is Decimal(38,16) like every hop
   amount). konsol writes one rate on every row of a rate step; the rows of a step
   that disagree are named by assert_cost_allocation_basis_valid, and max() here
   picks one of them so the lines still build and that test fails loudly.
   `runs_cte`, when given, restricts the rows to the runs of that CTE (alias r).
   Shared by the lines macro and by every test that must tell a rate origin from a
   share origin (coefficients_close, balanced_per_account, frozen_drift, amounts,
   hop_kind_valid, basis_valid); a test that reads lines alone uses their `basis`. #}
{% macro cost_allocation_rate_origins(runs_cte=none) %}
    select
        w.parent as run,
        w.sender_member as origin_member,
        min(w.step) as step,
        max(w.rate) as rate,
        {{ cast_to_decimal128('sum(w.driver_value)', 12) }} as units
    from {{ source('epm_staging', 'cost_allocation_run_weights') }} as w
    {%- if runs_cte %}
    inner join {{ runs_cte }} as r on r.name = w.parent
    {%- endif %}
    where w.basis = 'Declared Rate'
    group by w.parent, w.sender_member
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

rate_origins as (
    {{ cost_allocation_rate_origins('runs') }}
),

{# One row per origin and account to distribute: a share origin's pools, each on
   its own account with the pool as origin_amount; a rate origin once, on the
   run's allocation account, with the rate as origin_amount. A rate origin's pools
   are left out: its lines never carry its pool. #}
origins as (
    select
        p.run as run,
        p.origin_member as origin_member,
        p.main_account as pool_account,
        p.origin_amount as origin_amount,
        'Share of Pool' as basis
    from pools as p
    where (p.run, p.origin_member) not in (select run, origin_member from rate_origins)

    union all

    select
        ro.run as run,
        ro.origin_member as origin_member,
        r.allocation_account as pool_account,
        ro.rate as origin_amount,
        'Declared Rate' as basis
    from rate_origins as ro
    inner join runs as r
        on r.name = ro.run
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
        o.pool_account as pool_account,
        o.origin_amount as origin_amount,
        o.basis as basis,
        c.origin_member as origin_member,
        c.step as step,
        c.sender_member as sender_member,
        c.receiver_member as receiver_member,
        c.driver as driver,
        c.hop_kind as hop_kind,
        c.coefficient as coefficient,
        o.origin_amount * c.coefficient as hop_amount
    from runs as r
    inner join origins as o
        on o.run = r.name
    inner join {{ source('epm_staging', 'cost_allocation_coefficients') }} as c
        on c.run = r.name
        and c.origin_member = o.origin_member
),

lines as (
    select
        run, rule_set, method, scenario_id, data_area_id, fiscal_year, fiscal_period,
        multiIf(
            hop_kind = 'own', pool_account,
            hop_kind = 'pass', if(receiver_account_mode = 'Declared Allocation Account',
                                  allocation_account, pool_account),
            '?hop_kind') as main_account,
        pool_account,
        allocation_dimension,
        sender_member as member,
        'sent' as line_type,
        hop_kind,
        basis,
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
        hop_kind,
        basis,
        origin_member, sender_member, receiver_member, driver, step, coefficient, origin_amount,
        hop_amount as amount
    from hops
)

select
    run, rule_set, method, scenario_id, data_area_id, main_account, pool_account,
    allocation_dimension, member, line_type, hop_kind, basis, origin_member, sender_member, receiver_member,
    driver, fiscal_year, fiscal_period, step, coefficient, origin_amount,
    toDecimal128(amount, 16) as amount,
    {{ frozen_at_expr }} as frozen_at
from lines
{% endmacro %}


{#- RF8: backfill hop_kind on frozen rows written by phase 1 (sender = origin -> 'own',
    else 'pass'), only when a blank row exists. An ALTER ... UPDATE is a mutation that
    rewrites parts, so it must not run on every incremental build. Runs as a pre_hook,
    after the ADD COLUMN hook. The UPDATE is executed here and the macro returns an empty
    string, which dbt skips as a hook. mutations_sync = 2 waits on every replica. -#}
{% macro cost_allocation_backfill_hop_kind(relation) %}
    {%- if execute -%}
        {%- set blank = run_query("select count() from " ~ relation ~ " where hop_kind = ''") -%}
        {%- if blank.columns[0].values()[0] | int > 0 -%}
            {%- do run_query("ALTER TABLE " ~ relation ~ " UPDATE hop_kind = if(sender_member = origin_member, 'own', 'pass') WHERE hop_kind = '' SETTINGS mutations_sync = 2") -%}
        {%- endif -%}
    {%- endif -%}
{% endmacro %}


{# Absorption variance of a Declared Rate sender (konsol#269 2b-2 W6/W7; Q5 A, Deepak
   Pai 27 Nov 2026: its own model per rate sender, never variance lines). One row per
   run x rate sender, shared by gold_cost_allocation_absorption (Follow Latest Data
   runs) and gold_cost_allocation_absorption_frozen (Freeze at Approval runs, appended
   once): the caller says which runs (`runs_predicate`, a condition on alias `r`), which
   lines table its received lines come from (`lines_relation`: the live union for the
   live model, the frozen table for the frozen one, so a frozen row reads frozen lines)
   and what to stamp in frozen_at.
     rate, units  the rate step's rate and sum of driver units (cost_allocation_rate_origins);
     pool         the sender's trial balance on the run's accounts (cost_allocation_pools,
                  summed over its accounts), which its lines never carry;
     received     the `received` lines at the sender, of every origin: under Reciprocal
                  a rate sender is an exit of the solve, so cost that reaches it stops
                  there, its own returning units included (ZZEQ: 50 of ZZIT's own, 80 of
                  ZZHR's, 75 of ZZFM's = 205);
     charged      rate x units, exactly what its own `sent` lines relieve;
     variance     pool + received - charged: positive = under-absorbed, negative = over-.
   UNION ALL + GROUP BY, not joins, so a sender with no trial balance rows or no
   received line still gets its row with 0 there (join_use_nulls=0 would also give 0
   across a LEFT JOIN, but silently). Decimal(38,16) throughout: pool is at the amount
   scale (4), rate (4) x units (12) is exact at 16. #}
{% macro cost_allocation_absorption(runs_predicate, lines_relation, frozen_at_expr) %}
with runs as (
    select *
    from {{ source('epm_staging', 'cost_allocation_runs') }} as r
    where {{ runs_predicate }}
),

rate_origins as (
    {{ cost_allocation_rate_origins('runs') }}
),

pools as (
    {{ cost_allocation_pools('runs') }}
),

parts as (
    select run, origin_member as member, toDecimal128(0, {{ amount_scale() }}) as pool, toDecimal128(0, 16) as received
    from rate_origins

    union all

    select p.run, p.origin_member, p.origin_amount, toDecimal128(0, 16)
    from pools as p
    where (p.run, p.origin_member) in (select run, origin_member from rate_origins)

    union all

    select l.run, l.receiver_member, toDecimal128(0, {{ amount_scale() }}), l.amount
    from {{ lines_relation }} as l
    where l.line_type = 'received'
      and (l.run, l.receiver_member) in (select run, origin_member from rate_origins)
),

absorbed as (
    select run, member, sum(pool) as pool, sum(received) as received
    from parts
    group by run, member
)

select
    r.name as run,
    r.rule_set as rule_set,
    r.method as method,
    r.scenario_id as scenario_id,
    r.data_area_id as data_area_id,
    r.fiscal_year as fiscal_year,
    r.fiscal_period as fiscal_period,
    r.allocation_dimension as allocation_dimension,
    r.allocation_account as allocation_account,
    ro.origin_member as sender_member,
    ro.step as step,
    ro.rate as rate,
    ro.units as units,
    toDecimal128(a.pool, {{ amount_scale() }}) as pool,
    toDecimal128(a.received, 16) as received,
    toDecimal128(ro.rate * ro.units, 16) as charged,
    toDecimal128(toDecimal128(a.pool, 16) + a.received - ro.rate * ro.units, 16) as variance,
    {{ frozen_at_expr }} as frozen_at
from rate_origins as ro
inner join runs as r
    on r.name = ro.run
inner join absorbed as a
    on a.run = ro.run
    and a.member = ro.origin_member
{% endmacro %}
