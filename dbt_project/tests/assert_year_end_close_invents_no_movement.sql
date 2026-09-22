{#
    The synthesised year-end close moves only what a close moves (konsol#255).

    silver_tb_movements synthesises a post-close period for a 'Period-end
    balance' entity-year (PR 200 finding 1). By its own design — the grain note
    at the top of that model — the close period carries the last claimed
    period's balances with the P&L keys set to 0 and the year's result added to
    retained earnings. So exactly THREE kinds of movement may come out of it:

      - a P&L key, reversed             (silver_main_accounts.is_pnl = 1)
      - the retained-earnings key, partner '' (is_retained_earnings = 1)
      - every other key: the SAME figure it already had, which differences to 0
        and is dropped again

    This test judges the third kind. A 'year_end_close' row on a non-P&L,
    non-retained key that carries a movement is a balance the close INVENTED:
    no file ever claimed it, and it is added to the account's cumulative balance
    for every period that follows.

    KNOWN RED at konsol#255 row 14. Row 7b widened the differencing windows with
    the declared dimensions, but the close is still computed on the un-widened
    key and still carries BLANK dimension values (close_keys / close_source /
    close_spine, and the grain note says so). The two halves contradict on an
    account that a file splits across dimension values: close_source sums that
    account back to its WHOLE balance, while the widened lagInFrame differences
    the blank-dimensioned close row against the blank SLICE's previous figure —
    zero, because the account has no blank slice. The close then emits the whole
    balance as a movement out of nothing. Measured on
    assert_year_end_close_invents_no_movement.must_flag.sql (the dimensioned
    twin of silver_tb_movements.year_end_close.sql): account ZZ1000, split 60/40
    across two cost centres and unchanged between FY2024 P12 and FY2025 P1, gets
    a close row of source 100 / movement +100, and cumulates to 200 against a
    stated balance of 100.

    Deciding what a close SHOULD do per dimension value is
    `Dimension.survives_close` (decision of 22 Sep 2026, option #255-3,
    https://github.com/grynn-in/konsol/issues/255#issuecomment-5781879795),
    which is not yet exposed to dbt. This test does not presume that answer: it
    only says that whatever the close does, it may not create a balance the
    source never stated.

    Why the existing suite cannot see it. The invented rows come in pairs that
    net to zero whenever the split assets have split liabilities behind them
    (they are the same balances, differenced the same wrong way), so the
    entity-period still sums to zero and assert_tb_movements_balance passes.
    assert_tb_movements_cumulate_to_source runs its running sums on the FULL
    key, and the invented row is the only row of the blank slice, so its running
    sum equals its own source figure — exact, and green.
    assert_tb_movements_difference_within_dimension excludes 'year_end_close'
    rows and their successors, deliberately and in writing. All three are
    measured green on this test's fixture.

    NOT judged here, and a separate symptom of the same contradiction: a P&L
    account that a file SPLITS across dimension values is never reversed at all
    (its blank close row is 0 against a blank predecessor of 0 and is dropped),
    so the next year's first period reads last year's expense as activity.
    That is an under-close, not an invention, and it is
    assert_year_end_close_carried's neighbourhood.

    Quiet where it must be quiet, by construction rather than by a guard:
      - a site that declares no dimensions: every key has one series, so the
        close row and the balance it carries sit in the same window partition
        and difference to 0 — there is nothing to return. No `dimensions` guard
        and no dimension column is referenced, so this test renders identically
        whatever the var holds;
      - a 'Period movement' or 'Year-to-date movement' entity: no close is
        synthesised for it at all;
      - an entity whose accounts are not split: same single series as above.

    Tolerance 0.01, as for the other movement tests.
#}

{{ config(severity='error') }}

select
    m.data_area_id as data_area_id,
    m.fiscal_year as fiscal_year,
    m.fiscal_period as fiscal_period,
    m.main_account as main_account,
    m.partner_data_area_id as partner_data_area_id,
    m.source_net_amount as source_net_amount,
    {# the figure the close differenced against, exact, from the model's own
       arithmetic — no window here can disagree with it #}
    m.source_net_amount - m.movement_amount as previous_net_used,
    m.movement_amount as invented_movement
from {{ ref('silver_tb_movements') }} as m
inner join {{ ref('silver_main_accounts') }} as ma
    on ma.main_account_id = m.main_account
where m.movement_kind = 'year_end_close'
  and ma.is_pnl = 0
  and not (ma.is_retained_earnings = 1 and m.partner_data_area_id = '')
  and abs(m.movement_amount) > 0.01
