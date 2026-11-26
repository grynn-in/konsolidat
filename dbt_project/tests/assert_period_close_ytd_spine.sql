{#
    The YTD spine, checked against the file and not against itself: check (b) of the period-close
    family (konsolidat#<this issue>). Proposed on that issue; no decision is recorded yet.

    movement_spine and ytd_movement (macros/period_movements.sql) are the ONE definition of the
    'Year-to-date movement' rule, shared by silver_tb_movements (actuals) and gold_spread_budget
    (budget lines, konsol#348 R10). A YTD file lists only its non-zero keys, so the rule rests on
    the spine: a key present in period N and absent in the next claimed period N+1 of the same fiscal
    year has YTD 0 there and its movement is MINUS its N figure (the reversal); a key absent in N and
    present in N+1 starts from zero, so its movement is its whole N+1 figure; and the first claimed
    period of a year has nothing before it.

    This test re-derives every movement of a 'Year-to-date movement' entity from the claimed batches
    (bronze_trial_balance_submissions) with no window function of the model's and no macro of it:

        expected(key, p) = stated(key, p) - stated(key, previous claimed period of the same year)

    with a missing stated row read as 0, and compares it with the 'activity' movements
    silver_tb_movements emits, per full key (entity, account, partner, <the declared dimensions>) and
    claimed period. A key the spine MISSED has no silver row at all; it is still judged, because the
    expected side carries it (assert_tb_movements_cumulate_to_source judges only rows that exist and
    leaves that case to assert_tb_movements_balance, which sees it only as an unbalanced period).

    Rows returned (ERROR severity), |expected - emitted| > 0.01:
      vanished_key_not_reversed  stated in the previous claimed period, absent now: the reversal is
                                 missing or wrong
      new_key_not_from_zero      absent in the previous claimed period (or the first claimed period of
                                 the year), stated now: it did not start from zero
      ytd_difference             stated in both, and the difference is wrong

    "Previous claimed period" is the entity's previous claimed period of the same fiscal year in
    fiscal_period order, whatever its declared type, exactly the order the model differences in;
    Opening, Closing and Adjustment periods are judged by assert_period_close_integrity.
    Entity-periods are taken at their latest claim's basis, as silver_tb_movements takes them; an
    entity mixing bases is assert_entity_has_one_amount_basis's. The budget's YTD lines are judged
    against their stated figures by assert_budget_ytd_reconciles and assert_budget_ytd_hand_table.
    Fixtures: test_fixtures/assert_period_close_ytd_spine.*.sql
#}

{{ config(severity='error') }}

with periods as (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        amount_basis,
        leadInFrame(toInt32(fiscal_period), 1, toInt32(-1)) over (
            partition by data_area_id, fiscal_year
            order by fiscal_period
            rows between unbounded preceding and unbounded following
        ) as next_period
    from (
        select
            data_area_id,
            toUInt16(fiscal_year) as fiscal_year,
            toUInt16(fiscal_period) as fiscal_period,
            argMax(amount_basis, claimed_at) as amount_basis
        from {{ ref('bronze_trial_balance_submissions') }}
        group by data_area_id, fiscal_year, fiscal_period
    )
),

stated as (
    select
        b.data_area_id as data_area_id,
        toUInt16(b.fiscal_year) as fiscal_year,
        toUInt16(b.fiscal_period) as fiscal_period,
        b.main_account as main_account,
        b.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='b.', trailing=true) }}
        p.next_period as next_period,
        toDecimal128(sum(b.debit_amount - b.credit_amount), {{ amount_scale() }}) as stated_amount
    from {{ ref('bronze_trial_balance_submissions') }} as b
    inner join periods as p
        on p.data_area_id = b.data_area_id
        and p.fiscal_year = toUInt16(b.fiscal_year)
        and p.fiscal_period = toUInt16(b.fiscal_period)
    where p.amount_basis = 'Year-to-date movement'
    group by
        b.data_area_id, fiscal_year, fiscal_period, b.main_account, b.partner_data_area_id
        {{- dim_group_by(prefix='b.', leading=true) }}, p.next_period
),

legs as (
    {# + the figure stated in this period #}
    select
        data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id,
        {{ dim_select(trailing=true) }}
        stated_amount as amount,
        toUInt8(1) as stated_here,
        toUInt8(0) as stated_before
    from stated

    union all

    {# - the same key's figure, carried to the next claimed period of the year #}
    select
        data_area_id, fiscal_year, toUInt16(next_period) as fiscal_period, main_account, partner_data_area_id,
        {{ dim_select(trailing=true) }}
        -stated_amount as amount,
        toUInt8(0) as stated_here,
        toUInt8(1) as stated_before
    from stated
    where next_period >= 0

    union all

    {# - what the model emitted #}
    select
        m.data_area_id as data_area_id,
        toUInt16(m.fiscal_year) as fiscal_year,
        toUInt16(m.fiscal_period) as fiscal_period,
        m.main_account as main_account,
        m.partner_data_area_id as partner_data_area_id,
        {{ dim_select(prefix='m.', trailing=true) }}
        toDecimal128(-m.movement_amount, {{ amount_scale() }}) as amount,
        toUInt8(0) as stated_here,
        toUInt8(0) as stated_before
    from {{ ref('silver_tb_movements') }} as m
    where m.movement_kind = 'activity'
      and m.amount_basis = 'Year-to-date movement'
)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    partner_data_area_id,
    {{ dim_select(trailing=true) }}
    sum(amount) as unexplained_movement,
    multiIf(
        max(stated_before) = 1 and max(stated_here) = 0, 'vanished_key_not_reversed',
        max(stated_here) = 1 and max(stated_before) = 0, 'new_key_not_from_zero',
        'ytd_difference'
    ) as reason
from legs
group by data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id{{ dim_group_by(leading=true) }}
having abs(sum(amount)) > 0.01
