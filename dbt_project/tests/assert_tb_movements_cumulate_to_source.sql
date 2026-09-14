{#
    Normalised movements add back up to what the batch declared (konsolidat#199).

    silver_tb_movements rewrites every batch as period movements from its
    declared amount_basis. Undoing that rewrite must give the source figure
    back, per key (entity, account, partner) and period:

      'Period movement'        movement                              = source net
      'Year-to-date movement'  running sum within the fiscal year    = source net
      'Period-end balance'     running sum over every period         = source net

    A key that vanished from a later batch has a row here only because the
    model's spine put one there (source net 0, movement minus the previous
    figure), and that row's running sum comes back to 0 as any other. This
    test judges the rows that exist; a spine that MISSED the vanished key
    would leave no row to judge, and it is assert_tb_movements_balance that
    catches that (the period no longer sums to 0).

    The synthetic year-end close of a period-end-balance file (PR 200
    finding 1) passes for the same reason: its rows carry the post-close
    balance as source_net_amount (0 for a P&L key, the year's result added
    to retained earnings), so the running sum over every period still
    equals the source figure at each row.

    Rows whose basis is not one of the three strings are not judged here:
    assert_tb_submission_has_basis names them at the bronze layer and stops
    the build.

    Tolerance 0.01, as for the other balance tests.
#}

{{ config(severity='error') }}

with cumulated as (

    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        partner_data_area_id,
        amount_basis,
        source_net_amount,
        movement_amount,
        sum(movement_amount) over (
            partition by data_area_id, main_account, partner_data_area_id
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as running_all_periods,
        sum(movement_amount) over (
            partition by data_area_id, main_account, partner_data_area_id, fiscal_year
            order by fiscal_period
            rows between unbounded preceding and current row
        ) as running_fiscal_year
    from {{ ref('silver_tb_movements') }}

)

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    partner_data_area_id,
    amount_basis,
    source_net_amount,
    multiIf(
        amount_basis = 'Period movement', movement_amount,
        amount_basis = 'Year-to-date movement', running_fiscal_year,
        running_all_periods
    ) as cumulated_amount,
    round(cumulated_amount - source_net_amount, 2) as difference
from cumulated
where amount_basis in ('Period movement', 'Year-to-date movement', 'Period-end balance')
  and abs(difference) > 0.01
