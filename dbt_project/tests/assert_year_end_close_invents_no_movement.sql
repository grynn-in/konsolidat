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

    RED at konsol#255 row 14, GREEN at row 17. Row 7b widened the differencing
    windows with the declared dimensions but left the close computed on the
    un-widened key and carrying BLANK dimension values, and the two halves
    contradicted on an account that a file splits across dimension values:
    close_source summed that account back to its WHOLE balance, while the
    widened lagInFrame differenced the blank-dimensioned close row against the
    blank SLICE's previous figure — zero, because a split account has no blank
    slice. The close emitted the whole balance as a movement out of nothing.
    Measured on assert_year_end_close_invents_no_movement.must_flag.sql (the
    dimensioned twin of silver_tb_movements.year_end_close.sql): account ZZ1000,
    split 60/40 across two declared dimension values and unchanged between
    FY2024 P12 and FY2025 P1, got a close row of source 100 / movement +100 and
    cumulated to 200 against a stated balance of 100. Row 17 put close_spine on
    the same widened key as every other row; the same fixture now emits no close
    row for ZZ1000 at all and it cumulates to 60 + 40 = 100.

    What a close does per dimension value is settled: the year's result moves
    into retained earnings as ONE undimensioned lump (decision of 23 September
    2026, Deepak Pai, konsol#255 — the OFF default of
    `Dimension.survives_close`). This test does not rest on that answer: it only
    says that whatever the close does, it may not create a balance the source
    never stated, and it would hold just as well if the lump were dimensioned.

    Why the existing suite cannot see it. The invented rows come in pairs that
    net to zero whenever the split assets have split liabilities behind them
    (they are the same balances, differenced the same wrong way), so the
    entity-period still sums to zero and assert_tb_movements_balance passes.
    assert_tb_movements_cumulate_to_source runs its running sums on the FULL
    key, and the invented row is the only row of the blank slice, so its running
    sum equals its own source figure — exact, and green.
    assert_tb_movements_difference_within_dimension excludes 'year_end_close'
    rows and their successors, deliberately and in writing. All three were
    measured green on this test's fixture while it was red.

    NOT judged here, and the other symptom of the same contradiction: a P&L
    account that a file SPLITS across dimension values was never reversed at all
    (its blank close row was 0 against a blank predecessor of 0 and was
    dropped), so the next year's first period read last year's result as
    activity. That is an under-close, not an invention, and it is caught by
    assert_tb_movements_balance — the close period was short by the result and
    the next first period long by it. Its fixture is
    assert_tb_movements_balance.split_pnl_close.must_flag.sql, added at row 17.

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
