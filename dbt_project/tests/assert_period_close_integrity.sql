{#
    A period close is a boundary, not a posting: checks (a), (d) and (e) of the period-close family
    (konsolidat#<this issue>). Proposed on that issue; no decision is recorded yet.

    The year end has a stored close: silver_tb_movements (#259) synthesises the entity layer's
    P&L-to-retained-earnings entry in the year's Closing period, and the journal_close layer of
    gold_fully_consolidated_tb (#316) does the same for the journal layers. Nothing closes a Regular
    period or a quarter: a month-end or quarter-end figure is READ from the period movements (a running
    sum, gold_ytd_trial_balance), never written. This test holds the entity layer to that, per
    period, on the declared calendar (declared_periods(): Opening, Regular, Closing, Adjustment):

      close_outside_closing_period     (a) a 'year_end_close' row of silver_tb_movements in a period
                                       the calendar does not declare as Closing. Only the year end
                                       clears P&L; a close in a Regular period would zero the P&L of
                                       every period after it.
      pnl_not_carried_forward          (a) for an entity filing 'Year-to-date movement' or
                                       'Period-end balance', the reported P&L YTD
                                       (gold_ytd_trial_balance.ytd_net_amount) at a Regular period the
                                       entity claimed differs from the P&L figure its file states
                                       there, per (entity, year, period, account, <dimensions>),
                                       partners summed. Both bases state the year's P&L to date, so
                                       the two must tie in every Regular period: a balance carried
                                       wrongly over a period boundary (zeroed, doubled, or the prior
                                       year's result left in, e.g. a year with no Closing period
                                       declared) shows up here, in the period it lands in.
      closing_period_phantom_movement  (d) a movement in a declared Closing period on an account that
                                       is neither P&L nor the retained-earnings key (partner ''), for
                                       a stated-figure basis ('Year-to-date movement', 'Period-end
                                       balance'). konsol declares the Closing period as a one-day
                                       period on the last Regular period's last day; a balance sheet
                                       cannot move between two figures stated for the same day. A
                                       synthesised close row is judged too
                                       (assert_year_end_close_invents_no_movement already names
                                       those); this rule also covers a batch the entity claimed in
                                       the Closing period.
      opening_period_pnl_movement      (e) a P&L movement in a declared Opening period, any basis.
                                       The Opening period carries the balance sheet into the year;
                                       no result is earned on the eve of the year.
      opening_period_balance_movement  (e) a 'Period-end balance' entity whose balance sheet moves in
                                       a declared Opening period: its balances there are the prior
                                       year's closed balances, so the difference must be 0. The
                                       entity's first claimed period is not judged (its movement is
                                       its balance from inception).
      pnl_after_closing_period         (e) entity-layer P&L in a period AFTER the year's Closing period
                                       (an Adjustment period, P14) of a year the entity has filed a
                                       later year for, |sum| > materiality_floor() per (entity, year,
                                       account): the close sums the year to the Closing period, so it
                                       stays open. The entity-layer twin of
                                       assert_journal_pnl_closed_at_year_end's after_closing.

    The YTD spine itself ((b): vanished and new keys) is assert_period_close_ytd_spine; quarter-end
    snapshots ((c)) are assert_period_close_quarter_snapshot.

    Not judged: the calendar's own shape (that a Closing period is declared on its year's last Regular
    day). konsol owns the calendar and a scratch or partial calendar (CI's declares FY2026 P1 and P13
    only) cannot tell a misplaced Closing day from undeclared Regular periods; open question on the
    issue. A 'Period movement' entity's Closing and Opening balance-sheet rows (an ERP that exports
    its own closing/opening transactions as movements, D365's, legitimately moves the balance sheet
    out in P13 and back in P0; open question on the issue). Periods the calendar does not
    declare (assert_trial_balance_period_declared names them). The Closing period is the first
    period_type = 'Closing' of the year, as silver_tb_movements finds it.

    Tolerance 0.01 per row, as for the other movement tests; materiality_floor() for the per-year
    after-closing sum, as for the journal close.
    Fixtures: test_fixtures/assert_period_close_integrity.*.sql
#}

{{ config(severity='error') }}

with calendar as (
    select fiscal_year, fiscal_period, period_type, start_date, end_date
    from {{ declared_periods() }}
),

closing_periods as (
    select fiscal_year, min(fiscal_period) as closing_period
    from calendar
    where period_type = 'Closing'
    group by fiscal_year
),

{# every entity movement with its declared period type ('' when undeclared) and its account flags #}
movements as (
    select
        m.data_area_id as data_area_id,
        toUInt16(m.fiscal_year) as fiscal_year,
        toUInt16(m.fiscal_period) as fiscal_period,
        m.main_account as main_account,
        m.partner_data_area_id as partner_data_area_id,
        m.amount_basis as amount_basis,
        m.movement_kind as movement_kind,
        m.movement_amount as movement_amount,
        c.period_type as period_type,
        ma.is_pnl as is_pnl,
        ma.is_retained_earnings as is_retained_earnings
    from {{ ref('silver_tb_movements') }} as m
    left join calendar as c
        on c.fiscal_year = toUInt16(m.fiscal_year)
        and c.fiscal_period = toUInt16(m.fiscal_period)
    left join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = m.main_account
),

entity_span as (
    select
        data_area_id,
        max(fiscal_year) as last_year,
        min((fiscal_year, fiscal_period)) as first_claimed
    from movements
    where movement_kind = 'activity'
    group by data_area_id
),

close_outside_closing_period as (
    select
        data_area_id, fiscal_year, fiscal_period, main_account,
        movement_amount as difference,
        'close_outside_closing_period' as reason
    from movements
    where movement_kind = 'year_end_close'
      and period_type != 'Closing'
),

{# (a) the stated P&L to date: what a YTD or period-end-balance file says at a Regular period #}
claimed_stated_periods as (
    select
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        argMax(amount_basis, claimed_at) as amount_basis
    from {{ ref('bronze_trial_balance_submissions') }}
    group by data_area_id, fiscal_year, fiscal_period
    having amount_basis in ('Year-to-date movement', 'Period-end balance')
),

pnl_legs as (
    select
        b.data_area_id as data_area_id,
        toUInt16(b.fiscal_year) as fiscal_year,
        toUInt16(b.fiscal_period) as fiscal_period,
        b.main_account as main_account,
        {{ dim_select(prefix='b.', trailing=true) }}
        toDecimal128(b.debit_amount - b.credit_amount, {{ amount_scale() }}) as amount
    from {{ ref('bronze_trial_balance_submissions') }} as b
    inner join claimed_stated_periods as p
        on p.data_area_id = b.data_area_id
        and p.fiscal_year = toUInt16(b.fiscal_year)
        and p.fiscal_period = toUInt16(b.fiscal_period)
    inner join calendar as c
        on c.fiscal_year = p.fiscal_year
        and c.fiscal_period = p.fiscal_period
    inner join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = b.main_account
    where c.period_type = 'Regular'
      and ma.is_pnl = 1

    union all

    {# minus what is reported, at the same claimed Regular periods #}
    select
        y.data_area_id as data_area_id,
        toUInt16(y.fiscal_year) as fiscal_year,
        toUInt16(y.fiscal_period) as fiscal_period,
        y.main_account as main_account,
        {{ dim_select(prefix='y.', trailing=true) }}
        toDecimal128(-y.ytd_net_amount, {{ amount_scale() }}) as amount
    from {{ ref('gold_ytd_trial_balance') }} as y
    inner join claimed_stated_periods as p
        on p.data_area_id = y.data_area_id
        and p.fiscal_year = toUInt16(y.fiscal_year)
        and p.fiscal_period = toUInt16(y.fiscal_period)
    inner join calendar as c
        on c.fiscal_year = p.fiscal_year
        and c.fiscal_period = p.fiscal_period
    where c.period_type = 'Regular'
      and y.is_pnl = 1
),

pnl_not_carried_forward as (
    select
        data_area_id, fiscal_year, fiscal_period, main_account,
        sum(amount) as difference,
        'pnl_not_carried_forward' as reason
    from pnl_legs
    group by data_area_id, fiscal_year, fiscal_period, main_account{{ dim_group_by(leading=true) }}
    having abs(sum(amount)) > 0.01
),

closing_period_phantom_movement as (
    select
        data_area_id, fiscal_year, fiscal_period, main_account,
        movement_amount as difference,
        'closing_period_phantom_movement' as reason
    from movements
    where period_type = 'Closing'
      and amount_basis in ('Year-to-date movement', 'Period-end balance')
      and is_pnl != 1
      and not (is_retained_earnings = 1 and partner_data_area_id = '')
      and abs(movement_amount) > 0.01
),

opening_period_pnl_movement as (
    select
        data_area_id, fiscal_year, fiscal_period, main_account,
        movement_amount as difference,
        'opening_period_pnl_movement' as reason
    from movements
    where period_type = 'Opening'
      and is_pnl = 1
      and abs(movement_amount) > 0.01
),

opening_period_balance_movement as (
    select
        m.data_area_id as data_area_id,
        m.fiscal_year as fiscal_year,
        m.fiscal_period as fiscal_period,
        m.main_account as main_account,
        m.movement_amount as difference,
        'opening_period_balance_movement' as reason
    from movements as m
    inner join entity_span as e on e.data_area_id = m.data_area_id
    where m.period_type = 'Opening'
      and m.amount_basis = 'Period-end balance'
      and m.is_pnl != 1
      and (m.fiscal_year, m.fiscal_period) != e.first_claimed
      and abs(m.movement_amount) > 0.01
),

pnl_after_closing_period as (
    select
        m.data_area_id as data_area_id,
        m.fiscal_year as fiscal_year,
        toUInt16(0) as fiscal_period,
        m.main_account as main_account,
        sum(m.movement_amount) as difference,
        'pnl_after_closing_period' as reason
    from movements as m
    inner join closing_periods as cp on cp.fiscal_year = m.fiscal_year
    inner join entity_span as e on e.data_area_id = m.data_area_id
    where m.fiscal_period > cp.closing_period
      and m.fiscal_year < e.last_year
      and m.is_pnl = 1
    group by m.data_area_id, m.fiscal_year, m.main_account
    having abs(sum(m.movement_amount)) > {{ materiality_floor() }}
)

select * from close_outside_closing_period
union all
select * from pnl_not_carried_forward
union all
select * from closing_period_phantom_movement
union all
select * from opening_period_pnl_movement
union all
select * from opening_period_balance_movement
union all
select * from pnl_after_closing_period
