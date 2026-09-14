{#
    Normalised trial-balance movements balance within every entity-period
    (konsolidat#199).

    Every claimed batch balances (assert_tb_submission_batches_balance), and
    silver_tb_movements turns balances or year-to-date figures into period
    movements by differencing against the previous period over a spine that
    also carries the keys that vanished. A difference of two balanced sets is
    balanced, so a non-zero sum here means the spine or the differencing
    dropped or double-counted a key — an error that would unbalance every
    downstream statement.

    Aliases are defined once and reused — the displayed total is by
    construction the number the HAVING fired on.
#}

{{ config(severity='error') }}

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    any(amount_basis) as amount_basis,
    round(sum(movement_amount), 2) as total_movement
from {{ ref('silver_tb_movements') }}
group by data_area_id, fiscal_year, fiscal_period
having abs(total_movement) > 0.01
