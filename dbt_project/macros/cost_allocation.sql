{# Cost allocation lines (konsol#269). One computation, shared by the live model
   (gold_cost_allocation, W3) and the frozen model (W5): the caller says which
   runs to compute (`runs_predicate`, a SQL condition on the alias `r`, a row of
   epm_staging.cost_allocation_runs) and what to stamp in frozen_at.

   Pool: the run's accounts in gold_scenario_trial_balance, per origin member.
   The member is read from the run's allocation_dimension by a multiIf generated
   over the budget dimensions, so no dimension name is written here; an
   allocation_dimension that is not a budget dimension reads as '' and matches no
   coefficient (T3, W4, flags it).
   Per coefficient row (a hop) two lines: `sent` at the sender, in the pool's
   account, and `received` at the receiver, in the declared allocation account
   when the run says so. Both carry the same x = origin_amount * coefficient, so
   they cancel exactly.
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

{% macro cost_allocation_lines(runs_predicate, frozen_at_expr) %}
with runs as (
    select *
    from {{ source('epm_staging', 'cost_allocation_runs') }} as r
    where {{ runs_predicate }}
),

pools as (
    select
        r.name as run,
        {{ cost_allocation_member_expr('tb') }} as origin_member,
        tb.main_account as main_account,
        {{ cast_to_decimal128('sum(tb.amount)', amount_scale()) }} as origin_amount
    from runs as r
    inner join {{ source('epm_staging', 'cost_allocation_run_accounts') }} as a
        on a.parent = r.name
    inner join {{ ref('gold_scenario_trial_balance') }} as tb
        on tb.scenario_id = r.scenario_id
        and tb.data_area_id = r.data_area_id
        and tb.fiscal_year = r.fiscal_year
        and tb.fiscal_period = r.fiscal_period
        and tb.main_account = a.main_account
    group by r.name, origin_member, tb.main_account
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
        toDecimal128(p.origin_amount, 16) * toDecimal128(c.coefficient, 16) as hop_amount
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
        pool_account as main_account,
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
        allocation_dimension,
        receiver_member as member,
        'received' as line_type,
        origin_member, sender_member, receiver_member, driver, step, coefficient, origin_amount,
        hop_amount as amount
    from hops
)

select
    run, rule_set, method, scenario_id, data_area_id, main_account, allocation_dimension,
    member, line_type, origin_member, sender_member, receiver_member, driver,
    fiscal_year, fiscal_period, step, coefficient, origin_amount,
    toDecimal128(amount, 16) as amount,
    {{ frozen_at_expr }} as frozen_at
from lines
{% endmacro %}
