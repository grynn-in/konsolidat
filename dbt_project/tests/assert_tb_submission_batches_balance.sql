{#
    Every claimed trial-balance batch must balance: sum(debit) = sum(credit)
    within a small rounding tolerance.

    konsol validates this exactly, at the currency's own minor unit, before a
    submission can be submitted (konsol#180), so a failure means rows were
    landed or altered outside the doctype flow. Defense in depth for the one
    property that makes a trial balance a trial balance.

    #256: bronze keeps amounts at amount_scale() (4 places), and the sums are
    not rounded here, so a three-decimal currency's (BHD, KWD) third decimal
    reaches the comparison. Before #256 bronze rounded each line to cents: a
    balanced BHD batch could arrive unbalanced, and an unbalanced one could
    arrive balanced (fixtures assert_tb_submission_batches_balance.three_decimal*).
    The 0.01 tolerance is unchanged; a sub-cent imbalance is still below it.

    Aliases are defined once and reused — the displayed difference is by
    construction the number the HAVING fired on.
#}

select
    batch_id,
    any(submission_name) as submission_name,
    sum(debit_amount) as total_debit,
    sum(credit_amount) as total_credit,
    total_debit - total_credit as difference
from {{ ref('bronze_trial_balance_submissions') }}
group by batch_id
having abs(difference) > 0.01
