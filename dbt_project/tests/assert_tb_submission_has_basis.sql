{#
    Every claimed trial-balance batch declares what its amounts ARE (konsolidat#199).

    An ERP exports period movements, year-to-date movements or period-end
    balances, and the numbers alone cannot tell which. konsol writes the
    declared basis on the claim row (`amount_basis`); silver_tb_movements
    normalises each batch to period movements from it. A batch with no basis
    ('' — claimed before the column existed, or by another path) or with a
    value outside the three known strings cannot be normalised, and guessing
    would silently misstate every downstream balance. So this is an error:
    the build stops and names the batch until its basis is declared.
#}

{{ config(severity='error') }}

select
    batch_id,
    submission_name,
    data_area_id,
    fiscal_year,
    fiscal_period,
    amount_basis
from {{ ref('bronze_trial_balance_submissions') }}
where amount_basis not in ('Period movement', 'Year-to-date movement', 'Period-end balance')
group by batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, amount_basis
